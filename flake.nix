{
  description = "OpenFOAM (ESI/OpenCFD) built from source, with optional MPI, decomposition, I/O and visualization components";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f: lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});

      # Build an OpenFOAM variant. See nix/openfoam/mk.nix for the full
      # list of options and their defaults.
      mkOpenFOAM = pkgs: args: import ./nix/openfoam/mk.nix { inherit pkgs; } args;

      presets = {
        default = { };
        minimal = {
          mpi = null;
          scotch = false;
          ptscotch = false;
          metis = false;
          kahip = false;
          fftw = false;
        };
        full = {
          cgal = true;
          petsc = true;
          adios2 = true;
          paraview = true;
          docs = true;
        };
      };

      mkDevShell =
        pkgs: of:
        pkgs.mkShell {
          name = "openfoam-${of.version}-env";

          packages = [
            of
            pkgs.gcc
            pkgs.gnumake
            pkgs.binutils
            pkgs.flex
            pkgs.bison
            pkgs.m4
            pkgs.gawk
            pkgs.gdb
            pkgs.valgrind
            pkgs.ccache
            pkgs.cmake
            pkgs.gnuplot
            pkgs.which
            pkgs.python3
            pkgs.zlib.dev
            pkgs.readline.dev
          ]
          ++ lib.optional (of.paraview != null) of.paraview;

          shellHook = ''
            # Sourcing the upstream environment is the canonical way to use
            # OpenFOAM; it sets PATH, LD_LIBRARY_PATH, FOAM_* variables, ...
            source "${of}/${of.projectDir}/etc/bashrc"
          '';
        };
    in
    {
      # ------------------------------------------------------------------
      # Library API
      # ------------------------------------------------------------------
      lib = {
        inherit mkOpenFOAM;

        # The feature set used by `packages.<system>.openfoam` / the overlay.
        defaultFeatures = presets.default;
      };

      # ------------------------------------------------------------------
      # Packages
      # ------------------------------------------------------------------
      packages = forAllSystems (
        system: pkgs:
        let
          mk = mkOpenFOAM pkgs;
        in
        {
          default = mk presets.default;
          openfoam = mk presets.default;
          openfoamMinimal = mk presets.minimal;
          openfoamFull = mk presets.full;
        }
      );

      # ------------------------------------------------------------------
      # Development shells
      # ------------------------------------------------------------------
      devShells = forAllSystems (
        system: pkgs:
        let
          mk = mkOpenFOAM pkgs;
        in
        {
          default = mkDevShell pkgs (mk presets.default);
          minimal = mkDevShell pkgs (mk presets.minimal);
          full = mkDevShell pkgs (mk presets.full);
        }
      );

      # ------------------------------------------------------------------
      # Overlay: `nixpkgs.overlays = [ inputs.nix-openfoam.overlays.default ];`
      # then `pkgs.openfoam`, `pkgs.openfoamMinimal`, `pkgs.openfoamFull`.
      # ------------------------------------------------------------------
      overlays.default = final: prev: {
        openfoam = mkOpenFOAM final presets.default;
        openfoamMinimal = mkOpenFOAM final presets.minimal;
        openfoamFull = mkOpenFOAM final presets.full;
      };

      # ------------------------------------------------------------------
      # NixOS module
      # ------------------------------------------------------------------
      nixosModules.default = import ./nix/nixos-module.nix { inherit self; };

      # ------------------------------------------------------------------
      # Formatting and checks
      # ------------------------------------------------------------------
      formatter = forAllSystems (system: pkgs: pkgs.nixfmt);

      checks = forAllSystems (
        system: pkgs:
        let
          openfoam = self.packages.${system}.openfoam;
        in
        {
          inherit openfoam;
        }
      );
    };
}
