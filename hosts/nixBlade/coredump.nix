{ ... }:
# Cap what systemd-coredump will capture.
#
# An Electron app's dump is its whole address space, read, zstd-compressed and
# written through dm-crypt onto btrfs. On 2026-09-14 a run of graphide (gred)
# segfaults plus one librewolf crash queued several of those in ten minutes:
# IO pressure hit 54% full over five minutes, load reached 33 with the CPU 70%
# idle, and one graphide dump took 81 s to land.
#
# Past the cap the crash is still logged to the journal, with no dump.
{
  systemd.coredump.settings.Coredump = {
    ProcessSizeMax = "512M";
    ExternalSizeMax = "512M";
    MaxUse = "2G";
  };
}
