# vi: ft=sh

setup_file() {
  bats_require_minimum_version 1.5.0

  # For debugging
  # project_dir="/tmp/_clj-nix_project"

  project_dir="$BATS_FILE_TMPDIR/clj-nix_project"
  export project_dir
  cljnix_dir=$(dirname "$BATS_TEST_DIRNAME")
  export cljnix_dir

  cp -r "$cljnix_dir/test/polylith-example-project/." "$project_dir"
  echo "cljnixUrl: $cljnix_dir" | mustache "$project_dir/flake.template" > "$project_dir/flake.nix"

  cd "$project_dir" || exit
  nix flake lock
  git init
  git add .
}

# bats test_tags=polylith
@test "Generate lockfile (polylith)" {
    cd projects/app
    cp deps-lock.json "$BATS_TEST_TMPDIR/deps-lock.json"
    nix run "$cljnix_dir#deps-lock"
    cmp deps-lock.json "$BATS_TEST_TMPDIR/deps-lock.json"
}

# bats test_tags=polylith
@test "nix build .#app (polylith)" {
    nix build .#app --print-out-paths >> "$DERIVATIONS"
    run -0 ./result/bin/app
    [ "$output" = "Hello, Polylith!" ]
}

# bats test_tags=polylith
@test "projectSrc has only the bricks the project uses" {
    src="$(nix eval --raw .#app.src)"
    nix build "$src" --no-link
    [ -e "$src/bases/app/src/app/main.clj" ]
    [ -e "$src/components/greet/src/greet/core.clj" ]
    [ ! -e "$src/components/greet/test" ]
    [ ! -e "$src/components/unused" ]
}

# bats test_tags=polylith
@test "Changing an unused component doesn't change the derivation" {
    before="$(nix eval --raw .#app.drvPath)"
    echo "(def other 2)" >> components/unused/src/unused/core.clj
    echo "(def other 2)" >> components/greet/test/greet/core_test.clj
    git add .
    after="$(nix eval --raw .#app.drvPath)"
    git checkout -- components
    [ "$before" = "$after" ]
}
