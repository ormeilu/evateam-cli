"""The update check end to end, against a loopback stand-in for GitHub's
/releases/latest redirect. Set EVA_BIN to test another binary than build/eva."""
import os
from pathlib import Path
import re
import shutil
import ssl
import subprocess
import tempfile
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread

from mock_diagnostics import DiagnosticsServer

ROOT = Path(__file__).resolve().parents[1]
NEWER = "99.0.0"
TOKEN = "fixture-token-must-not-leave"


class ReleaseServer(ThreadingHTTPServer):
    def __init__(self, tls=None):
        super().__init__(("127.0.0.1", 0), ReleaseHandler)
        self.scheme = "http"
        if tls is not None:
            self.socket = tls.wrap_socket(self.socket, server_side=True)
            self.scheme = "https"
        self.requests = []
        self.location = "https://github.com/ormeilu/evateam-cli/releases/tag/v" + NEWER
        self.status = 302
        self.thread = Thread(target=self.serve_forever, daemon=True)
        self.thread.start()

    @property
    def url(self):
        return self.scheme + "://127.0.0.1:" + str(self.server_address[1]) + "/ormeilu/evateam-cli/releases/latest"

    def close(self):
        self.shutdown()
        self.server_close()
        self.thread.join()


class ReleaseHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        self.server.requests.append({"path": self.path, "headers": dict(self.headers)})
        self.send_response(self.server.status)
        if self.server.location is not None:
            self.send_header("Location", self.server.location)
        self.send_header("Content-Length", "0")
        self.end_headers()


