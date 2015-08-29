with import <nixpkgs> {};
rec {
  pypySrc = fetchFromBitbucket {
    owner = "pypy";
    repo = "pypy";
    rev = "5345333d8dcd";
    sha256 = "0qsxjql2x7qkmg20mzjp2b02fds5vai1jr5asbwvg5yp3qqnmdwk";
  };
  typhonVm = stdenv.mkDerivation {
    name = "typhon-vm";
    buildInputs = [ pypy pkgs.pythonPackages.pytest pypySrc  ];
    buildPhase = ''
      source $stdenv/setup
      mkdir -p ./rpython/_cache
      cp -r ${pypySrc}/rpython .
      cp -r $src/main.py .
      pypy -mrpython -O2 main.py
      '';
    installPhase = ''
      mkdir $out
      cp mt-typhon $out/
      '';
    src = let loc = part: (toString ./.) + part;
     in builtins.filterSource (path: type:
      let p = toString path;
       in (lib.hasPrefix (loc "/typhon/") p &&
           (type == "directory" || lib.hasSuffix ".py" p)) ||
        p == loc "/typhon" ||
        p == loc "/main.py") ./.;

  };
  typhon = stdenv.mkDerivation {
    name = "typhon";
    buildInputs = [ typhonVm ];
    buildPhase = ''
      ln -s ${typhonVm}/mt-typhon .
      make mast fun repl.ty
      '';
    installPhase = ''
      mkdir -p $out/bin
      cp -r mast repl.ty $out/
      echo "${typhonVm}/mt-typhon -l $out/mast $out/repl.ty" > $out/bin/monte
      chmod +x $out/bin/monte
      '';
    src = let loc = part: (toString ./.) + part;
     in builtins.filterSource (path: type:
      let p = toString path;
       in ((lib.hasPrefix (loc "/mast/") p &&
            (type == "directory" || lib.hasSuffix ".mt" p)) ||
           (lib.hasPrefix (loc "/boot/") p &&
            (type == "directory" || lib.hasSuffix ".ty" p)) ||
        p == loc "/mast" ||
        p == loc "/boot" ||
        p == loc "/Makefile" ||
        p == loc "/repl.mt")) ./.;
  };
}
