{
# Known-good version of Nixpkgs, with no user overlays, etc.
nixpkgs ? import (fetchTarball {
  name = "nixpkgs2305";
  url = "https://github.com/NixOS/nixpkgs/archive/23.05.tar.gz";
  sha256 = "10wn0l08j9lgqcw8177nh2ljrnxdrpri7bp0g7nvrsn9rkawvlbf";
}) {
  config = { };
  overlays = [ ];
}
# This attrset contains our dependencies, including Python3 and Mercurial
, python3Packages ? nixpkgs.python3Packages

  # The Artemis source code to use; defaults to the current directory, but could
  # be e.g. a call to fetchGit, fetchTarball, etc.
, artemisSrc ? nixpkgs.lib.cleanSource ./.

  # Defaults to reading "__version__ = '...'" from $artemisSrc/artemis.py
, version ? with rec {
  inherit (builtins) filter fromTOML head isString readFile split;
  inherit (nixpkgs.lib) hasInfix;
  lines = split "\n" (readFile "${artemisSrc}/artemis.py");
  versionLine = head (filter (l: isString l && hasInfix "__version__" l) lines);
};
  (fromTOML versionLine).__version__

  # If true, the resulting derivation depends on basic functional tests passing
, artemisRequireTests ? true }:
with rec {
  # A function for building Artemis: must be called with 'version' and 'extras'
  mkPkg = python3Packages.callPackage
    ({ buildPythonApplication, extras, mercurial, version }:
      buildPythonApplication ({
        inherit version;
        pname = "artemis";
        propagatedBuildInputs = [ mercurial ];
        src = artemisSrc;
      } // extras));

  artemisTests = nixpkgs.runCommand "artemis-${version}-tests" {
    EDITOR = nixpkgs.writeScript "artemis-test-editor" ''
      #!${nixpkgs.bash}/bin/bash
      exec sed -e "s/brief description/$SUBJECT/g" \
               -e "s/Detailed description/$BODY/g" \
               -i "$1"
    '';
    buildInputs = [
      nixpkgs.git
      # Basic build of Artemis, which doesn't depend on these tests
      (mkPkg {
        version = "${version}-untested";
        extras = { };
      })
    ];
  } ''
    echo 'Setting up test git repo' 1>&2
    export HOME="$PWD"
    git config --global init.defaultBranch master
    git config --global user.name 'Test User'
    git config --global user.email 'test@example.com'
    mkdir -p repo
    cd repo
    git init

    echo 'Checking Artemis can list and make issues' 1>&2
    git artemis list
    SUBJECT='ISSUE SUBJECT' BODY='ISSUE BODY' git artemis add
    ISSUES=$(git artemis list)
    ISSUE=$(echo "$ISSUES" | head -n1 | awk '{print $1}')
    git artemis show "$ISSUE"

    echo 'Checking Artemis can list and make comments' 1>&2
    SUBJECT='COMMENT SUBJECT' BODY='COMMENT BODY' git artemis add "$ISSUE"
    git artemis show "$ISSUE" 1

    SUBJECT='NESTED SUBJECT' BODY='NESTED BODY' git artemis add "$ISSUE" 1
    git artemis show "$ISSUE" 2

    echo 'Passed' 1>&2
    mkdir "$out"
  '';
};
# Return a final build of Artemis, which (optionally) depends on artemisTests
mkPkg {
  inherit version;
  extras = if artemisRequireTests then { inherit artemisTests; } else { };
} // {
  # We append the tests and our nixpkgs set to the result in case they're useful
  # for anyone importing this definition, e.g. to debug or override.
  inherit artemisTests nixpkgs;
}
