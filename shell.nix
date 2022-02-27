let
  pkgs = import <nixpkgs> { };
in pkgs.mkShell {
  buildInputs = with pkgs; [
    rustc
    cargo
    cargo-watch
    rls
    rustfmt
  ];

  RUST_LOG = "info";
}
