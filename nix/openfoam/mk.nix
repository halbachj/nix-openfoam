# Feature resolution for the OpenFOAM package.
#
# This turns a friendly, flat set of feature toggles into the package
# arguments consumed by ./default.nix.
{ pkgs, ... }:

let
  inherit (pkgs.lib) optional unique;

  defaults = {
    # Which OpenFOAM release to build. The flake pins v2606; only change
    # this if you also provide a matching `source` (and know what you are
    # doing).
    version = "v2606";
    source = null;

    # "openmpi", "mpich" or null (serial build)
    mpi = "openmpi";
    # Only used with `scotch = true`
    ptscotch = true;

    # Decomposition / numerics
    scotch = true;
    metis = true;
    kahip = true;
    fftw = true;

    # Larger optional integrations
    cgal = false; # required by the foamyMesh utilities
    petsc = false; # petsc4Foam, provided by the external-solver module
    adios2 = false; # ADIOS2 I/O, provided by the adios module
    paraview = false; # ParaView reader/plugins, visualization module

    # Extra modules: "visualization", "external-solver", "adios",
    # "OpenQBMM". Some modules are implied by the options above.
    modules = [ ];

    # Documentation (doxygen + graphviz)
    docs = false;

    # Build flavour
    precision = "DP"; # DP | SP
    labelSize = 32; # 32 | 64
    buildMode = "Opt"; # Opt | Debug | Prof
    openmp = false;
    strict = false;
  };

  mpiPackage =
    name:
    if name == null then
      null
    else if name == "mpich" then
      pkgs.mpich
    else if name == "openmpi" then
      pkgs.openmpi
    else
      throw "nix-openfoam: unknown MPI implementation '${name}' (expected \"openmpi\", \"mpich\" or null)";

  # Satisfies dependencies of libraries that always link an MPI
  # implementation, even when OpenFOAM itself is built serially.
  fallbackMpi = pkgs.mpich;

  check = cond: msg: if cond then true else throw "nix-openfoam: ${msg}";

  validate =
    cfg:
    check (
      cfg.mpi == null
      || builtins.elem cfg.mpi [
        "openmpi"
        "mpich"
      ]
    ) "mpi must be \"openmpi\", \"mpich\" or null"
    && check (builtins.elem cfg.precision [
      "DP"
      "SP"
    ]) "precision must be \"DP\" or \"SP\""
    && check (builtins.elem cfg.labelSize [
      32
      64
    ]) "labelSize must be 32 or 64"
    && check (builtins.elem cfg.buildMode [
      "Opt"
      "Debug"
      "Prof"
    ]) "buildMode must be one of \"Opt\", \"Debug\" or \"Prof\""
    && check (
      !(builtins.elem "external-solver" cfg.modules) || cfg.petsc
    ) "the 'external-solver' module requires `petsc = true`"
    && check (
      !(builtins.elem "adios" cfg.modules) || cfg.adios2
    ) "the 'adios' module requires `adios2 = true`";
in
userArgs:
let
  cfg = defaults // userArgs;

  mpiPkg = mpiPackage cfg.mpi;
  mpiOrFallback = if mpiPkg != null then mpiPkg else fallbackMpi;

  modules = unique (
    cfg.modules
    ++ optional cfg.paraview "visualization"
    ++ optional cfg.petsc "external-solver"
    ++ optional cfg.adios2 "adios"
  );
in
assert validate cfg;
pkgs.callPackage ./default.nix {
  mpiPkg = mpiPkg;
  mpiFlavor = if cfg.mpi == "mpich" then "mpich" else "openmpi";

  scotchPkg =
    if cfg.scotch then
      pkgs.scotch.override {
        withPtScotch = cfg.ptscotch && mpiPkg != null;
        mpi = mpiOrFallback;
      }
    else
      null;
  metisPkg = if cfg.metis then pkgs.metis else null;
  kahipPkg = if cfg.kahip then pkgs.kahip.override { mpi = mpiOrFallback; } else null;
  fftwPkg = if cfg.fftw then pkgs.fftw else null;

  cgalPkg = if cfg.cgal then pkgs.cgal else null;
  boostPkg = if cfg.cgal then pkgs.boost else null;
  gmpPkg = if cfg.cgal then pkgs.gmp else null;
  mpfrPkg = if cfg.cgal then pkgs.mpfr else null;

  adios2Pkg =
    if cfg.adios2 then
      pkgs.adios2.override {
        mpi = mpiOrFallback;
        mpiSupport = mpiPkg != null;
      }
    else
      null;
  petscPkg =
    if cfg.petsc then
      pkgs.petsc.override {
        mpi = mpiOrFallback;
        mpiSupport = mpiPkg != null;
      }
    else
      null;
  paraviewPkg = if cfg.paraview then pkgs.paraview else null;

  inherit modules;
  docs = cfg.docs;
  cmakePkg = if modules != [ ] then pkgs.cmake else null;
  doxygenPkg = if cfg.docs then pkgs.doxygen else null;
  graphvizPkg = if cfg.docs then pkgs.graphviz else null;

  precision = cfg.precision;
  labelSize = cfg.labelSize;
  compileOption = cfg.buildMode;
  openmp = cfg.openmp;
  strict = cfg.strict;

  version = cfg.version;
  source = cfg.source;
}
