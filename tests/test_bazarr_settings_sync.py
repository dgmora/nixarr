"""Regression tests for the Bazarr settings API request format."""

import importlib.util
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs


SCRIPT = Path(__file__).resolve().parents[1] / "nixarr/bazarr/settings-sync/sync_settings.py"
spec = importlib.util.spec_from_file_location("bazarr_sync_settings", SCRIPT)
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class SettingsHandler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        if self.path != self.server.api_path or self.headers.get("X-API-KEY") != "bazarr-key":
            self.send_error(404)
            return
        if self.headers.get_content_type() != "application/x-www-form-urlencoded":
            self.send_error(415)
            return
        size = int(self.headers["Content-Length"])
        fields = parse_qs(self.rfile.read(size).decode("utf-8"))
        self.server.posts.append({key: values[0] for key, values in fields.items()})
        self.send_response(204)
        self.end_headers()


class BazarrSyncTests(unittest.TestCase):
    def test_form_encoding_flags_and_url_prefix(self):
        for prefix in ("", "/bazarr"):
            with self.subTest(prefix=prefix), tempfile.TemporaryDirectory() as tmp:
                temp = Path(tmp)
                for name in ("bazarr", "sonarr", "radarr"):
                    (temp / name).write_text(f"{name}-key\n", encoding="utf-8")

                with ThreadingHTTPServer(("127.0.0.1", 0), SettingsHandler) as server:
                    server.api_path = f"{prefix}/api/system/settings"
                    server.posts = []
                    thread = threading.Thread(target=server.serve_forever, daemon=True)
                    thread.start()
                    try:
                        sync.main(sync.SettingsSyncConfig(
                            bazarr_base_url=f"http://127.0.0.1:{server.server_port}{prefix}/",
                            bazarr_api_key_file=str(temp / "bazarr"),
                            sonarr=sync.SonarrConfig(
                                base_url="/sonarr",
                                apiKeyFile=str(temp / "sonarr"),
                                sync_only_monitored_series=True,
                            ),
                            radarr=sync.RadarrConfig(
                                base_url="/radarr",
                                apiKeyFile=str(temp / "radarr"),
                                sync_only_monitored_movies=False,
                            ),
                        ))
                    finally:
                        server.shutdown()
                        thread.join()

                    self.assertEqual(len(server.posts), 2)
                    sonarr, radarr = server.posts
                    self.assertEqual(sonarr["settings-general-use_sonarr"], "true")
                    self.assertEqual(sonarr["settings-sonarr-only_monitored"], "true")
                    self.assertEqual(sonarr["settings-sonarr-ssl"], "false")
                    self.assertEqual(sonarr["settings-sonarr-base_url"], "/sonarr")
                    self.assertEqual(sonarr["settings-sonarr-apikey"], "sonarr-key")
                    self.assertEqual(sonarr["settings-sonarr-series_sync"], "60")
                    self.assertNotIn("settings-sonarr-episodes_sync", sonarr)
                    self.assertEqual(radarr["settings-general-use_radarr"], "true")
                    self.assertEqual(radarr["settings-radarr-only_monitored"], "false")
                    self.assertEqual(radarr["settings-radarr-ssl"], "false")
                    self.assertEqual(radarr["settings-radarr-base_url"], "/radarr")
                    self.assertEqual(radarr["settings-radarr-apikey"], "radarr-key")
                    self.assertEqual(radarr["settings-radarr-movies_sync"], "60")
                    self.assertNotIn("settings-sonarr-full_update", sonarr)
                    self.assertNotIn("settings-radarr-full_update", radarr)


if __name__ == "__main__":
    unittest.main()
