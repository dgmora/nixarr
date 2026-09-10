# Comprehensive test for Nixarr file permissions, user/group creation, and directory structure
{
  pkgs,
  nixosModules,
  lib ? pkgs.lib,
}:
pkgs.testers.nixosTest {
  name = "nixarr-permissions-test";

  nodes.machine = {
    config,
    pkgs,
    ...
  }: {
    imports = [nixosModules.default];

    networking.firewall.enable = false;

    nixarr = {
      enable = true;
      stateDir = "/data/.state/nixarr";
      mediaDir = "/data/media";
      mediaDirs = [
        "/data/media"
        "/data/media-local"
        {
          path = "/data/media-external";
          create = false;
        }
      ];
      mediaUsers = ["testuser"];

      # Enable key services to trigger tmpfiles directory creation
      jellyfin.enable = true;

      transmission = {
        enable = true;
        vpn.enable = false;
        privateTrackers.cross-seed.enable = true;
      };

      sonarr = {
        enable = true;
        vpn.enable = false;
      };

      radarr = {
        enable = true;
        vpn.enable = false;
      };

      lidarr = {
        enable = true;
        vpn.enable = false;
      };

      prowlarr = {
        enable = true;
        vpn.enable = false;
      };
    };

    # Create a test user to verify mediaUsers functionality
    users.users.testuser = {
      isNormalUser = true;
      home = "/home/testuser";
    };
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    print("Starting Nixarr permissions test...")

    # Test 1: Verify key users and groups exist
    print("\n=== Testing User/Group Creation ===")

    # Check essential users exist
    key_users = ["jellyfin", "transmission", "sonarr", "radarr", "testuser"]
    for user in key_users:
        machine.succeed(f"id {user}")
        print(f"✓ User {user} exists")

    # Check media group exists and has correct members
    media_members = machine.succeed("getent group media | cut -d: -f4").strip()
    expected_members = ["jellyfin", "transmission", "sonarr", "radarr", "lidarr", "testuser"]
    for member in expected_members:
        if member in media_members:
            print(f"✓ {member} is in media group")
        else:
            machine.fail(f"{member} not in media group")

    # Test 2: Verify directory structure and ownership
    print("\n=== Testing Directory Permissions ===")

    def check_dir(path, expected_user, expected_group, description):
        stat_output = machine.succeed(f"stat -c '%U:%G' '{path}'").strip()
        user, group = stat_output.split(":")
        if user == expected_user and group == expected_group:
            print(f"✓ {description}: {user}:{group}")
        else:
            machine.fail(f"{description} has wrong ownership: {user}:{group}, expected {expected_user}:{expected_group}")

    # Check primary and additional managed roots exist with correct ownership
    for media_root in ["/data/media", "/data/media-local"]:
        check_dir(media_root, "root", "media", f"Media root directory {media_root}")
        check_dir(f"{media_root}/library/movies", "root", "media", f"Movies directory {media_root}")
        check_dir(f"{media_root}/library/shows", "root", "media", f"Shows directory {media_root}")
        check_dir(f"{media_root}/library/music", "root", "media", f"Music directory {media_root}")

    # A create=false root must not be materialized by Nixarr.
    machine.fail("test -e /data/media-external")
    print("✓ create=false media root was not created")

    # Download clients still use the canonical mediaDir.
    check_dir("/data/media/torrents", "transmission", "media", "Torrents directory")
    machine.fail("test -e /data/media-local/torrents")

    # Test 3: Verify service file access
    print("\n=== Testing Service File Access ===")

    # Test Jellyfin can write to media directories
    test_dirs = [
        "/data/media/library/movies",
        "/data/media/library/shows",
        "/data/media-local/library/movies",
        "/data/media-local/library/shows",
    ]
    for test_dir in test_dirs:
        if machine.succeed(f"test -d '{test_dir}' && echo 'exists' || echo 'missing'").strip() == "exists":
            test_file = f"{test_dir}/jellyfin-test.txt"
            machine.succeed(f"sudo -u jellyfin touch '{test_file}'")
            machine.succeed(f"sudo -u jellyfin sh -c 'echo test > {test_file}'")
            content = machine.succeed(f"cat '{test_file}'").strip()
            if content != "test":
                machine.fail(f"Expected 'test' but got '{content}'")
            machine.succeed(f"sudo -u jellyfin rm '{test_file}'")
            print(f"✓ Jellyfin can write/read/delete in {test_dir}")

    # Test 4: Verify fix-permissions command
    print("\n=== Testing fix-permissions Command ===")

    # Create files with wrong permissions on both managed roots.
    test_files = [
        "/data/media/library/movies/test-wrong-perms.txt",
        "/data/media-local/library/movies/test-wrong-perms.txt",
    ]
    for test_file in test_files:
        machine.succeed(f"umask 077 && touch '{test_file}'")
        initial_perms = machine.succeed(f"stat -c '%a' '{test_file}'").strip()
        if initial_perms != "600":
            machine.fail(f"Expected 600 permissions, got {initial_perms}")

    machine.succeed("nixarr fix-permissions")

    for test_file in test_files:
        fixed_perms = machine.succeed(f"stat -c '%a' '{test_file}'").strip()
        if fixed_perms not in ["644", "664"]:
            machine.fail(f"fix-permissions failed: permissions are {fixed_perms}, expected 644 or 664")
        machine.succeed(f"rm '{test_file}'")
        print(f"✓ fix-permissions corrected {test_file} to {fixed_perms}")

    # fix-permissions must also leave an absent create=false root absent.
    machine.fail("test -e /data/media-external")

    print("\n=== All Permission Tests Completed ===")
  '';
}
