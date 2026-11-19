# OpenFOAM (ESI / OpenCFD line) built from source.
#
# This is a fairly direct wrapper around the upstream `Allwmake` build
# system. Optional components are provided as separate derivations and
# wired in through Nix-generated OpenFOAM "site" configuration, which
# both the build and the runtime environment pick up automatically.
#
# Note: package-valued arguments carry a "Pkg" suffix so that `callPackage`
# does not silently auto-fill them from the package set.
{
  lib,
  stdenv,
  fetchurl,
  symlinkJoin,
  runCommand,
  writeText,
  flex,
  bison,
  m4,
  gawk,
  zlib,
  readline,
  # Optional tools
  cmakePkg ? null,
  doxygenPkg ? null,
  graphvizPkg ? null,
  # Optional components (pass null to disable)
  mpiPkg ? null,
  mpiFlavor ? "openmpi",
  scotchPkg ? null,
  metisPkg ? null,
  kahipPkg ? null,
  fftwPkg ? null,
  cgalPkg ? null,
  boostPkg ? null,
  gmpPkg ? null,
  mpfrPkg ? null,
  adios2Pkg ? null,
  petscPkg ? null,
  paraviewPkg ? null,
  # Modules to build (their dependencies should be supplied above)
  modules ? [ ],
  docs ? false,
  # Build flavour
  precision ? "DP", # DP | SP
  labelSize ? 32, # 32 | 64
  compileOption ? "Opt", # Opt | Debug | Prof
  openmp ? false,
  strict ? false,
  # Upstream source
  version ? "v2606",
  source ? null,
  ...
}:

