{ sources ? import ./nix/sources.nix, pkgs ? import <nixpkgs> { } }:
let
  srcNoTarget = dir:
    builtins.filterSource
    (path: type: type != "directory" || builtins.baseNameOf path != "target")
    dir;
  naersk = pkgs.callPackage sources.naersk { };
  gruvbox-css = pkgs.callPackage sources.gruvbox-css { };
  src = srcNoTarget ./.;
  pfacts = naersk.buildPackage {
    inherit src;
    remapPathPrefix = true;
  };
in pkgs.stdenv.mkDerivation {
  inherit (pfacts) name;
  inherit src;
  phases = "installPhase";

  installPhase = ''
    mkdir -p $out/static

    cp -rf $src/templates $out/templates
    cp -rf ${pfacts}/bin $out/bin
    cp -rf ${gruvbox-css}/gruvbox.css $out/static/gruvbox.css
  '';
}
