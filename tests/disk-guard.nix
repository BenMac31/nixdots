{ pkgs, diskGuardModule }:
let
  writer = pkgs.writeShellScript "writer" ''
    i=0
    while :; do
      i=$((i + 1))
      head -c 4096 /dev/urandom >/data/writer/f$((i % 20000)) || true
      echo "$i" >/run/user/1000/count
      sleep 0.02
    done
  '';
in
pkgs.testers.runNixOSTest {
  name = "disk-guard";
  nodes.machine = { lib, pkgs, ... }: {
    imports = [ diskGuardModule ];
    virtualisation.memorySize = 2048;
    virtualisation.emptyDiskImages = [ 16384 ];
    environment.systemPackages = [ pkgs.btrfs-progs ];
    users.users.alice = {
      isNormalUser = true;
      uid = 1000;
      linger = true;
    };
    systemd.user.slices.agents.sliceConfig.IOWeight = 30;
    services.snapper.configs.data = {
      SUBVOLUME = "/data";
      TIMELINE_CREATE = false;
      TIMELINE_CLEANUP = true;
      TIMELINE_LIMIT_HOURLY = "10";
      TIMELINE_LIMIT_DAILY = "10";
    };
    services.diskGuard = {
      enable = true;
      mountPoint = "/data";
      user = "alice";
      targetGiB = 6;
      tightGiB = 4;
      criticalGiB = 2;
      metadataCriticalGiB = 1;
      trueFreeTightGiB = 1;
      trueFreeOkPercent = 5;
      ballast = {
        dir = "/data/ballast";
        sizeGiB = 2;
      };
      snapper.config = "data";
      purge.dirs = [ "/data/tmp" ];
      nixGc = false;
    };
    # The test runs the guard by hand.
    systemd.timers.disk-guard.wantedBy = lib.mkForce [ ];
  };

  testScript = ''
    import json

    GiB = 1 << 30

    def unalloc():
        return int(machine.succeed("btrfs filesystem usage -b /data | awk '/Device unallocated:/ { print $3 }'").strip())

    def state():
        return json.loads(machine.succeed("cat /run/disk-guard/state.json"))

    def count():
        return int(machine.succeed("cat /run/user/1000/count").strip())

    def guard():
        machine.succeed("systemctl start disk-guard")
        print(machine.succeed("journalctl -u disk-guard -b --no-pager -o cat | tail -40"))
        return state()

    def timeline_snapshots():
        out = machine.succeed("snapper -c data --csvout list --columns number,cleanup")
        return [l for l in out.splitlines() if l.endswith(",timeline")]

    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("user@1000.service")
    machine.succeed(
        "mkfs.btrfs -f /dev/vdb",
        "mkdir -p /data && mount -o noatime /dev/vdb /data",
        "btrfs subvolume create /data/.snapshots",
        "btrfs subvolume create /data/ballast",
        "mkdir -p /data/writer /data/fill /data/tmp && chown alice /data/writer",
        "touch /data/tmp/new && touch -d '2 days ago' /data/tmp/old",
    )

    with subtest("roomy disk: OK and the ballast appears"):
        s = guard()
        assert s["state"] == "OK", s
        assert s["ballast"], s
        machine.succeed("test $(stat -c %s /data/ballast/ballast) -eq $((2 << 30))")
        machine.succeed("lsattr /data/ballast/ballast | grep -q C")

    machine.succeed(
        "runuser -u alice -- env XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "
        "systemd-run --user --unit=writer --slice=agents.slice ${writer}"
    )
    machine.wait_until_succeeds("test -s /run/user/1000/count")

    with subtest("fill until metadata has almost nowhere to grow"):
        i = 0
        while unalloc() > 1536 << 20:
            machine.succeed(f"for j in $(seq {i} {i + 7}); do fallocate -l 64M /data/fill/$j; done")
            i += 8
        machine.succeed("sync")
        for k in range(3):
            machine.succeed(f"snapper -c data create -c timeline -d pre{k}")
        # Snapshots pre* pin these; the two after do not.
        machine.succeed(f"for j in $(seq 0 {i - 1}); do [ $((j % 3)) = 0 ] || rm -f /data/fill/$j; done; sync")
        for k in range(2):
            machine.succeed(f"snapper -c data create -c timeline -d post{k}")
        assert len(timeline_snapshots()) == 5
        before = unalloc()
        print(f"unallocated before the guard: {before / GiB:.2f} GiB")
        assert before < 2 * GiB

    with subtest("CRITICAL: freeze, drop ballast, prune, balance"):
        s = guard()
        after = unalloc()
        print(f"unallocated after the guard: {after / GiB:.2f} GiB")
        assert s["frozen"], s
        assert not s["ballast"], s
        machine.fail("test -e /data/ballast/ballast")
        assert len(timeline_snapshots()) == 2, timeline_snapshots()
        assert after > before + 2 * GiB, (before, after)
        machine.succeed("test \"$(cat /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/agents.slice/cgroup.freeze)\" = 1")
        machine.succeed("grep -q 'frozen 1' /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/agents.slice/cgroup.events")
        machine.succeed("test \"$(cat /run/disk-guard/notified)\" = 3")
        machine.fail("test -e /data/tmp/old")
        machine.succeed("test -e /data/tmp/new")
        c1 = count()
        machine.sleep(3)
        assert count() == c1, "writer kept running while frozen"

    with subtest("no auto-thaw: a second run leaves the slice frozen"):
        s = guard()
        assert s["frozen"], s

    with subtest("thaw resumes the writer"):
        print(machine.succeed("disk-guard status"))
        c1 = count()
        machine.succeed("disk-guard thaw")
        machine.wait_until_succeeds(f"test $(cat /run/user/1000/count) -gt {c1}", timeout=30)
        s = guard()
        assert not s["frozen"], s
        assert s["state"] == "OK", s

    with subtest("the filesystem never went read-only"):
        machine.succeed("findmnt -no OPTIONS /data | grep -q '^rw'")
        machine.fail("dmesg | grep -i 'forced readonly'")
        print(machine.succeed("btrfs filesystem usage /data"))
  '';
}
