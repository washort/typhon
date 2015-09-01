
{ system ? builtins.currentSystem }:

let
  pkgs = import <nixpkgs> { inherit system; };
in
rec {
  typhonVm = import ./nix/vm.nix {
    inherit (pkgs) stdenv lib fetchFromBitbucket pypy pypyPackages;};
  mast = import ./nix/mast.nix {
    inherit typhonVm;
    inherit (pkgs) stdenv lib;};
  mastWithTests = pkgs.lib.overrideDerivation mast (oldAttrs: {
    inherit mast;
    doCheck = true;});
}
