# NixOS module for HuggingHub.
#
# Import from a NixOS host as either flake output:
#   hugginghub.nixosModules.default
#   hugginghub.nixosModules.hugginghub
#
# This option set is the stable interface other repositories should enable.
# Every setting maps to the server's existing HH_* environment variables.
# Local disk is the default; S3 is optional and unused unless storage = "s3".
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.hugginghub;

  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    optional
    optionalAttrs
    types
    ;

  gitBin = lib.getExe' cfg.gitPackage "git";

  # Bracket bare IPv6 addresses so HH_BIND is host:port.
  bindHost =
    if lib.hasInfix ":" cfg.address && !(lib.hasPrefix "[" cfg.address) then
      "[${cfg.address}]"
    else
      cfg.address;
  bind = "${bindHost}:${toString cfg.port}";

  stateRelative = lib.removePrefix "/var/lib/" cfg.dataDir;
  useStateDirectory = lib.hasPrefix "/var/lib/" cfg.dataDir && stateRelative != "";

  environment = lib.filterAttrs (_: value: value != null && value != "") (
    {
      HH_BIND = bind;
      HH_DATA = cfg.dataDir;
      HH_GIT = gitBin;
      HH_STORAGE = cfg.storage;
      HH_OPEN_SIGNUP = if cfg.openSignup then "1" else "0";
      HH_LFS_THRESHOLD = toString cfg.lfsThreshold;
      HH_SITE_NAME = cfg.siteName;
      HOME = cfg.dataDir;
      RUST_LOG = cfg.logLevel;
    }
    // optionalAttrs (cfg.publicUrl != null) {
      HH_PUBLIC_URL = cfg.publicUrl;
    }
    // optionalAttrs (cfg.storage == "s3") {
      HH_S3_BUCKET = cfg.s3.bucket;
      HH_S3_PATH_STYLE = if cfg.s3.pathStyle then "1" else "0";
      HH_S3_REDIRECT = if cfg.s3.redirect then "1" else "0";
    }
    // optionalAttrs (cfg.storage == "s3" && cfg.s3.endpoint != null) {
      HH_S3_ENDPOINT = cfg.s3.endpoint;
    }
    // optionalAttrs (cfg.storage == "s3" && cfg.s3.region != null) {
      HH_S3_REGION = cfg.s3.region;
    }
    // optionalAttrs (cfg.storage == "s3" && cfg.s3.prefix != null) {
      HH_S3_PREFIX = cfg.s3.prefix;
    }
    // cfg.extraEnvironment
  );

  # CLI on PATH. The systemd unit does not use this wrapper; it sets HH_* itself.
  # The wrapper exists so `hugginghub create-user` writes into dataDir instead of ./data.
  cli = pkgs.writeShellScriptBin "hugginghub" ''
    set -euo pipefail
    export HH_DATA=''${HH_DATA:-${lib.escapeShellArg cfg.dataDir}}
    export HH_GIT=''${HH_GIT:-${lib.escapeShellArg gitBin}}
    export PATH=${lib.escapeShellArg (lib.makeBinPath [ cfg.gitPackage ])}:''${PATH:-}
    exec ${lib.getExe cfg.package} "$@"
  '';
