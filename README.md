# nix-openfoam

A Nix flake that builds [OpenFOAM](https://www.openfoam.com) (the ESI /
OpenCFD line) from source, with the optional third-party components wired
in as ordinary flake/package options.

The flake currently packages **OpenFOAM v2606**. Everything is built with
Nixpkgs' toolchain and libraries; there is no FHS sandbox or vendor binary
pack.

## Quick start

```sh
# Core build: OpenMPI + Scotch/PT-Scotch + Metis + KaHIP + FFTW
nix build .#openfoam

# Enter the OpenFOAM environment (also provides gdb, valgrind, ccache,
# gnuplot, python3, ...)
nix develop

# ... or source the installed environment directly
source result/OpenFOAM-v2606/etc/bashrc

blockMesh
foamRun
mpirun -np 4 foamRun -parallel
```

Three presets are provided:

| Output | Description |
| --- | --- |
| `.#openfoam` (default) | MPI + Scotch/PT-Scotch, Metis, KaHIP, FFTW |
| `.#openfoamMinimal` | Serial build, no optional third-party libraries |
| `.#openfoamFull` | Everything below, including CGAL, PETSc, ADIOS2, ParaView and documentation |

Corresponding development shells are `nix develop .#minimal` and
`nix develop .#full`.

## Flake options

Build variants with `lib.mkOpenFOAM`, which takes a package set and an
attribute set of options:

| Option | Default | Description |
| --- | --- | --- |
| `mpi` | `"openmpi"` | MPI implementation: `"openmpi"`, `"mpich"` or `null` (serial) |
| `scotch` | `true` | Build the Scotch/PT-Scotch decomposition methods |
| `ptscotch` | `true` | Use the parallel Scotch interface (requires MPI) |
| `metis` | `true` | Build the Metis decomposition method |
| `kahip` | `true` | Build the KaHIP decomposition method |
| `fftw` | `true` | Link FFTW (used by a number of utilities) |
| `cgal` | `false` | CGAL support, needed by `foamyMesh` utilities |
| `petsc` | `false` | PETSc support (builds the `external-solver` module, i.e. `petsc4Foam`) |
| `adios2` | `false` | ADIOS2 I/O (builds the `adios` module) |
| `paraview` | `false` | ParaView reader/plugins (builds the `visualization` module) |
| `modules` | `[]` | Extra modules: `"visualization"`, `"external-solver"`, `"adios"`, `"OpenQBMM"` |
| `docs` | `false` | Build the Doxygen documentation |
| `precision` | `"DP"` | `"DP"` (double) or `"SP"` (single) precision |
| `labelSize` | `32` | `32` or `64` bit labels |
| `buildMode` | `"Opt"` | `"Opt"`, `"Debug"` or `"Prof"` |
| `openmp` | `false` | Build with OpenMP enabled |
| `strict` | `false` | Build with `wmake -strict` (warnings are errors) |
| `version` | `"v2606"` | Upstream release; only change together with `source` |
| `source` | `null` | Override the upstream source (a fetched derivation) |

The features imply the relevant modules: `paraview = true` adds
`visualization`, `petsc = true` adds `external-solver`, and
`adios2 = true` adds `adios`.

## Customising

### From another flake

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.nix-openfoam.url = "github:you/nix-openfoam";
  inputs.nix-openfoam.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, nix-openfoam }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      openfoam = nix-openfoam.lib.mkOpenFOAM pkgs {
        paraview = true;
        cgal = true;
      };
    in {
      packages.${system}.openfoam = openfoam;
    };
}
```

### With the overlay

```nix
{
  nixpkgs.overlays = [ inputs.nix-openfoam.overlays.default ];
  environment.systemPackages = [ pkgs.openfoamFull ];
  # or: pkgs.openfoam, pkgs.openfoamMinimal
}
```

### NixOS module

```nix
{
  imports = [ inputs.nix-openfoam.nixosModules.default ];

  programs.openfoam = {
    enable = true;
    package = inputs.nix-openfoam.packages.x86_64-linux.openfoamFull;
    extraPackages = [ pkgs.paraview pkgs.gmsh ];
  };
}
```

The module installs the package and (by default) sources
`etc/bashrc` from `/etc/profile.d/openfoam.sh` for interactive login
shells. Set `programs.openfoam.autoSource = false` if you prefer to
source it manually.

## Notes

- **Build time / memory.** A full OpenFOAM build is large. On a
  12-core/8 GB machine, prefer something like
  `nix build .#openfoam --cores 4`; the build is parallel and some
  translation units are memory hungry. Subsequent builds are cached.
- **No binary cache.** This package is not part of Nixpkgs, so the first
  build (and every change to the source/dependency closure) is compiled
  locally.
- **Environment.** OpenFOAM expects to be used after sourcing
  `etc/bashrc` (it sets `LD_LIBRARY_PATH`, `FOAM_*` variables and the
  relevant `PATH` entries). The package also installs two convenience
  wrappers, `$out/bin/openfoam` (interactive shell) and
  `$out/bin/foamExec` (run a command), both of which source the
  environment for you.
- **Site configuration.** Third-party paths are placed in
  `OpenFOAM-v2606/site/etc/config.sh/`, which OpenFOAM gives precedence
  over the shipped defaults. You can still override any of them per-user
  in `~/.OpenFOAM/config.sh/...` or `~/.OpenFOAM/prefs.sh`.
- **ParaView.** With `paraview = true`, the plugins are built against the
  Nixpkgs ParaView and installed under
  `OpenFOAM-v2606/platforms/linux64GccDPInt32Opt/lib/paraview-X.Y`.
  Use a shell that has `paraview` on `PATH` (the dev shell does) so that
  OpenFOAM's environment can locate it. The ParaView reader libraries are
  built; the optional GUI property-widget plugin is best-effort and may be
  skipped by the upstream CMake files when ParaView 6 / Qt6 is used (they
  contain Qt5-only CMake calls). ParaView's built-in OpenFOAM reader is
  unaffected.
- **Updating.** Change `nix/openfoam/sources.nix` (version, URL and
  hash). Use `nix-prefetch-url --unpack` or `nix store prefetch-file` to
  obtain the new hash.

## Layout

```
flake.nix                  flake outputs, presets, dev shells, overlay
nix/openfoam/default.nix   the build recipe (upstream Allwmake wrapper)
nix/openfoam/mk.nix        feature resolution (options -> package args)
nix/openfoam/sources.nix   upstream version and source hash
nix/nixos-module.nix       NixOS module
```

## License

OpenFOAM is distributed under the GNU General Public License v3 or later.
The packaging expression in this repository follows the same license.