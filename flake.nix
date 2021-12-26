{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    naersk.url = "github:nix-community/naersk";
    xess = {
      url = "github:Xe/Xess";
      flake = false;
    };
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

        overlay = final: prev: {
          inherit (packages) printerfacts;
        };

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
              nix.overlay = self.overlay;

              users.users.printerfacts = {
                createHome = true;
                description = "tulpa.dev/cadey/printerfacts";
                isSystemUser = true;
                group = "within";
                home = "/srv/within/printerfacts";
                extraGroups = [ "keys" ];
              };

              systemd.services.printerfacts = {
                wantedBy = [ "multi-user.target" ];

                serviceConfig = {
                  User = "printerfacts";
                  Group = "within";
                  Restart = "on-failure";
                  WorkingDirectory = "/srv/within/printerfacts";
                  RestartSec = "30s";

                  # Security
                  CapabilityBoundingSet = "";
                  DeviceAllow = [ ];
                  NoNewPrivileges = "true";
                  ProtectControlGroups = "true";
                  ProtectClock = "true";
                  PrivateDevices = "true";
                  PrivateUsers = "true";
                  ProtectHome = "true";
                  ProtectHostname = "true";
                  ProtectKernelLogs = "true";
                  ProtectKernelModules = "true";
                  ProtectKernelTunables = "true";
                  ProtectSystem = "true";
                  ProtectProc = "invisible";
                  RemoveIPC = "true";
                  RestrictAddressFamilies = [ "~AF_NETLINK" ];
                  RestrictNamespaces = [
                    "CLONE_NEWCGROUP"
                    "CLONE_NEWIPC"
                    "CLONE_NEWNET"
                    "CLONE_NEWNS"
                    "CLONE_NEWPID"
                    "CLONE_NEWUTS"
                    "CLONE_NEWUSER"
                  ];
                  RestrictSUIDSGID = "true";
                  RestrictRealtime = "true";
                  SystemCallArchitectures = "native";
                  SystemCallFilter = [
                    "~@reboot"
                    "~@module"
                    "~@mount"
                    "~@swap"
                    "~@resources"
                    "~@cpu-emulation"
                    "~@obsolete"
                    "~@debug"
                    "~@privileged"
                  ];
                  UMask = "007";
                };

                script = let site = pkgs.tulpa.dev.cadey.printerfacts;
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
