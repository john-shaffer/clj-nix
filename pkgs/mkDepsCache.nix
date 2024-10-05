{ lib
, fetchurl
, fetchgit
, jdk
, runtimeShell
, runCommand
, writeText
, linkFarm
, lockfile
, maven-extra ? [ ]
}:
let
  deps-lock-version = 4;

  consUrl = segments:
    lib.pipe
      segments
      [
        (map (lib.removeSuffix "/"))
        (map (lib.removePrefix "/"))
        (lib.concatStringsSep "/")
      ];

  lock = builtins.fromJSON (builtins.readFile lockfile);

  maven-deps =
    { mvn-path, mvn-repo, hash, snapshot ? null, ... }:
    let
      path = fetchurl {
        inherit hash;
        url = consUrl [ mvn-repo mvn-path ];
      };
      names = [ mvn-path ] ++ lib.optional (snapshot != null) (builtins.concatStringsSep "/" [ (builtins.dirOf mvn-path) snapshot ]);
    in
    map (name: { inherit path name; }) names;

  git-deps =
    { lib, url, rev, hash, fetch ? "pkgs.fetchgit", ... }:
    {
      name = "${lib}/${rev}";
      path =
        if "pkgs.fetchgit" == fetch
        then fetchgit {
          inherit url rev hash;
        }
        else if "builtins.fetchTree" == fetch
          # support credential integration (ssh-agent, ... ) for private git repositories
          # through builtin fetching.
          # See https://nix.dev/manual/nix/latest/language/builtins.html#builtins-fetchTree
          # This is not a good default, because it will download
          # the repository during evaluation, even for a dry-run
          # Pending https://github.com/NixOS/nix/issues/9077
        then builtins.fetchTree {
          type = "git";
          allRefs = true;
          narHash = hash;
          inherit url rev;
          # deep cloning is necessary, for allRefs to work
          # See https://nix.dev/manual/nix/latest/language/builtins.html#source-types
          shallow = false;
        }
        else throw "clj-nix.mkDepsCache: unknown :clj-nix.git/fetch :${toString fetch}";
    };

  maven-extra-cache = { path, content }:
    {
      name = path;
      path = writeText "maven-data" content;
    };

  maven-dep-list = builtins.concatMap maven-deps lock.mvn-deps;
  maven-extra-list = builtins.map maven-extra-cache maven-extra;

  maven-cache = runCommand "maven-cache" { } ''
    mkdir -p $out
    ${lib.concatStringsSep "\n" (map (dep: ''
      mkdir -p $out/$(dirname "${dep.name}")
      cp -r ${dep.path} $out/${dep.name}
    '') (maven-dep-list ++ maven-extra-list))}
  '';

  git-dep-list = builtins.map git-deps lock.git-deps;

  git-cache = runCommand "git-cache" { } ''
    mkdir -p $out
    ${lib.concatStringsSep "\n" (map (dep: ''
      mkdir -p $out/$(dirname "${dep.name}")
      cp -r ${dep.path} $out/${dep.name}
    '') git-dep-list)}
  '';

  git-repo-config = runCommand "gitlibs-config-dir"
    { }
    (
      ''
        mkdir -p $out
      '' +
      (lib.concatMapStringsSep
        "\n"
        ({ git-dir, rev, ... }@data:
          ''
            mkdir -p $out/${git-dir}/revs
            json='${builtins.toJSON data}'
            touch $out/${git-dir}/config
            echo "$json" > $out/${git-dir}/revs/${rev}
          ''
        )
        lock.git-deps)
    );
  dotclojure = runCommand "dotclojure"
    { }
    ''
      mkdir -p $out/tools
      echo "{}" > $out/deps.edn
      echo "{}" > $out/tools/tools.edn
    '';
  version = lock.lock-version or 0;
in
assert
(
  lib.assertMsg
    (version == deps-lock-version)
    ''
      Lock file generated with a different clj-nix version.
      Current version: ${builtins.toString version}
      Expected version: ${builtins.toString deps-lock-version}

      Re-generate the lock file with
      nix run github:jlesquembre/clj-nix#deps-lock
    ''
);
linkFarm "clj-cache" [
  {
    name = ".m2/repository";
    path = maven-cache;
  }
  {
    name = ".gitlibs/libs";
    path = git-cache;
  }
  {
    name = ".gitlibs/_repos";
    path = git-repo-config;
  }
  {
    name = ".clojure";
    path = dotclojure;
  }
]
