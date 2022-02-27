{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    naersk.url = "github:nix-community/naersk";
    xess.url = "github:Xe/Xess";
    portable-svc.url = "git+https://tulpa.dev/cadey/portable-svc.git?ref=main";
  };

  outputs = { self, nixpkgs, flake-utils, naersk, xess, portable-svc }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = import nixpkgs { overlays = [ portable-svc.overlay ]; inherit system; };
        naersk-lib = naersk.lib."${system}";
        src = ./.;
      in rec {
        # `nix build`
        packages = rec {
          printerfacts-bin = naersk-lib.buildPackage {
            pname = "printerfacts";
            root = ./.;
          };
          printerfacts = pkgs.stdenv.mkDerivation {
            inherit (printerfacts-bin) pname version;
            inherit src;
            phases = "installPhase";

            installPhase = ''
              mkdir -p $out/static

              cp -rf $src/templates $out/templates
              cp -rf ${printerfacts-bin}/bin $out/bin
              cp -rf ${
                xess.defaultPackage."${system}"
              }/static/css/xess.css $out/static/gruvbox.css
            '';
          };
          printerfacts-service = pkgs.substituteAll {
            name = "printerfacts.service";
            src = ./systemd/printerfacts.service.in;
            printerfacts = self.packages.${system}.printerfacts;
          };
          portable-service = pkgs.portableService {
            inherit (self.packages.${system}.printerfacts) version;
            name = "printerfacts";
            description = "Printer facts";
            units = [ self.packages.${system}.printerfacts-service ];
          };
        };
        defaultPackage = packages.printerfacts;

        # `nix run`
        apps.printerfacts =
          flake-utils.lib.mkApp { drv = packages.printerfacts; };
        defaultApp = apps.printerfacts;

        # `nix develop`
        devShell = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            rustc
            cargo
            cargo-watch
            rls
            rustfmt
          ];

          RUST_LOG = "info";
        };

        checks.end2end =
          with import (nixpkgs + "/nixos/lib/testing-python.nix") {
            inherit system;
          };

          makeTest {
            nodes.server = { ... }: {
              imports = [ self.nixosModules."${system}".printerfacts ];
              users.groups.within = { };
              systemd.services."within.homedir-setup" = {
                description = "Creates homedirs for /srv/within services";
                wantedBy = [ "multi-user.target" ];

                serviceConfig.Type = "oneshot";

                script = with pkgs; ''
                  ${coreutils}/bin/mkdir -p /srv/within
                  ${coreutils}/bin/chown root:within /srv/within
                  ${coreutils}/bin/chmod 775 /srv/within
                  ${coreutils}/bin/mkdir -p /srv/within/run
                  ${coreutils}/bin/chown root:within /srv/within/run
                  ${coreutils}/bin/chmod 770 /srv/within/run
                '';
              };

              within.services.printerfacts.enable = true;
            };

            testScript = ''
              start_all()
              server.wait_for_unit("within.printerfacts.service")
              server.succeed("sleep 2 && curl -m 2 -v -f http://printerfacts.akua/metrics --unix-socket /srv/within/run/printerfacts.sock")
            '';
          };

        nixosModules.printerfacts = { config, lib, pkgs, ... }:
          with lib;
          let cfg = config.within.services.printerfacts;
          in {
            options.within.services.printerfacts = {
              enable = mkEnableOption "Activates the printerfacts server";
              useACME = mkEnableOption "Enables ACME for cert stuff";

              domain = mkOption {
                type = types.str;
                default = "printerfacts.akua";
                example = "printerfacts.cetacean.club";
                description =
                  "The domain name that nginx should check against for HTTP hostnames";
              };

              sockPath = mkOption rec {
                type = types.str;
                default = "/srv/within/run/printerfacts.sock";
                example = default;
                description =
                  "The unix domain socket that printerfacts should listen on";
              };
            };

            config = mkIf cfg.enable {
              users.users.printerfacts = {
                createHome = true;
                description = "tulpa.dev/cadey/printerfacts";
                isSystemUser = true;
                group = "within";
                home = "/srv/within/printerfacts";
                extraGroups = [ "keys" ];
              };

              systemd.services."within.printerfacts" = {
                wantedBy = [ "multi-user.target" ];
                path = [ self.packages."${system}".printerfacts ];
                after = [ "within.homedir-setup.service" ];

                serviceConfig =
                  let site = self.packages."${system}".printerfacts;
                  in {
                    User = "printerfacts";
                    Group = "within";
                    Restart = "on-failure";
                    WorkingDirectory = site;
                    ExecStart = "${site}/bin/printerfacts";
                    RestartSec = "5s";
                    UMask = "007";
                  };

                environment = {
                  RUST_LOG = "info";
                  DOMAIN = cfg.domain;
                  SOCKPATH = cfg.sockPath;
                };
              };

              services.cfdyndns =
                mkIf cfg.useACME { records = [ "${cfg.domain}" ]; };

              services.nginx.virtualHosts."${cfg.domain}" = {
                locations."/" = {
                  proxyPass = "http://unix:${cfg.sockPath}";
                  proxyWebsockets = true;
                };
                forceSSL = cfg.useACME;
                useACMEHost = mkIf cfg.useACME "cetacean.club";
                extraConfig = ''
                  access_log /var/log/nginx/printerfacts.access.log;
                '';
              };
            };
          };
      });
}
