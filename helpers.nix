let

  formatArg =
    x:
    if x == null then
      [ ]
    else if (builtins.isList x) then
      x
    else
      [ x ];
in

{ clj-nix_overlay }:
{
  # The files of the :local/root deps in a lock file, for use with
  # lib.fileset. Building projectSrc from these instead of a whole
  # directory, e.g. a Polylith workspace, avoids rebuilds when unrelated
  # files change. Paths that don't exist, such as an unused "resources"
  # dir, are left out.
  localDepsPaths =
    { lockfile }:
    assert builtins.isPath lockfile;
    let
      lock = builtins.fromJSON (builtins.readFile lockfile);
      dir = builtins.dirOf lockfile;
    in
    builtins.filter builtins.pathExists (
      builtins.concatMap (dep: map (p: dir + "/${p}") dep.paths) (lock.local-deps or [ ])
    );

  mkCljCli =
    {
      jdkDrv,
      java-opts ? [ ],
      extra-args ? [ ],
    }:
    builtins.filter (s: builtins.stringLength s != 0) (
      [
        "${jdkDrv.jdk}/bin/java"
      ]
      ++ (formatArg java-opts)
      ++ [
        "-jar"
        "${jdkDrv.jarPath}"
      ]
      ++ (formatArg extra-args)
    );

  mkCljApp =
    { pkgs, modules }:
    let
      pkgs' = pkgs.extend clj-nix_overlay;

      _m = pkgs.lib.evalModules {
        specialArgs = {
          pkgs = pkgs';
        };
        modules = [ ./modules/top-level.nix ] ++ modules;
      };

      cfg = _m.config;

    in

    assert (
      pkgs'.lib.assertMsg (
        cfg.customJdk.enable == true -> cfg.nativeImage.enable == false
      ) "customJdk and nativeImage are incompatible, you can enable only one"
    );

    assert (
      pkgs'.lib.assertMsg (
        cfg.withLeiningen == true -> !isNull cfg.buildCommand
      ) "With Leiningen you have to provide a 'buildCommand'"
    );

    assert (
      pkgs'.lib.assertMsg (
        cfg.withLeiningen == true
        -> isNull cfg.compileCljOpts && isNull cfg.javacOpts && isNull cfg.uberOpts
      ) "Leiningen is incompatible with Clojure tools.build options (compileCljOpts and javacOpts)"
    );

    assert (
      pkgs'.lib.assertMsg (
        cfg.buildCommand != null
        ->
          cfg.builder-extra-inputs == [ ]
          && cfg.builder-java-opts == [ ]
          && cfg.builder-preBuild == ""
          && cfg.builder-postBuild == ""
      ) "buildCommand and builder-* options are incompatible"
    );

    let
      cljDrv = pkgs'.mkCljBin {
        jdkRunner = cfg.jdk;
        inherit (cfg)
          projectSrc
          name
          version
          main-ns
          buildCommand
          lockfile
          java-opts
          compileCljOpts
          javacOpts
          uberOpts
          builder-extra-inputs
          builder-java-opts
          builder-preBuild
          builder-postBuild
          ;
        enableLeiningen = cfg.withLeiningen;
      };
    in

    if cfg.customJdk.enable then
      pkgs'.customJdk {
        inherit cljDrv;
        jdkBase = cfg.jdk;
        java-opts = cfg.java-opts;
        inherit (cfg.customJdk) jdkModules extraJdkModules locales;
      }

    else if cfg.nativeImage.enable then
      pkgs'.mkGraalBin {
        inherit cljDrv;

        graalvm =
          if cfg.nativeImage.static then pkgs'.graalvmPackages.graalvm-ce-musl else cfg.nativeImage.graalvm;

        extraNativeImageBuildArgs =
          cfg.nativeImage.extraNativeImageBuildArgs
          ++ (
            if cfg.nativeImage.static then
              [
                "--static"
                "--libc=musl"
              ]
            else
              [ ]
          );
        inherit (cfg.nativeImage) graalvmXmx;
      }
    else
      cljDrv;

}
