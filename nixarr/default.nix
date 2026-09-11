{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr;
  globals = config.util-nixarr.globals;
  primaryMediaDir =
    if cfg.mediaDirs == []
    then {
      path = cfg.mediaDir;
      create = true;
    }
    else head cfg.mediaDirs;
  managedDownloadClientEnabled = cfg.transmission.enable || cfg.qbittorrent.enable || cfg.sabnzbd.enable;
in {
  imports = [
    ./anchorr
    ./audiobookshelf
    ./autobrr
    ./bazarr
    ./ddns
    ./jellyfin
    ./jellyseerr
    ./seerr
    ./lib
    ./komga
    ./lidarr
    ./nixarr-command
    ./openssh
    ./plex
    ./prowlarr
    ./qbittorrent
    ./radarr
    ./shelfmark
    ./recyclarr
    ./sabnzbd
    ./sonarr
    ./transmission
    ./whisparr
    ./monitoring
    ../util
  ];

  options.nixarr = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the nixarr module. Has the following features:

        - **Run services through a VPN:** You can run any service that this module
          supports through a VPN, fx `nixarr.transmission.vpn.enable = true;`
        - **Automatic Directories, Users and Permissions:** The module automatically
          creates directories and users for your media library. It also sets sane
          permissions.
        - **State Management:** All services support state management and all state
          that they manage is located by default in `/data/.state/nixarr/*`
        - **Optional Automatic Port Forwarding:** This module has a UPNP support that
          lets services request ports from your router automatically, if you enable it.

        Also comes with the `nixarr` command that helps you manage your library.

        It is possible, _but not recommended_, to run the "*Arrs" behind a VPN,
        because it can cause rate limiting issues. Generally, you should use
        VPN on transmission and maybe jellyfin, depending on your setup.

        The following services are supported:

        - [Anchorr](#nixarr.anchorr.enable)
        - [Audiobookshelf](#nixarr.audiobookshelf.enable)
        - [Autobrr](#nixarr.autobrr.enable)
        - [Bazarr](#nixarr.bazarr.enable)
        - [Jellyfin](#nixarr.jellyfin.enable)
        - [Seerr](#nixarr.seerr.enable)
        - [Lidarr](#nixarr.lidarr.enable)
        - [Plex](#nixarr.plex.enable)
        - [Prowlarr](#nixarr.prowlarr.enable)
        - [qBittorrent](#nixarr.qbittorrent.enable)
        - [Radarr](#nixarr.radarr.enable)
        - [Shelfmark](#nixarr.shelfmark.enable)
        - [Recyclarr](#nixarr.recyclarr.enable)
        - [SABnzbd](#nixarr.sabnzbd.enable)
        - [Sonarr](#nixarr.sonarr.enable)
        - [Transmission](#nixarr.transmission.enable)

        Remember to read the options!
      '';
    };

    mediaUsers = mkOption {
      type = with types; listOf str;
      default = [];
      example = ["user"];
      description = ''
        Extra users to add to the media group.
      '';
    };

    mediaDir = mkOption {
      type = types.path;
      default = "/data/media";
      example = "/nixarr";
      description = ''
        Legacy single media directory option, kept for backwards compatibility.
        When `nixarr.mediaDirs` is not set, it defaults to a single entry using
        this path. New multi-root configurations should set `nixarr.mediaDirs`
        directly instead.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   mediaDir = /home/user/nixarr
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    mediaDirs = mkOption {
      type = types.listOf (
        types.coercedTo types.path
          (path: {inherit path;})
          (types.submodule {
            options = {
              path = mkOption {
                type = types.path;
                description = "Path to a media directory.";
              };

              create = mkOption {
                type = types.bool;
                default = true;
                description = ''
                  Whether Nixarr should create the media root and service
                  library directories below it. Set this to false for a
                  mountpoint that must not be recreated when its filesystem
                  is absent.
                '';
              };
            };
          })
      );
      default = [cfg.mediaDir];
      defaultText = literalExpression "[ config.nixarr.mediaDir ]";
      example = [
        {
          path = "/mnt/media";
          create = false;
        }
        "/local-media"
      ];
      description = ''
        Media directories whose library structure Nixarr should manage. The
        first entry is the primary/canonical media root.

        A plain path is shorthand for `{ path = <path>; create = true; }`.
        Existing configurations that only set `nixarr.mediaDir` keep working:
        `mediaDirs` defaults to `[ mediaDir ]`.

        Nixarr-managed download clients still use the legacy `mediaDir`
        internally for now, so when one of them is enabled it must match the
        first `mediaDirs` entry and that entry must have `create = true`.
      '';
    };

    stateDir = mkOption {
      type = types.path;
      default = "/data/.state/nixarr";
      example = "/nixarr/.state";
      description = ''
        The location of the state directory for the services.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   stateDir = /home/user/nixarr/.state
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    vpn = {
      enable = mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = ''
          **Required options:** [`nixarr.vpn.wgConf`](#nixarr.vpn.wgconf)

          Whether or not to enable VPN support for the services that nixarr
          supports.
        '';
      };

      wgConf = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "/data/.secret/vpn/wg.conf";
        description = "The path to the wireguard configuration file.";
      };

      accessibleFrom = mkOption {
        type = with types; listOf str;
        default = [];
        description = ''
          What IP's the VPN submodule should be accessible from. By default
          the following are included:

          - "192.168.1.0/24"
          - "192.168.0.0/24"
          - "127.0.0.1"

          Otherwise, you would not be able to services over your local
          network. You might have to use this option to extend your list
          with your local IP range by passing it with this option.
        '';
        example = ["192.168.2.0/24"];
      };

      vpnTestService = {
        enable = mkEnableOption ''
          the vpn test service. Useful for testing DNS leaks or if the VPN
          port forwarding works correctly.
        '';

        port = mkOption {
          type = with types; nullOr port;
          default = null;
          example = 58403;
          description = ''
            The port that netcat listens to on the vpn test service. If set to
            `null`, then netcat will not be started.
          '';
        };
      };

      openTcpPorts = mkOption {
        type = with types; listOf port;
        default = [];
        description = ''
          What TCP ports to allow traffic from. You might need this if you're
          port forwarding on your VPN provider and you're setting up services
          not covered in by this module that uses the VPN.
        '';
        example = [46382 38473];
      };

      openUdpPorts = mkOption {
        type = with types; listOf port;
        default = [];
        description = ''
          What UDP ports to allow traffic from. You might need this if you're
          port forwarding on your VPN provider and you're setting up services
          not covered in by this module that uses the VPN.
        '';
        example = [46382 38473];
      };

      proxyListenAddr = mkOption {
        type = types.str;
        default = "0.0.0.0";
        example = "127.0.0.1";
        description = ''
          The address that the nginx proxy should listen on when proxying
          VPN-confined services. By default, it listens on all interfaces
          (0.0.0.0), but you can set this to "127.0.0.1" if you want to
          only expose services locally and then use another reverse proxy
          (like Caddy) for external access.
        '';
      };

      exposeOnLAN = mkOption {
        type = types.bool;
        default = true;
        example = false;
        description = ''
          Whether to allow direct LAN access to VPN-confined services. When
          enabled (default), services are accessible from the local network
          (all RFC 1918 private ranges: 10.0.0.0/8, 172.16.0.0/12,
          192.168.0.0/16). When disabled, services are only accessible from
          localhost (127.0.0.1), which is useful when using a reverse proxy
          like Caddy for all external access.

          This is controlled by the VPN namespace firewall rules via the
          accessibleFrom configuration.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.vpn.enable -> cfg.vpn.wgConf != null;
        message = ''
          The nixarr.vpn.enable option requires the nixarr.vpn.wgConf option
          to be set, but it was not.
        '';
      }
      {
        assertion = cfg.mediaDirs != [];
        message = "nixarr.mediaDirs must contain at least one media directory.";
      }
      {
        assertion =
          !managedDownloadClientEnabled
          || (primaryMediaDir.path == cfg.mediaDir && primaryMediaDir.create);
        message = ''
          A Nixarr-managed download client is enabled, but the first
          nixarr.mediaDirs entry does not match nixarr.mediaDir or has
          create = false. Transmission, qBittorrent and SABnzbd still use the
          legacy nixarr.mediaDir path internally and require it to be managed.
        '';
      }
    ];

    users.groups.media.members = cfg.mediaUsers;

    systemd.tmpfiles.rules = map (
      media: "d '${media.path}'  2775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
    ) (filter (media: media.create) cfg.mediaDirs);

    environment.systemPackages = with pkgs; [
      jdupes
    ];

    vpnNamespaces.wg = mkIf cfg.vpn.enable {
      enable = true;
      openVPNPorts = optional (cfg.vpn.vpnTestService.port != null) {
        port = cfg.vpn.vpnTestService.port;
        protocol = "tcp";
      };
      accessibleFrom =
        (
          if cfg.vpn.exposeOnLAN
          then [
            "10.0.0.0/8"
            "172.16.0.0/12"
            "192.168.0.0/16"
            "127.0.0.1"
          ]
          else ["127.0.0.1"]
        )
        ++ cfg.vpn.accessibleFrom;
      wireguardConfigFile = cfg.vpn.wgConf;
    };

    systemd.services.vpn-test-service = mkIf cfg.vpn.vpnTestService.enable {
      enable = true;

      vpnConfinement = {
        enable = true;
        vpnNamespace = "wg";
      };

      script = let
        vpn-test = pkgs.writeShellApplication {
          name = "vpn-test";

          runtimeInputs = with pkgs; [util-linux unixtools.ping coreutils curl bash libressl netcat-gnu openresolv dig];

          text =
            ''
              cd "$(mktemp -d)"

              # DNS information
              dig google.com

              # Print resolv.conf
              echo "/etc/resolv.conf contains:"
              cat /etc/resolv.conf

              # Check if resolvconf is available
              if command -v resolvconf >/dev/null 2>&1; then
                # Query resolvconf
                echo "resolvconf output:"
                resolvconf -l
                echo ""
              fi

              # Get ip
              echo "Getting IP:"
              curl -s ipinfo.io

              echo -ne "DNS leak test:"
              curl -s https://raw.githubusercontent.com/macvk/dnsleaktest/b03ab54d574adbe322ca48cbcb0523be720ad38d/dnsleaktest.sh -o dnsleaktest.sh
              chmod +x dnsleaktest.sh
              ./dnsleaktest.sh
            ''
            + (
              if cfg.vpn.vpnTestService.port != null
              then ''
                echo "starting netcat on port ${builtins.toString cfg.vpn.vpnTestService.port}:"
                nc -vnlp ${builtins.toString cfg.vpn.vpnTestService.port}
              ''
              else ""
            );
        };
      in "${vpn-test}/bin/vpn-test";
    };
  };
}