in
{
  options.services.hugginghub = {
    enable = mkEnableOption "HuggingHub, a self-hosted Hugging Face Hub";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = ''
        HuggingHub package to run. Defaults to the Cargo build in this flake,
        compiled with the host NixOS configuration's nixpkgs.
      '';
    };

    address = mkOption {
      type = types.str;
      default = "127.0.0.1";
      example = "0.0.0.0";
      description = ''
        Address to bind (`HH_BIND` host). Defaults to loopback so enabling the
        service does not publish it on every interface. Set a LAN address or
        `0.0.0.0` when other machines should connect, and set
        {option}`services.hugginghub.openFirewall` to open the port.
        Bare IPv6 addresses are bracketed automatically.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = ''
        TCP port to bind (`HH_BIND` port). Ports below 1024 receive
        `CAP_NET_BIND_SERVICE`. The upstream example unit listens on port 80;
        this module defaults to the binary's port 8080.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open {option}`services.hugginghub.port` in the NixOS firewall.
        Leave this false unless other machines on the LAN should reach the
        service. Binding a non-loopback address does not open the firewall.
      '';
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/hugginghub";
      apply = lib.removeSuffix "/";
      example = "/var/lib/hugginghub";
      description = ''
        Local disk directory for `hub.db`, `repos/`, `lfs/`, `tmp/`, and
        `avatars/` (`HH_DATA`). S3 is not required. When this path is under
        `/var/lib`, systemd `StateDirectory` creates it and the service user
        owns it. Other absolute paths are created with a tmpfiles rule.
        Put this on a volume large enough for the models you mirror.
      '';
    };

    user = mkOption {
      type = types.str;
      default = "hugginghub";
      description = "User account that owns the data directory and runs the service.";
    };

    group = mkOption {
      type = types.str;
      default = "hugginghub";
      description = "Group that owns the data directory and runs the service.";
    };

    publicUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "http://hub.lan:8080";
      description = ''
        Externally visible base URL (`HH_PUBLIC_URL`). When unset, HuggingHub
        derives URLs from the request `Host` header (and `X-Forwarded-*`
        behind a reverse proxy).
      '';
    };

    siteName = mkOption {
      type = types.str;
      default = "HuggingHub";
      description = "Instance name shown in the web UI (`HH_SITE_NAME`).";
    };

    openSignup = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Allow self-service sign-up (`HH_OPEN_SIGNUP`). The HuggingHub binary
        defaults this to true. The NixOS service defaults to false so a LAN
        mirror does not accept open registration. Create users with
        `hugginghub create-user` or from `/admin`.
      '';
    };

    lfsThreshold = mkOption {
      type = types.ints.unsigned;
      default = 10 * 1024 * 1024;
      description = ''
        Files of at least this many bytes are stored through Git LFS on
        preupload (`HH_LFS_THRESHOLD`). The binary default is 10 MiB.
      '';
    };

    gitPackage = mkOption {
      type = types.package;
      default = pkgs.gitMinimal;
      defaultText = lib.literalExpression "pkgs.gitMinimal";
      description = ''
        Git package used for bare repositories and `git http-backend`
        (`HH_GIT`). `git-lfs` is a client tool and is not required on the server.
      '';
    };

    logLevel = mkOption {
      type = types.str;
      default = "info";
      example = "info,hugginghub=debug";
      description = "Tracing filter passed as `RUST_LOG`.";
    };

    storage = mkOption {
      type = types.enum [
        "local"
        "s3"
      ];
      default = "local";
      description = ''
        LFS object storage (`HH_STORAGE`). `local` keeps objects under
        {option}`services.hugginghub.dataDir`. `s3` stores LFS objects in an
        S3-compatible bucket; git repositories themselves stay on local disk.
      '';
    };

    s3 = mkOption {
      description = ''
        S3-compatible object storage for LFS objects. Ignored unless
        {option}`services.hugginghub.storage` is `s3`. Credentials are not
        options: put `HH_S3_ACCESS_KEY` and `HH_S3_SECRET_KEY` in
        {option}`services.hugginghub.environmentFile`.
      '';
      default = { };
      type = types.submodule {
        options = {
          bucket = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "hugginghub";
            description = "Bucket name (`HH_S3_BUCKET`). Required when storage is `s3`.";
          };

          endpoint = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "https://s3.example.net";
            description = ''
              S3 API endpoint (`HH_S3_ENDPOINT`). Unset uses the AWS endpoint
              for {option}`services.hugginghub.s3.region`.
            '';
          };

          region = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "us-east-1";
            description = ''
              Signing region (`HH_S3_REGION`). Unset lets the server default to `us-east-1`.
            '';
          };

          prefix = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "hugginghub/prod";
            description = "Optional key prefix inside the bucket (`HH_S3_PREFIX`).";
          };

          pathStyle = mkOption {
            type = types.bool;
            default = true;
            description = ''
              Use path-style bucket URLs (`HH_S3_PATH_STYLE`). This matches the
              server default and is what MinIO and Ceph expect. Set false for
              AWS virtual-hosted-style URLs.
            '';
          };

          redirect = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Redirect downloads to presigned bucket URLs (`HH_S3_REDIRECT`)
              instead of proxying bytes. Clients must be able to reach the bucket.
            '';
          };
        };
      };
    };

    environmentFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/run/secrets/hugginghub.env";
      description = ''
        Absolute path to a systemd `EnvironmentFile` on the host. It is not
        copied into the Nix store; pass a string, not a Nix path. Use it for
        `HH_S3_ACCESS_KEY` and `HH_S3_SECRET_KEY` (or `AWS_ACCESS_KEY_ID` and
        `AWS_SECRET_ACCESS_KEY`) when {option}`services.hugginghub.storage`
        is `s3`. systemd reads the file as root and passes the variables to
        the service.
      '';
    };

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = lib.literalExpression ''
        {
          HH_SITE_NAME = "LAN Hub";
        }
      '';
      description = ''
        Extra environment variables for the service, applied after the options
        above so they can override them. Values are written into the unit in
        the Nix store. Do not put access keys or other secrets here; use
        {option}`services.hugginghub.environmentFile`.
      '';
    };
  };

  config = mkIf cfg.enable {
    warnings = optional (cfg.storage == "s3" && cfg.environmentFile == null) ''
      services.hugginghub.storage is "s3" but services.hugginghub.environmentFile
      is not set. HuggingHub reads HH_S3_ACCESS_KEY and HH_S3_SECRET_KEY (or
      AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY) from the environment and
      will not start without them. Point environmentFile at an absolute path
      outside the Nix store.
    '';

    assertions = [
      {
        assertion = cfg.address != "" && lib.match "[^[:space:]/]+" cfg.address != null;
        message = "services.hugginghub.address must be a non-empty address without spaces.";
      }
      {
        assertion = lib.hasPrefix "/" cfg.dataDir && lib.match "/[^[:space:]]+" cfg.dataDir != null;
        message = "services.hugginghub.dataDir must be an absolute path without whitespace.";
      }
      {
        assertion =
          !lib.hasPrefix "/var/lib/" cfg.dataDir || (stateRelative != "" && !lib.hasInfix ".." stateRelative);
        message = "services.hugginghub.dataDir under /var/lib must be a subdirectory StateDirectory can create.";
      }
      {
        assertion = cfg.storage != "s3" || (cfg.s3.bucket != null && cfg.s3.bucket != "");
        message = "services.hugginghub.s3.bucket must be set when services.hugginghub.storage is \"s3\".";
      }
      {
        assertion = cfg.environmentFile == null || lib.hasPrefix "/" cfg.environmentFile;
        message = "services.hugginghub.environmentFile must be an absolute path so systemd can read it on the host. Pass a string, not a Nix path.";
      }
      {
        assertion = cfg.lfsThreshold >= 0;
        message = "services.hugginghub.lfsThreshold must be zero or positive.";
      }
    ];

    environment.systemPackages = [ cli ];

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      createHome = false;
      description = "HuggingHub service user";
    };
    users.groups.${cfg.group} = { };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.hugginghub = {
      description = "HuggingHub, self-hosted Hugging Face Hub";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ cfg.gitPackage ];
      environment = environment;
      # Plain attrsets, not nested mkIf: serviceConfig does not merge conditional
      # values inside one definition, and a leftover mkIf would be written into
      # the unit as an attribute set.
      serviceConfig = {
        ExecStart = lib.getExe cfg.package;
        WorkingDirectory = cfg.dataDir;
        User = cfg.user;
        Group = cfg.group;
        Restart = "on-failure";
        RestartSec = "2s";
        UMask = "0027";
        LimitNOFILE = 65536;
        # Ambient capabilities are ignored when NoNewPrivileges is true.
        NoNewPrivileges = cfg.port >= 1024;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        ReadWritePaths = [ cfg.dataDir ];
      }
      // optionalAttrs useStateDirectory {
        StateDirectory = stateRelative;
        StateDirectoryMode = "0750";
      }
      // optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = cfg.environmentFile;
      }
      // optionalAttrs (cfg.port < 1024) {
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
      };
    };
  };
}
