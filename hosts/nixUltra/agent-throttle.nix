# Keep the desktop usable while agents and nix builds run at once. Same shape
# as hosts/nixBlade/agent-throttle.nix, sized for 24 threads.
{ ... }:
{
  # The claude and codex wrappers in term/ai/accounts.nix start each session
  # here. The quota is for all sessions together and keeps four threads free.
  systemd.user.slices.agents = {
    description = "Coding agents and everything they spawn";
    sliceConfig = {
      CPUWeight = 30;
      CPUQuota = "2000%";
      IOWeight = 30;
    };
  };

  # The defaults (cores = 0, max-jobs = auto) let one home build run 24 jobs
  # of 24 threads each: 45 rustc at once and a load past 120.
  nix.settings = {
    cores = 8;
    max-jobs = 2;
  };
  # Builds run under nix-daemon, out of reach of agents.slice.
  systemd.services.nix-daemon.serviceConfig = {
    CPUWeight = 30;
    IOWeight = 30;
    CPUQuota = "1600%";
  };
}
