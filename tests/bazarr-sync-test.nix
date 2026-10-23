{
  pkgs,
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "bazarr-sync-test";

  nodes.machine = {
    config,
    pkgs,
    ...
  }: {
    imports = [nixosModules.default];

    networking.firewall.enable = false;

    # Exercise settings sync with Bazarr served under a URL prefix.
    systemd.services.bazarr.serviceConfig.Environment = "DYNACONF_GENERAL__BASE_URL=/bazarr";

    virtualisation.cores = 4; # one per service plus one for luck

    nixarr = {
      enable = true;

      bazarr = {
        enable = true;
        settings-sync = {
          baseUrl = "http://127.0.0.1:6767/bazarr";
          sonarr = {
            enable = true;
            config.sync_only_monitored_series = true;
          };
          radarr = {
            enable = true;
            config.sync_only_monitored_movies = true;
          };
        };
      };

      sonarr = {
        enable = true;
      };

      radarr = {
        enable = true;
      };
    };
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # Check that main services are active
    machine.succeed("systemctl is-active bazarr")
    machine.succeed("systemctl is-active sonarr")
    machine.succeed("systemctl is-active radarr")

    # Wait for service APIs
    machine.wait_for_unit("bazarr-api.service")
    machine.wait_for_unit("sonarr-api.service")
    machine.wait_for_unit("radarr-api.service")

    # Once the APIs are up, the sync service shouldn't take long
    machine.wait_for_unit("bazarr-sync-config.service", timeout=60)
    machine.succeed("systemctl is-active bazarr-sync-config.service")

    # A successful oneshot does not prove that Bazarr accepted its settings.
    machine.succeed("""
      ${pkgs.curl}/bin/curl -fsS \\
        -H "X-API-KEY: $(cat /data/.state/nixarr/secrets/bazarr.api-key)" \\
        http://127.0.0.1:6767/bazarr/api/system/settings \\
        | ${pkgs.jq}/bin/jq -e '
          .general.use_sonarr == true and
          .general.use_radarr == true and
          .sonarr.only_monitored == true and
          .radarr.only_monitored == true and
          .sonarr.port == 8989 and
          .radarr.port == 7878
        '
    """)

    print("\n=== Bazarr Sync Test Completed ===")
  '';
}
