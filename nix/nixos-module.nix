{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.openfoam;
  system = pkgs.stdenv.hostPlatform.system;
in
{
  options.programs.openfoam = {
    enable = lib.mkEnableOption "the OpenFOAM CFD toolbox environment";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${system}.openfoam;
      defaultText = lib.literalExpression "inputs.nix-openfoam.packages.\${system}.openfoam";
      description = ''
        The OpenFOAM package to install. Use `lib.mkOpenFOAM` or one of the
        presets (`openfoamMinimal`, `openfoamFull`) to customise it.
      '';
    };

    projectSubdir = lib.mkOption {
      type = lib.types.str;
      default = "OpenFOAM-v2606";
      description = "Directory inside the package that contains the OpenFOAM tree.";
    };

    autoSource = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Source OpenFOAM's `etc/bashrc` from `/etc/profile.d` for interactive
        login shells.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.paraview pkgs.gmsh ]";
      description = "Additional packages to install alongside OpenFOAM.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ] ++ cfg.extraPackages;

    environment.sessionVariables.OPENFOAM_PREFIX = "${cfg.package}";

    environment.etc."profile.d/openfoam.sh" = lib.mkIf cfg.autoSource {
      text = ''
        # Source the OpenFOAM environment in interactive shells.
        if [ -r "${cfg.package}/${cfg.projectSubdir}/etc/bashrc" ]; then
          case "''${-}" in
            *i*) . "${cfg.package}/${cfg.projectSubdir}/etc/bashrc" ;;
          esac
        fi
      '';
    };
  };
}
