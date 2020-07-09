{ system ? builtins.currentSystem }:

let
  sources = import ./nix/sources.nix;
  pkgs = import <nixpkgs> { };
  printerfacts = import ./printerfacts.nix { inherit pkgs sources; };

  name = "xena/printerfacts";
  tag = "latest";

in pkgs.dockerTools.buildLayeredImage {
  inherit name tag;
  contents = [ printerfacts ];

  config = {
    Cmd = [ "${printerfacts}/bin/printerfacts" ];
    Env = [ "RUST_LOG=info" ];
    WorkingDir = "/";
  };
}