let
  inherit (lib)
    optional
    optionalString
    concatStringsSep
    mapAttrsToList
    unique
    ;

  src = if source != null then source else fetchurl (import ./sources.nix).src;

  dirName = "OpenFOAM-${version}";

  # MPI prefix combining the dev (mpicc, headers) and out (libraries,
  # mpirun) outputs, so that users can compile their own OpenFOAM code in
  # the runtime environment.
  mpiPrefix = if hasMpi then toString (mergeOutputs mpiPkg) else null;

  hasMpi = mpiPkg != null;

  # Merge the outputs of a package into one prefix that has include/, lib/.
  # `lndir` (used by symlinkJoin) merges directories rather than failing on
  # collisions, which is exactly what we need for dev + out combinations.
  mergeOutputs =
    pkg:
    symlinkJoin {
      name = "${pkg.pname or pkg.name}-prefix";
      paths = unique [
        (lib.getLib pkg)
        (lib.getDev pkg)
      ];
    };

  scotchPrefix = if scotchPkg != null then toString (mergeOutputs scotchPkg) else null;
  fftwPrefix = if fftwPkg != null then toString (mergeOutputs fftwPkg) else null;
  boostPrefix = if boostPkg != null then toString (mergeOutputs boostPkg) else null;
  gmpPrefix = if gmpPkg != null then toString (mergeOutputs gmpPkg) else null;
  mpfrPrefix = if mpfrPkg != null then toString (mergeOutputs mpfrPkg) else null;

  wmArch =
    if stdenv.hostPlatform.isx86_64 then
      "linux64"
    else if stdenv.hostPlatform.isAarch64 then
      "linuxARM64"
    else
      throw "nix-openfoam: unsupported architecture ${stdenv.hostPlatform.system}";

  # Library directories to bake into DT_RUNPATH so that the OpenFOAM
  # libraries and executables work without relying on LD_LIBRARY_PATH for
  # third-party dependencies. OpenFOAM's own libraries are still found
  # through the environment sourced from etc/bashrc, as is customary.
  rpathLibs = unique (
    lib.optional hasMpi (lib.getLib mpiPkg)
    ++ lib.optional (scotchPkg != null) scotchPkg
    ++ lib.optional (metisPkg != null) metisPkg
    ++ lib.optional (kahipPkg != null) kahipPkg
    ++ lib.optional (fftwPkg != null) fftwPkg
    ++ lib.optional (cgalPkg != null) cgalPkg
    ++ lib.optional (boostPkg != null) boostPkg
    ++ lib.optional (gmpPkg != null) gmpPkg
    ++ lib.optional (mpfrPkg != null) mpfrPkg
    ++ lib.optional (adios2Pkg != null) adios2Pkg
    ++ lib.optional (petscPkg != null) petscPkg
    ++ lib.optional (paraviewPkg != null) paraviewPkg
  );
  rpathFlags = concatStringsSep " " (map (p: "-Wl,-rpath,${lib.getLib p}/lib") rpathLibs);

  # --------------------------------------------------------------------
  # OpenFOAM site configuration.
  #
  # Files placed in <project>/site/etc/config.sh/ take precedence over
  # the versions shipped in <project>/etc/config.sh/ but can still be
  # overridden per-user in ~/.OpenFOAM. They are used both while
  # compiling and when sourcing etc/bashrc at runtime.
  # --------------------------------------------------------------------
  siteFiles = {
    scotch =
      if scotchPkg != null then
        ''
          SCOTCH_VERSION=scotch-system
          export SCOTCH_ARCH_PATH="${scotchPrefix}"
          if command -v _foamAddLibAuto >/dev/null 2>&1; then
              _foamAddLibAuto "$SCOTCH_ARCH_PATH" "lib"
              _foamAddLibAuto "$SCOTCH_ARCH_PATH" "lib64"
          fi
        ''
      else
        ''
          SCOTCH_VERSION=scotch-none
          unset SCOTCH_ARCH_PATH PTSCOTCH_ARCH_PATH
        '';

    metis =
      if metisPkg != null then
        ''
          METIS_VERSION=metis-system
          export METIS_ARCH_PATH="${metisPkg}"
          if command -v _foamAddLibAuto >/dev/null 2>&1; then
              _foamAddLibAuto "$METIS_ARCH_PATH" "lib"
              _foamAddLibAuto "$METIS_ARCH_PATH" "lib64"
          fi
        ''
      else
        ''
          METIS_VERSION=metis-none
          unset METIS_ARCH_PATH
        '';

    kahip =
      if kahipPkg != null then
        ''
          KAHIP_VERSION=kahip-system
          export KAHIP_ARCH_PATH="${kahipPkg}"
          if command -v _foamAddLibAuto >/dev/null 2>&1; then
              _foamAddLibAuto "$KAHIP_ARCH_PATH" "lib"
              _foamAddLibAuto "$KAHIP_ARCH_PATH" "lib64"
          fi
        ''
      else
        ''
          KAHIP_VERSION=kahip-none
          unset KAHIP_ARCH_PATH
        '';

    FFTW =
      if fftwPkg != null then
        ''
          fftw_version=fftw-system
          export FFTW_ARCH_PATH="${fftwPrefix}"
          if command -v _foamAddLibAuto >/dev/null 2>&1; then
              _foamAddLibAuto "$FFTW_ARCH_PATH" "lib"
              _foamAddLibAuto "$FFTW_ARCH_PATH" "lib64"
          fi
        ''
      else
        ''
          fftw_version=fftw-none
          unset FFTW_ARCH_PATH
        '';

    CGAL =
      if cgalPkg != null then
        ''
          boost_version=boost-system
          cgal_version=cgal-system
          export BOOST_ARCH_PATH="${boostPrefix}"
          export CGAL_ARCH_PATH="${cgalPkg}"
          export GMP_ARCH_PATH="${gmpPrefix}"
          export MPFR_ARCH_PATH="${mpfrPrefix}"
          if command -v _foamAddLibAuto >/dev/null 2>&1; then
              _foamAddLibAuto "$BOOST_ARCH_PATH" "lib"
              _foamAddLibAuto "$CGAL_ARCH_PATH" "lib"
              _foamAddLibAuto "$GMP_ARCH_PATH" "lib"
              _foamAddLibAuto "$MPFR_ARCH_PATH" "lib"
          fi
        ''
      else
        ''
          boost_version=boost-none
          cgal_version=cgal-none
          unset BOOST_ARCH_PATH CGAL_ARCH_PATH GMP_ARCH_PATH MPFR_ARCH_PATH
        '';

    adios2 =
      if adios2Pkg != null then
        ''
          adios2_version=ADIOS2-system
          export ADIOS2_ARCH_PATH="${adios2Pkg}"
          if command -v _foamAddLibAuto >/dev/null 2>&1; then
              _foamAddLibAuto "$ADIOS2_ARCH_PATH" "lib"
          fi
        ''
      else
        ''
          adios2_version=ADIOS2-none
          unset ADIOS2_ARCH_PATH
        '';

    petsc =
      if petscPkg != null then
        ''
          petsc_version=petsc-system
          export PETSC_ARCH_PATH="${petscPkg}"
          if command -v _foamAddLibAuto >/dev/null 2>&1; then
              _foamAddLibAuto "$PETSC_ARCH_PATH" "lib"
          fi
        ''
      else
        ''
          petsc_version=petsc-none
          unset PETSC_ARCH_PATH
        '';

    # ParaView is picked up from the third-party layout; a symlink is
    # created below when the feature is enabled.
    paraview =
      if paraviewPkg != null then
        ''
          ParaView_VERSION=${lib.versions.majorMinor paraviewPkg.version}
          export ParaView_DIR="$WM_THIRD_PARTY_DIR/platforms/$WM_ARCH$WM_COMPILER/ParaView-$ParaView_VERSION"

          pv_api=$(echo "$ParaView_VERSION" | sed -e 's/^\([0-9]*\.[0-9]*\).*/\1/')
          pv_plugin_dir="$FOAM_LIBBIN/paraview-$pv_api"

          if [ -d "$ParaView_DIR" ]; then
              export PATH="$ParaView_DIR/bin:$PATH"
              for libDir in "lib$WM_COMPILER_LIB_ARCH" lib; do
                  if [ -d "$ParaView_DIR/$libDir/paraview-$pv_api" ]; then
                      export LD_LIBRARY_PATH="$ParaView_DIR/$libDir/paraview-$pv_api:$ParaView_DIR/$libDir:''${LD_LIBRARY_PATH:-}"
                      break
                  fi
              done
              # Export even if the directory does not exist yet: it is
              # created when the plugin module is built, and the versioned
              # name is how OpenFOAM discovers the plugin API version.
              export PV_PLUGIN_PATH="$pv_plugin_dir"
          fi
          unset pv_api pv_plugin_dir
        ''
      else
        ''
          ParaView_VERSION=none
          unset ParaView_DIR PV_PLUGIN_PATH
        '';
  };

  siteConfig = runCommand "openfoam-${version}-site-config" { } ''
    mkdir -p $out/etc/config.sh
    ${concatStringsSep "\n" (
      mapAttrsToList (
        name: content: "cp ${writeText "openfoam-site-${name}" content} $out/etc/config.sh/${name}"
      ) siteFiles
    )}
  '';

  mpiPrefs =
    if !hasMpi then
      ''
        export WM_MPLIB=dummy
        export FOAM_MPI=dummy
        unset MPI_ARCH_PATH MPI_HOME
      ''
    else if mpiFlavor == "mpich" then
      ''
        export WM_MPLIB=SYSTEMMPI
        export MPI_ARCH_PATH="${mpiPrefix}"
        export MPI_ARCH_FLAGS="-DMPICH_SKIP_MPICXX"
        export MPI_ARCH_INC="-isystem ${lib.getDev mpiPkg}/include"
        export MPI_ARCH_LIBS="-L${lib.getLib mpiPkg}/lib -lmpi"
      ''
    else
      ''
        export WM_MPLIB=SYSTEMOPENMPI
        export MPI_ARCH_PATH="${mpiPrefix}"
      '';

  prefsFile = writeText "openfoam-${version}-prefs.sh" ''
    # Generated by the nix-openfoam flake.
    #
    # User overrides can be placed in ~/.OpenFOAM/prefs.sh (they are
    # sourced after this file) or by setting WM_PROJECT_SITE.
    export WM_COMPILER_TYPE=system
    export WM_COMPILER=Gcc
    ${mpiPrefs}
    export WM_LABEL_SIZE=${toString labelSize}
    export WM_PRECISION_OPTION=${precision}
    export WM_COMPILE_OPTION=${compileOption}
  '';
