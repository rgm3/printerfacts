{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    naersk.url = "github:nix-community/naersk";
    xess.url = "github:Xe/Xess";
  };

  outputs = { self, nixpkgs, flake-utils, naersk, xess }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages."${system}";
        naersk-lib = naersk.lib."${system}";
        srcNoTarget = dir:
          builtins.filterSource (path: type:
            type != "directory" || builtins.baseNameOf path != "target") dir;
        src = srcNoTarget ./.;
      in rec {
        # `nix build`
        packages = rec {
          printerfacts-bin = naersk-lib.buildPackage {
            pname = "printerfacts";
            root = srcNoTarget ./.;
          };
          printerfacts = pkgs.stdenv.mkDerivation {
            inherit (printerfacts-bin) name;
            inherit src;
            phases = "installPhase";

            installPhase = ''
              mkdir -p $out/static

              cp -rf $src/templates $out/templates
              cp -rf ${printerfacts-bin}/bin $out/bin
              cp -rf ${xess}/xess.css $out/static/gruvbox.css
            '';
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
              systemd.services.within-homedir-setup = {
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

            testScript =
              ''
                start_all()
                client.wait_for_unit("within.printerfacts.service")
                client.succeed("curl -f http://printerfacts.akua --resolve printerfacts.akua:80:127.0.0.1")
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
              systemd.services."within.printerfacts" = {
                wantedBy = [ "multi-user.target" ];

                serviceConfig = {
                  DynamicUser = "yes";
                  Restart = "on-failure";
                  WorkingDirectory = "/srv/within/printerfacts";
                  RestartSec = "30s";
                };

                script = let site = self.packages."${system}".printerfacts;
                in ''
                  export SOCKPATH=${cfg.sockPath}
                  export DOMAIN=${toString cfg.domain}
                  export RUST_LOG=info
                  cd ${site}
                  exec ${site}/bin/printerfacts
                '';
              };

              services.cfdyndns =
                mkIf cfg.useACME { records = [ "${cfg.domain}" ]; };

              services.nginx.virtualHosts."${cfg.domain}" = {
                locations."/" = {
                  proxyPass = "http://unix:${cfg.sockPath}";
                  proxyWebsockets = true;
                };
                forceSSL = cfg.useACME;
                useACMEHost = "cetacean.club";
                extraConfig = ''
                  access_log /var/log/nginx/printerfacts.access.log;
                '';
              };
            };
          };
      });
}
