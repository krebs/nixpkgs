{ pkgs, lib }:

with lib;
rec {
  # Base implementation for non-compiled executables.
  # Takes an interpreter, for example `${pkgs.bash}/bin/bash`
  #
  # Examples:
  #   writebash = makeScriptWriter { interpreter = "${pkgs.bash}/bin/bash"; }
  #   makeScriptWriter { interpreter = "${pkgs.dash}/bin/dash"; } "hello" "echo hello world"
  makeScriptWriter = { interpreter, check ? null }: name: text:
    assert (with types; either absolute-pathname filename).check name;
    pkgs.write (baseNameOf name) {
      ${optionalString (types.absolute-pathname.check name) name} = {
        inherit check;
        executable = true;
        text = "#! ${interpreter}\n${text}";
      };
    };

  # Like writeScript but the first line is a shebang to bash
  #
  # Example:
  #   writeBash "example" ''
  #     echo hello world
  #   ''
  writeBash = pkgs.makeScriptWriter {
    interpreter = "${pkgs.bash}/bin/bash";
  };

  # Like writeScriptBIn but the first line is a shebang to bash
  writeBashBin = name:
    assert types.filename.check name;
    pkgs.writeBash "/bin/${name}";

  # writeC writes an executable c package called `name` to `destination` using
  # `library'.
  #
  #  Examples:
  #    writeC "hello-world" { destination = "/bin/hello-world"; } ''
  #      include <stdio.h>
  #      int main() {
  #        printf("Hello World\n");
  #        return 0;
  #      }
  #    ''
  #
  #    writeC "hello-world-ncurses" { libraries = {ncurses = pkgs.ncurses;}; } ''
  #      #include <ncurses.h>
  #      int main() {
  #        initscr();
  #        printw("Hello World !!!");
  #        refresh(); endwin();
  #        return 0;
  #      }
  #    ''
  writeC = name: {
    destination ? "",
    libraries ? {}
  }: text: pkgs.runCommand name {
    inherit text;
    buildInputs = [ pkgs.pkgconfig ] ++ attrValues libraries;
    passAsFile = [ "text" ];
  } /* sh */ ''
    PATH=${makeBinPath [
      pkgs.binutils-unwrapped
      pkgs.coreutils
      pkgs.gcc
      pkgs.pkgconfig
    ]}
    exe=$out${destination}
    mkdir -p "$(dirname "$exe")"
    gcc \
        ${optionalString (libraries != [])
          /* sh */ "$(pkg-config --cflags --libs ${
            concatMapStringsSep " " escapeShellArg (attrNames libraries)
          })"
        } \
        -O \
        -o "$exe" \
        -Wall \
        -x c \
        "$textPath"
    strip --strip-unneeded "$exe"
  '';

  # Like writeScript but the first line is a shebang to dash
  #
  # Example:
  #   writeDash "example" ''
  #     echo hello world
  #   ''
  writeDash = pkgs.makeScriptWriter {
    interpreter = "${pkgs.dash}/bin/dash";
  };

  # Like writeScriptBin but the first line is a shebang to dash
  writeDashBin = name:
    assert types.filename.check name;
    pkgs.writeDash "/bin/${name}";

  writeHaskell = name: extra-depends: text:
    pkgs.stdenv.mkDerivation {
      inherit name;
      src = pkgs.writeHaskellPackage name {
        executables.${name} = {
          inherit extra-depends;
          text = text;
        };
      };
      phases = [ "buildPhase" ];
      buildPhase = ''
        ln -fns $src/bin/${name} $out
      '';
    };

  writeHaskellPackage =
    k:
    let
      k' = parseDrvName k;
      name = k'.name;
      version = if k'.version != "" then k'.version else "0";
    in
    { base-depends ? ["base"]
    , executables ? {}
    , ghc-options ? ["-Wall" "-O3" "-threaded" "-rtsopts"]
    , haskellPackages ? pkgs.haskellPackages
    , library ? null
    , license ? "WTFPL"
    }:
    let
      isExecutable = executables != {};
      isLibrary = library != null;

      cabal-file = pkgs.writeText "${name}-${version}.cabal" /* cabal */ ''
        build-type: Simple
        cabal-version: >= 1.2
        name: ${name}
        version: ${version}
        ${concatStringsSep "\n" (mapAttrsToList exe-section executables)}
        ${optionalString isLibrary (lib-section library)}
      '';

      exe-install =
        exe-name:
        { file ? pkgs.writeText "${name}-${exe-name}.hs" text
        , relpath ? "${exe-name}.hs"
        , text
        , ... }:
        if types.filename.check exe-name
          then /* sh */ "install -D ${file} $out/${relpath}"
          else throw "argument ‘exe-name’ is not a ${types.filename.name}";

      exe-section =
        exe-name:
        { build-depends ? base-depends ++ extra-depends
        , extra-depends ? []
        , file ? pkgs.writeText "${name}-${exe-name}.hs" text
        , relpath ? "${exe-name}.hs"
        , text
        , ... }: /* cabal */ ''
          executable ${exe-name}
            build-depends: ${concatStringsSep "," build-depends}
            ghc-options: ${toString ghc-options}
            main-is: ${relpath}
        '';

      get-depends =
        { build-depends ? base-depends ++ extra-depends
        , extra-depends ? []
        , ...
        }:
        build-depends;

      lib-install =
        { exposed-modules
        , ... }:
        concatStringsSep "\n" (mapAttrsToList mod-install exposed-modules);

      lib-section =
        { build-depends ? base-depends ++ extra-depends
        , extra-depends ? []
        , exposed-modules
        , ... }: /* cabal */ ''
          library
            build-depends: ${concatStringsSep "," build-depends}
            ghc-options: ${toString ghc-options}
            exposed-modules: ${concatStringsSep "," (attrNames exposed-modules)}
        '';

      mod-install =
        mod-name:
        { file ? pkgs.writeText "${name}-${mod-name}.hs" text
        , relpath ? "${replaceStrings ["."] ["/"] mod-name}.hs"
        , text
        , ... }:
        if types.haskell.modid.check mod-name
          then /* sh */ "install -D ${file} $out/${relpath}"
          else throw "argument ‘mod-name’ is not a ${types.haskell.modid.name}";
    in
      haskellPackages.mkDerivation {
        inherit isExecutable isLibrary license version;
        executableHaskellDepends =
          attrVals
            (concatMap get-depends (attrValues executables))
            haskellPackages;
        libraryHaskellDepends =
          attrVals
            (optionals isLibrary (get-depends library))
            haskellPackages;
        pname = name;
        src = pkgs.runCommand "${name}-${version}-src" {} /* sh */ ''
          install -D ${cabal-file} $out/${cabal-file.name}
          ${optionalString isLibrary (lib-install library)}
          ${concatStringsSep "\n" (mapAttrsToList exe-install executables)}
        '';
      };

  writeJq = name: text:
    assert (with types; either absolute-pathname filename).check name;
    pkgs.write (baseNameOf name) {
      ${optionalString (types.absolute-pathname.check name) name} = {
        check = pkgs.writeDash "jqcheck.sh" ''
          exec ${pkgs.jq}/bin/jq -f "$1" < /dev/null
        '';
        inherit text;
      };
    };

  writeJS = name: { deps ? [] }: text:
  let
    node-env = pkgs.buildEnv {
      name = "node";
      paths = deps;
      pathsToLink = [
        "/lib/node_modules"
      ];
    };
  in pkgs.writeDash name ''
    export NODE_PATH=${node-env}/lib/node_modules
    exec ${pkgs.nodejs}/bin/node ${pkgs.writeText "js" text}
  '';

  writeJSBin = name:
    pkgs.writeJS "/bin/${name}";

  writeJSON = name: value: pkgs.runCommand name {
    json = toJSON value;
    passAsFile = [ "json" ];
  } /* sh */ ''
    ${pkgs.jq}/bin/jq . "$jsonPath" > "$out"
  '';

  writePerl = name: { deps ? [] }:
  let
    perl-env = pkgs.buildEnv {
      name = "perl-environment";
      paths = deps;
      pathsToLink = [
        "/lib/perl5/site_perl"
      ];
    };
  in
  pkgs.makeScriptWriter {
    interpreter = "${pkgs.perl}/bin/perl -I ${perl-env}/lib/perl5/site_perl";
  } name;

  writePerlBin = name:
    pkgs.writePerl "/bin/${name}";

  writePython2 = name: { deps ? [], flakeIgnore ? [] }:
  let
    py = pkgs.python2.withPackages (ps: deps);
    ignoreAttribute = optionalString (flakeIgnore != []) "--ignore ${concatMapStringsSep "," escapeShellArg flakeIgnore}";
  in
  pkgs.makeScriptWriter {
    interpreter = "${py}/bin/python";
    check = pkgs.writeDash "python2check.sh" ''
      exec ${pkgs.python2Packages.flake8}/bin/flake8 --show-source ${ignoreAttribute} "$1"
    '';
  } name;

  writePython2Bin = name:
    pkgs.writePython2 "/bin/${name}";

  writePython3 = name: { deps ? [], flakeIgnore ? [] }:
  let
    py = pkgs.python3.withPackages (ps: deps);
    ignoreAttribute = optionalString (flakeIgnore != []) "--ignore ${concatMapStringsSep "," escapeShellArg flakeIgnore}";
  in
  pkgs.makeScriptWriter {
    interpreter = "${py}/bin/python";
    check = pkgs.writeDash "python3check.sh" ''
      exec ${pkgs.python3Packages.flake8}/bin/flake8 --show-source ${ignoreAttribute} "$1"
    '';
  } name;

  writePython3Bin = name:
    pkgs.writePython3 "/bin/${name}";

  writeSed = pkgs.makeScriptWriter {
    interpreter = "${pkgs.gnused}/bin/sed -f";
  };
}
