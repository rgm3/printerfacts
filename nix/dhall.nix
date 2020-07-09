let
  sources = import ./sources.nix;
  pkgs = import sources.nixpkgs { };
in pkgs.stdenv.mkDerivation rec {
  name = "dhall-yaml-simple";

  src = sources.dhall-yaml;

  installPhase = ''
    mkdir -p $out/bin
    DHALL_TO_YAML=$out/bin/dhall-to-yaml-ng
    install -D -m555 -T dhall-to-yaml-ng $DHALL_TO_YAML
    mkdir -p $out/etc/bash_completion.d/
    $DHALL_TO_YAML --bash-completion-script $DHALL_TO_YAML > $out/etc/bash_completion.d/dhall-to-yaml-completion.bash
  '';
}