in
stdenv.mkDerivation (finalAttrs: {
  pname = "openfoam";
  version = lib.removePrefix "v" version;

  inherit src;

  # A handful of helper scripts use #!/bin/bash, which is not available in
  # the build sandbox; point all interpreters at the nix store shells.
  postPatch = ''
    patchShebangs .

    # A few upstream scripts hard-code /bin/cat and /usr/bin/tee.
    grep -rl -- '/bin/cat' wmake etc modules 2>/dev/null | while read -r f; do
      sed -i 's|/bin/cat|cat|g' "$f"
    done
    substituteInPlace wmake/scripts/AllwmakeParseArguments \
      --replace-fail '/usr/bin/tee' 'tee'
  '';

  nativeBuildInputs = [
    flex
    bison
    m4
    gawk
  ]
  ++ optional hasMpi mpiPrefix
  ++ optional (modules != [ ] && cmakePkg != null) cmakePkg
  ++ optional (docs && doxygenPkg != null) doxygenPkg
  ++ optional (docs && graphvizPkg != null) graphvizPkg;

  buildInputs = [
    zlib
    readline
  ]
  ++ optional hasMpi mpiPkg
  ++ optional (scotchPkg != null) scotchPkg
  ++ optional (scotchPkg != null) (mergeOutputs scotchPkg)
  ++ optional (metisPkg != null) metisPkg
  ++ optional (kahipPkg != null) kahipPkg
  ++ optional (fftwPkg != null) fftwPkg
  ++ optional (fftwPkg != null) (mergeOutputs fftwPkg)
  ++ optional (cgalPkg != null) cgalPkg
  ++ optional (boostPkg != null) boostPkg
  ++ optional (boostPkg != null) (mergeOutputs boostPkg)
  ++ optional (gmpPkg != null) gmpPkg
  ++ optional (gmpPkg != null) (mergeOutputs gmpPkg)
  ++ optional (mpfrPkg != null) mpfrPkg
  ++ optional (mpfrPkg != null) (mergeOutputs mpfrPkg)
  ++ optional (adios2Pkg != null) adios2Pkg
  ++ optional (petscPkg != null) petscPkg
  ++ optional (paraviewPkg != null) paraviewPkg;

  # The upstream build system is entirely environment driven; there is
  # nothing to configure at the autotools/cmake level.
  configurePhase = ''
    runHook preConfigure

    cp -a ${siteConfig} site
    chmod -R u+w site
    cp ${prefsFile} etc/prefs.sh

    ${optionalString (paraviewPkg != null) ''
      # Present the nixpkgs ParaView in the layout that OpenFOAM expects.
      mkdir -p "ThirdParty/platforms/${wmArch}Gcc"
      ln -sfn "${paraviewPkg}" "ThirdParty/platforms/${wmArch}Gcc/ParaView-${lib.versions.majorMinor paraviewPkg.version}"
    ''}

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    # Keep $HOME writable; a few helper scripts assume it exists.
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"

    # shellcheck disable=SC1091
    source ./etc/bashrc

    export FOAM_EXTRA_LDFLAGS="${rpathFlags}"

    buildLog="$TMPDIR/build.log"

    echo "Building ${dirName} (''${WM_OPTIONS}) with ''${WM_MPLIB} ''${FOAM_MPI}"

    # OpenFOAM's own -log option uses /usr/bin/tee, which does not exist
    # in the Nix sandbox. Redirect explicitly instead, and dump the tail
    # of the log if something goes wrong.
    # The top-level Allwmake builds *all* modules when a module prefix is
    # set. Disable that here and build exactly the requested modules below.
    export FOAM_MODULE_PREFIX=none

    if ! ./Allwmake \
        -j"''${NIX_BUILD_CORES:-1}" \
        -s -q \
        ${optionalString openmp "-openmp"} \
        ${optionalString strict "-strict"} \
        > "$buildLog" 2>&1
    then
      echo "===== OpenFOAM build failed; tail of $buildLog ====="
      tail -n 300 "$buildLog" || true
      echo "===== end of log ====="
      exit 1
    fi

    # Individual modules are built separately so that the flake can pick
    # exactly the ones requested (the top-level Allwmake builds them all
    # when modules are enabled).
    ${optionalString (modules != [ ]) ''
      for module in ${concatStringsSep " " modules}; do
        echo "Building OpenFOAM module: $module"
        moduleLog="$TMPDIR/module-$module.log"

        # The visualization module bundles optional components (Catalyst,
        # ParaView GUI plugin, runTimePostProcessing). Upstream treats those
        # as best-effort, so do the same; the reader libraries are the
        # important part. Dependencies such as PETSc/ADIOS are required.
        moduleEnv=""
        moduleRequired=true
        if [ "$module" = visualization ]; then
          moduleEnv="WM_CONTINUE_ON_ERROR=true"
          moduleRequired=false
        fi

        if ! (cd "modules/$module" && env $moduleEnv ./Allwmake \
              -j"''${NIX_BUILD_CORES:-1}" -s -q -prefix=openfoam \
              > "$moduleLog" 2>&1)
        then
          if [ "$moduleRequired" = true ]; then
            echo "===== OpenFOAM module '$module' failed; tail of $moduleLog ====="
            tail -n 300 "$moduleLog" || true
            echo "===== end of log ====="
            exit 1
          else
            echo "===== warning: optional parts of module '$module' failed ====="
            tail -n 100 "$moduleLog" || true
            echo "===== continuing ====="
          fi
        fi
      done
    ''}

    ${optionalString docs ''
      echo "Building OpenFOAM documentation"
      docLog="$TMPDIR/doc.log"
      if ! (cd doc && ./Allwmake > "$docLog" 2>&1); then
        echo "===== OpenFOAM documentation failed; tail of $docLog ====="
        tail -n 300 "$docLog" || true
        exit 1
      fi
    ''}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/${dirName}"

    # Install the complete tree: OpenFOAM is not relocatable in the usual
    # sense and needs its source headers, wmake rules, tutorials, etc.
    shopt -s dotglob nullglob
    for entry in *; do
      case "$entry" in
        build | log.* | ThirdParty) continue ;;
      esac
      cp -a "$entry" "$out/${dirName}/"
    done
    shopt -u dotglob nullglob

    # Only the synthetic third-party layout (ParaView) is wanted.
    if [ -d ThirdParty/platforms ]; then
      mkdir -p "$out/${dirName}/ThirdParty"
      cp -a ThirdParty/platforms "$out/${dirName}/ThirdParty/"
    fi

    # Object files are build artefacts and are not needed at runtime.
    rm -rf "$out/${dirName}/build"

    # Convenience entry points so the package can be used without
    # remembering the installation prefix.
    mkdir -p "$out/bin"
    cat > "$out/bin/openfoam" <<'EOF'
    #!/bin/sh
    # Source the OpenFOAM environment and start an interactive shell.
    prefix="''${OPENFOAM_PREFIX:-@prefix@}"
    . "$prefix/etc/bashrc"
    exec "''${SHELL:-@shell@}" "$@"
    EOF
    substituteInPlace "$out/bin/openfoam" \
      --replace-fail '@prefix@' "$out/${dirName}" \
      --replace-fail '@shell@' "${stdenv.shell}"
    chmod +x "$out/bin/openfoam"

    cat > "$out/bin/foamExec" <<'EOF'
    #!/bin/sh
    # Run a command inside the OpenFOAM environment.
    prefix="''${OPENFOAM_PREFIX:-@prefix@}"
    . "$prefix/etc/bashrc"
    exec "$@"
    EOF
    substituteInPlace "$out/bin/foamExec" \
      --replace-fail '@prefix@' "$out/${dirName}"
    chmod +x "$out/bin/foamExec"

    runHook postInstall
  '';

  # Verify that the generated environment is usable.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    # shellcheck disable=SC1091
    source "$out/${dirName}/etc/bashrc"

    blockMesh -help > /dev/null
    foamVersion

    runHook postInstallCheck
  '';

  passthru = {
    mpi = mpiPkg;
    scotch = scotchPkg;
    metis = metisPkg;
    kahip = kahipPkg;
    fftw = fftwPkg;
    cgal = cgalPkg;
    adios2 = adios2Pkg;
    petsc = petscPkg;
    paraview = paraviewPkg;
    inherit
      mpiFlavor
      modules
      version
      ;
    # Paths are relative to the final installation prefix; the usual way to
    # enter the environment is:
    #   source ${openfoam}/OpenFOAM-v2606/etc/bashrc
    projectDir = "${dirName}";
    bashrc = "${dirName}/etc/bashrc";
  };

  meta = {
    description = "OpenFOAM ${version} (ESI/OpenCFD) computational fluid dynamics toolbox";
    longDescription = ''
      OpenFOAM is a free, open source CFD software package. This package
      builds the OpenCFD (ESI/Keysight) release from source and can be
      configured with a number of optional third-party components such as
      MPI, Scotch/PT-Scotch, Metis, KaHIP, FFTW, CGAL, PETSc, ADIOS2 and
      ParaView.
    '';
    homepage = "https://www.openfoam.com";
    downloadPage = "https://dl.openfoam.com/source/latest/";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = "openfoam";
  };
})
