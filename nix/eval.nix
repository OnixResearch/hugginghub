# Evaluate the NixOS module without building HuggingHub.
# `nix build .#checks.<system>.module-eval` forces these assertions.
{
  lib,
  runCommand,
  nixosSystem,
  module,
  system,
}:

let
  eval =
    extra:
    nixosSystem {
      inherit system;
      modules = [
        module
        (
          { ... }:
          {
            boot.isContainer = true;
            networking.hostName = "hugginghub";
            system.stateVersion = "26.05";
            documentation.enable = false;
            nixpkgs.config.allowUnfreePredicate = pkg: (pkg.pname or "") == "hugginghub";
            fileSystems."/" = {
              device = "ignore-for-eval";
              fsType = "ext4";
            };
          }
        )
        extra
      ];
    };

  defaults = eval {
    services.hugginghub.enable = true;
  };

  lan = eval {
    services.hugginghub = {
      enable = true;
      address = "0.0.0.0";
      port = 8080;
      openFirewall = true;
      publicUrl = "http://hub.lan:8080";
    };
  };

  combined = eval {
    services.hugginghub = {
      enable = true;
      address = "::1";
      port = 8081;
      dataDir = "/srv/hugginghub";
      user = "hh";
      group = "hh";
      openSignup = true;
      storage = "s3";
      environmentFile = "/run/secrets/hugginghub.env";
      s3 = {
        bucket = "models";
        endpoint = "https://s3.example.net";
        region = "eu-central-1";
        prefix = "hh";
        pathStyle = false;
        redirect = true;
      };
    };
  };

  invalid = eval {
    services.hugginghub = {
      enable = true;
      storage = "s3";
      environmentFile = "secrets.env";
    };
  };

  s3NoFile = eval {
    services.hugginghub = {
      enable = true;
      storage = "s3";
      s3.bucket = "models";
    };
  };

  privileged = eval {
    services.hugginghub = {
      enable = true;
      port = 80;
    };
  };

  envOf = evaluated: evaluated.config.systemd.services.hugginghub.environment;
  unitOf = evaluated: evaluated.config.systemd.services.hugginghub.serviceConfig;

  failedAssertions =
    evaluated:
    map (item: item.message) (lib.filter (item: !item.assertion) evaluated.config.assertions);

  hugginghubWarnings =
    evaluated: lib.filter (lib.hasInfix "environmentFile") evaluated.config.warnings;

  require =
    name: condition: if condition then name else throw "hugginghub module eval failed: ${name}";

  defaultEnv = envOf defaults;
  defaultUnit = unitOf defaults;
  lanEnv = envOf lan;
  combinedEnv = envOf combined;
  combinedUnit = unitOf combined;

  checks = [
    (require "default bind is loopback" (defaultEnv.HH_BIND == "127.0.0.1:8080"))
    (require "default data dir" (defaultEnv.HH_DATA == "/var/lib/hugginghub"))
    (require "default storage is local" (defaultEnv.HH_STORAGE == "local"))
    (require "default signup is closed" (defaultEnv.HH_OPEN_SIGNUP == "0"))
    (require "default has no s3 bucket" (!(defaultEnv ? HH_S3_BUCKET)))
    (require "default has no access key" (
      !(defaultEnv ? HH_S3_ACCESS_KEY) && !(defaultEnv ? HH_S3_SECRET_KEY)
    ))
    (require "default user" (defaultUnit.User == "hugginghub"))
    (require "default group" (defaultUnit.Group == "hugginghub"))
    (require "default state directory" (
      defaultUnit.StateDirectory or null == "hugginghub"
      || defaultUnit.StateDirectory or null == [ "hugginghub" ]
    ))
    (require "restart on failure" (defaultUnit.Restart == "on-failure"))
    (require "wanted by multi-user" (
      lib.elem "multi-user.target" defaults.config.systemd.services.hugginghub.wantedBy
    ))
    (require "system user" defaults.config.users.users.hugginghub.isSystemUser)
    (require "system group" (defaults.config.users.groups ? hugginghub))
    (require "firewall stays closed" (
      !(lib.elem 8080 defaults.config.networking.firewall.allowedTCPPorts)
    ))
    (require "cli is installed" (
      lib.any (pkg: (pkg.name or "") == "hugginghub") defaults.config.environment.systemPackages
    ))
    (require "exec start is the package" (lib.hasSuffix "/bin/hugginghub" defaultUnit.ExecStart))
    (require "git is configured" (lib.hasSuffix "/bin/git" defaultEnv.HH_GIT))
    (require "no default warnings" (hugginghubWarnings defaults == [ ]))
    (require "default assertions hold" (failedAssertions defaults == [ ]))

    (require "lan bind" (lanEnv.HH_BIND == "0.0.0.0:8080"))
    (require "lan firewall opens the port" (
      lib.elem 8080 lan.config.networking.firewall.allowedTCPPorts
    ))
    (require "public url" (lanEnv.HH_PUBLIC_URL == "http://hub.lan:8080"))
    (require "lan assertions hold" (failedAssertions lan == [ ]))

    (require "ipv6 bind" (combinedEnv.HH_BIND == "[::1]:8081"))
    (require "custom data dir" (combinedEnv.HH_DATA == "/srv/hugginghub"))
    (require "custom user" (combinedUnit.User == "hh"))
    (require "no state directory outside /var/lib" (!(combinedUnit ? StateDirectory)))
    (require "tmpfiles creates custom data dir" (
      lib.any (
        rule: lib.hasInfix "/srv/hugginghub 0750 hh hh" rule
      ) combined.config.systemd.tmpfiles.rules
    ))
    (require "custom port is not firewalled" (
      !(lib.elem 8081 combined.config.networking.firewall.allowedTCPPorts)
    ))
    (require "s3 storage" (combinedEnv.HH_STORAGE == "s3"))
    (require "s3 bucket" (combinedEnv.HH_S3_BUCKET == "models"))
    (require "s3 endpoint" (combinedEnv.HH_S3_ENDPOINT == "https://s3.example.net"))
    (require "s3 region" (combinedEnv.HH_S3_REGION == "eu-central-1"))
    (require "s3 prefix" (combinedEnv.HH_S3_PREFIX == "hh"))
    (require "s3 path style off" (combinedEnv.HH_S3_PATH_STYLE == "0"))
    (require "s3 redirect on" (combinedEnv.HH_S3_REDIRECT == "1"))
    (require "signup can be opened" (combinedEnv.HH_OPEN_SIGNUP == "1"))
    (require "s3 credentials are not in the unit" (
      !(combinedEnv ? HH_S3_ACCESS_KEY)
      && !(combinedEnv ? HH_S3_SECRET_KEY)
      && !(combinedEnv ? AWS_ACCESS_KEY_ID)
      && !(combinedEnv ? AWS_SECRET_ACCESS_KEY)
    ))
    (require "environment file is passed through" (
      combinedUnit.EnvironmentFile or null == "/run/secrets/hugginghub.env"
    ))
    (require "unprivileged port has no bind capability" (!(defaultUnit ? AmbientCapabilities)))
    (require "unprivileged port keeps NoNewPrivileges" (defaultUnit.NoNewPrivileges == true))
    (require "privileged port can bind" (
      lib.elem "CAP_NET_BIND_SERVICE" ((unitOf privileged).AmbientCapabilities or [ ])
    ))
    (require "privileged port drops NoNewPrivileges" ((unitOf privileged).NoNewPrivileges == false))
    (require "privileged assertions hold" (failedAssertions privileged == [ ]))
    (require "combined assertions hold" (failedAssertions combined == [ ]))
    (require "s3 with environment file does not warn" (hugginghubWarnings combined == [ ]))

    (require "missing bucket is rejected" (
      lib.any (lib.hasInfix "s3.bucket") (failedAssertions invalid)
    ))
    (require "relative environment file is rejected" (
      lib.any (lib.hasInfix "environmentFile") (failedAssertions invalid)
    ))
    (require "s3 without credentials warns" (hugginghubWarnings s3NoFile != [ ]))
    (require "s3 without credentials still evaluates" (
      s3NoFile.config.services.hugginghub.storage == "s3"
    ))
  ];
in
runCommand "hugginghub-module-eval" { preferLocalBuild = true; } ''
  echo ${lib.escapeShellArg (builtins.deepSeq checks "ok")} > "$out"
''
