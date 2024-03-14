{ lib, pkgs, config, ... }:
{
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
    "nvidia-x11"
      "nvidia-settings"
      "nvidia-persistenced"
      "cudatoolkit"
      "cuda_cudart"
      "cudaPackages.cuda_cudart"
      config.boot.kernel.kernelPackages.nvidiaPackages.beta
    ];
  environment.systemPackages = [
  pkgs.unfree.cudatoolkit
  pkgs.unfree.cudaPackages.cuda_cudart
  ];
  nixpkgs.config.cudaSupport = true;

  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };
  services.xserver.videoDrivers = ["nvidia"];

  hardware.nvidia = {

    modesetting.enable = true;

    prime = {
      # sync.enable = true;
      amdgpuBusId = "PCI:100:0:0";
      nvidiaBusId = "PCI:01:0:0";
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
    };
    powerManagement.enable = true;
    powerManagement.finegrained = true;

    open = false;

    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.beta;
  };
}