class UpdateCheck(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary = str(Path(os.environ.get("EVA_BIN", ROOT / "build/eva")).resolve())
        cls.current = re.search(r'comptime VERSION = "([^"]+)"', (ROOT / "src/main.mojo").read_text()).group(1)

    def setUp(self):
        self.releases = ReleaseServer()
        self.addCleanup(self.releases.close)
        tmp = tempfile.TemporaryDirectory(prefix="eva-update-")
        self.addCleanup(tmp.cleanup)
        self.cache = Path(tmp.name) / "eva-diagnostics"
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("EVA_") and k != "CI"}
        self.env.update(XDG_CACHE_HOME=tmp.name, EVA_UPDATE_URL=self.releases.url,
                        EVA_URL="http://127.0.0.1:9", EVA_API_KEY=TOKEN)

    def eva(self, *args, **env):
        return subprocess.run([self.binary, *args], env={**self.env, **env}, input="", text=True,
                              capture_output=True, timeout=20)

    def wait_for_check(self):
        latest = self.cache / "update-latest"
        for _ in range(100):
            if latest.exists() and latest.read_text().strip():
                return latest.read_text().strip()
            time.sleep(0.1)
        self.fail("the background check saved nothing; requests: " + repr(self.releases.requests))

    def notice(self, latest=NEWER):
        return f"eva {latest} is out (you have {self.current}); update with: eva upgrade"

    def write_state(self, text):
        self.cache.mkdir(mode=0o700, parents=True, exist_ok=True)
        fd = os.open(self.cache / "update-check", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(text)

    def test_check_runs_in_the_background_then_notices_once_a_day(self):
        first = self.eva("cheatsheet")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertNotIn("is out", first.stdout + first.stderr)
        self.assertEqual(self.wait_for_check(), NEWER)
        self.assertEqual(oct((self.cache / "update-latest").stat().st_mode & 0o777), "0o600")

        second = self.eva("cheatsheet")
        self.assertEqual(second.stderr.strip(), self.notice())
        self.assertNotIn("is out", second.stdout)
        third = self.eva("cheatsheet")
        self.assertNotIn("is out", third.stdout + third.stderr)
        # One check per interval, however many runs.
        self.assertEqual(len(self.releases.requests), 1)

    @unittest.skipUnless(shutil.which("openssl"), "needs openssl for a test certificate")
    def test_https_source_is_verified_with_the_system_ca_bundle(self):
        # Release builds bundle OpenSSL, whose compiled-in CA path is the build
        # machine's: the check must use the same CA bundle as EvaTeam calls.
        tls = Path(tempfile.mkdtemp(prefix="eva-tls-"))
        self.addCleanup(shutil.rmtree, tls, True)
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                        "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1",
                        "-keyout", str(tls / "key.pem"), "-out", str(tls / "cert.pem")],
                       check=True, capture_output=True)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(tls / "cert.pem", tls / "key.pem")
        server = ReleaseServer(context)
        self.addCleanup(server.close)
        untrusted = tls / "untrusted-cache"
        self.eva("cheatsheet", EVA_UPDATE_URL=server.url, XDG_CACHE_HOME=str(untrusted))
        time.sleep(3)
        self.assertFalse((untrusted / "eva-diagnostics" / "update-latest").exists())
        self.eva("cheatsheet", EVA_UPDATE_URL=server.url, EVA_CA_BUNDLE=str(tls / "cert.pem"))
        self.assertEqual(self.wait_for_check(), NEWER)

    def test_release_source_gets_no_credentials_or_address(self):
        self.eva("cheatsheet")
        self.wait_for_check()
        request = self.releases.requests[0]
        self.assertEqual(request["path"], "/ormeilu/evateam-cli/releases/latest")
        sent = repr(request)
        self.assertNotIn(TOKEN, sent)
        self.assertNotIn("127.0.0.1:9", sent)
        self.assertNotIn("Authorization", request["headers"])
        self.assertNotIn("Cookie", request["headers"])

    def test_version_and_context_show_a_known_release(self):
        self.eva("cheatsheet")
        self.wait_for_check()
        version = self.eva("--version")
        self.assertEqual(version.stdout, f"eva {self.current}\n")
        self.assertEqual(version.stderr.strip(), self.notice())
        # They show it every time; the daily notice is only for other commands.
        self.assertEqual(self.eva("--version").stderr.strip(), self.notice())
        server = DiagnosticsServer()
        self.addCleanup(server.close)
        context = self.eva("context", EVA_URL=server.url)
        self.assertEqual(context.returncode, 0, context.stderr)
        self.assertIn("update: " + self.notice() + "\n", context.stdout)
        self.assertNotIn("is out", context.stderr)

    def test_stdout_stays_clean_for_machine_output(self):
        self.eva("cheatsheet")
        self.wait_for_check()
        listed = self.eva("schema", "--classes", "--json")
        self.assertEqual(listed.returncode, 0, listed.stderr)
        self.assertNotIn("is out", listed.stdout)
        self.assertIn(self.notice(), listed.stderr)

    def test_due_again_after_the_interval(self):
        self.write_state("checked=1\n")
        self.eva("cheatsheet")
        self.wait_for_check()
        self.assertEqual(len(self.releases.requests), 1)
        self.write_state(f"checked={int(time.time()) - 3 * 3600}\n")
        self.eva("cheatsheet", EVA_UPDATE_CHECK_HOURS="4")
        time.sleep(0.5)
        self.assertEqual(len(self.releases.requests), 1)
        self.eva("cheatsheet", EVA_UPDATE_CHECK_HOURS="2")
        for _ in range(100):
            if len(self.releases.requests) == 2:
                break
            time.sleep(0.1)
        self.assertEqual(len(self.releases.requests), 2)

    def test_opt_out_and_ci_skip_everything(self):
        for env in ({"EVA_NO_UPDATE_CHECK": "1"}, {"CI": "true"}):
            result = self.eva("cheatsheet", **env)
            self.assertEqual(result.returncode, 0, result.stderr)
        time.sleep(0.5)
        self.assertEqual(self.releases.requests, [])
        self.assertFalse((self.cache / "update-check").exists())

    def test_upgrade_does_not_check(self):
        # Only a source build: an installed eva would really upgrade itself.
        if not Path(self.binary).is_relative_to(ROOT):
            self.skipTest("EVA_BIN is an installed eva")
        self.eva("upgrade")
        time.sleep(0.5)
        self.assertEqual(self.releases.requests, [])

    def test_bad_answers_are_ignored(self):
        cases = [
            (302, "https://github.com/ormeilu/evateam-cli/releases/tag/v9.9.9\x1b[2J"),
            (302, "https://github.com/ormeilu/evateam-cli/releases"),
            (200, None),
            (500, None),
        ]
        for status, location in cases:
            with self.subTest(status=status, location=location):
                self.releases.status = status
                self.releases.location = location
                self.releases.requests.clear()
                self.write_state("checked=1\n")
                first = self.eva("cheatsheet")
                self.assertEqual(first.returncode, 0, first.stderr)
                for _ in range(50):
                    if self.releases.requests:
                        break
                    time.sleep(0.1)
                time.sleep(0.3)
                self.assertFalse((self.cache / "update-latest").exists())
                again = self.eva("--version")
                self.assertEqual(again.stderr, "")

    def test_unreachable_source_does_not_slow_or_break_a_command(self):
        start = time.monotonic()
        result = self.eva("cheatsheet", EVA_UPDATE_URL="http://10.255.255.1/releases/latest")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertLess(time.monotonic() - start, 2)
        self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
