{ ... }:
# An Electron app's core dump is its whole address space, compressed and
# written through dm-crypt; a few in a row stall the machine on IO. Past the
# cap a crash is still logged, just without the dump.
{
  systemd.coredump.settings.Coredump = {
    ProcessSizeMax = "512M";
    ExternalSizeMax = "512M";
    MaxUse = "2G";
  };
}
