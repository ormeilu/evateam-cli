"""Diagnostics contracts; runs only against loopback and temporary private caches.

Run: PATH="$HOME/.pixi/bin:$PATH" pixi run python -m unittest discover -s tests -p test_diagnostics.py -v
Set EVA_BIN to route command tests through an integrated binary as well.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRATCH = Path.home() / ".hermes/cache/scratch"
DRIVER = '''from std.sys import argv, stderr, exit
from eva.diagnostics import error_hint, print_raw_reply, schema, schema_classes, context, cheatsheet, public_address
from std.os import getenv
from eva.args import Args
from eva.client import Reply, Config, Client
from eva.json import JsonDoc
from eva.render import Out

def main() raises:
    var raw = argv()
    if len(raw) > 2 and raw[1] == "hint":
        print(error_hint(raw[2]))
    elif raw[1] == "address":
        print(public_address(String(raw[2])))
    elif raw[1] == "raw":
        var d = JsonDoc()
        var root = d.parse(raw[2])
        var r = Reply(d^, root)
        var opts = List[String]()
        for i in range(3, len(raw)):
            opts.append(raw[i])
        var args = Args(opts)
        var ui = Out(args.has("full"))
        if args.has("tty"):
            ui.tty = True
        print_raw_reply(r, args, ui)
    else:
        var opts = List[String]()
        for i in range(1, len(raw)):
            var value = String(raw[i])
            if value == "--classes" or value == "--relations" or value == "--refresh":
                value += "=true"
            opts.append(value)
        var args = Args(opts)
        if args.pos(0) == "cheatsheet":
            cheatsheet()
            return
        if args.pos(0) == "schema" and args.has("classes"):
            schema_classes()
            return
        var cfg = Config()
        cfg.url = getenv("EVA_URL")
        cfg.token = getenv("EVA_API_KEY")
        cfg.source = "the environment"
        var client = Client(cfg^, False)
        if args.pos(0) == "context":
            context(client, args, Out(False))
        else:
            schema(client, args, Out(False))
'''


def fixture_env(**overrides):
    """Never let an inherited profile override the loopback fixture identity."""
    env = {key: value for key, value in os.environ.items() if not key.startswith("EVA_")}
    env.update(overrides)
    return env


class DiagnosticsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        cls.tmp = tempfile.TemporaryDirectory(prefix="eva-diagnostics-", dir=SCRATCH)
        cls.work = Path(cls.tmp.name)
        cls.bin = cls.work / "diagnostics"
        source = cls.work / "driver.mojo"
        source.write_text(DRIVER)
        pixi = shutil.which("pixi") or str(Path.home() / ".pixi/bin/pixi")
        result = subprocess.run([pixi, "run", "mojo", "build", "-I", str(ROOT / "src"), str(source), "-o", str(cls.bin)], cwd=ROOT, text=True, capture_output=True)
        if result.returncode:
            raise AssertionError("diagnostics scratch driver did not build:\n" + result.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def run_driver(self, *args, env=None):
        target = os.environ.get("EVA_BIN") if args[0] in ("schema", "context", "cheatsheet") else None
        return subprocess.run([str(Path(target).resolve()) if target else str(self.bin), *args], cwd=self.work, env=env, text=True, capture_output=True, timeout=30)

    def test_context_address_hides_url_secrets(self):
        result = self.run_driver("address", "https://someone:password@example.invalid:8443/private-token?api_key=secret#secret")
        self.assertEqual(result.stdout.strip(), "https://example.invalid:8443")

    def test_raw_64k_boundary_and_unicode_single_line(self):
        import json
        cache = self.work / "boundary-cache"
        env = fixture_env(XDG_CACHE_HOME=str(cache))
        # JSON string quotes are two bytes, and Mojo pretty printing adds no indent.
        exact = json.dumps("x" * 65534)
        result = self.run_driver("raw", exact, env=env)
        self.assertEqual(json.loads(result.stdout), "x" * 65534)
        self.assertFalse(cache.exists())
        over = self.run_driver("raw", json.dumps("x" * 65535), env=env)
        self.assertEqual(over.returncode, 0, over.stderr)
        self.assertLess(len(over.stdout), 1000)
        unicode = self.run_driver("raw", json.dumps("Ж" * 40000), env=env)
        self.assertEqual(unicode.returncode, 0, unicode.stderr)
        self.assertLess(len(unicode.stdout), 1000)
        self.assertEqual(len(list(cache.rglob("raw-*.json"))), 2)

    def test_schema_fifo_cache_does_not_block(self):
        from mock_diagnostics import DiagnosticsServer
        server = DiagnosticsServer()
        self.addCleanup(server.close)
        cache = self.work / "fifo-cache"
        env = fixture_env(XDG_CACHE_HOME=str(cache), EVA_URL=server.url, EVA_API_KEY="fixture-not-a-token")
        first = self.run_driver("schema", "CmfTask", env=env)
        self.assertEqual(first.returncode, 0, first.stderr)
        path = next(cache.rglob("schema-*.json"))
        path.unlink()
        os.mkfifo(path, 0o600)
        binary = str(Path(os.environ["EVA_BIN"]).resolve()) if os.environ.get("EVA_BIN") else str(self.bin)
        result = subprocess.run([binary, "schema", "CmfTask"], cwd=self.work, env=env, capture_output=True, text=True, timeout=2)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(path.is_file())
        self.assertEqual(len(server.calls), 2)

    def test_schema_cache_refuses_symlink_file_and_recovers(self):
        import json
        from mock_diagnostics import DiagnosticsServer
        server = DiagnosticsServer()
        self.addCleanup(server.close)
        cache = self.work / "schema-symlink-cache"
        env = fixture_env(XDG_CACHE_HOME=str(cache), EVA_URL=server.url, EVA_API_KEY="fixture-not-a-token")
        first = self.run_driver("schema", "CmfTask", "--json", env=env)
        self.assertEqual(first.returncode, 0, first.stderr)
        path = next(cache.rglob("schema-*.json"))
        target = self.work / "do-not-overwrite.json"
        target.write_text("PRIVATE-UNRELATED-DATA")
        path.unlink()
        path.symlink_to(target)
        again = self.run_driver("schema", "CmfTask", "--json", env=env)
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertEqual(json.loads(again.stdout), json.loads(first.stdout))
        self.assertEqual(len(server.calls), 2)
        self.assertEqual(target.read_text(), "PRIVATE-UNRELATED-DATA")
        self.assertFalse(path.is_symlink())
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_context_hidden_rows_and_project_failure_are_honest(self):
        from mock_diagnostics import DiagnosticsServer
        server = DiagnosticsServer()
        self.addCleanup(server.close)
        server.hidden_tasks = True
        env = fixture_env(EVA_URL=server.url, EVA_API_KEY="fixture-not-a-token")
        result = self.run_driver("context", env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("open >=1", result.stdout)
        self.assertIn("activity: >=1", result.stdout)
        server.fail.add("CmfProject.list")
        failed = self.run_driver("context", env=env)
        self.assertEqual(failed.returncode, 0, failed.stderr)
        self.assertIn("projects: unavailable", failed.stdout)
        self.assertIn("activity: >=1", failed.stdout)

    @unittest.skipUnless(os.environ.get("EVA_BIN"), "set EVA_BIN to test main integration")
    def test_integrated_main_help_raw_reply_and_error_exit(self):
        import json
        from mock_diagnostics import DiagnosticsServer
        server = DiagnosticsServer()
        self.addCleanup(server.close)
        cache = self.work / "integrated-cache"
        env = fixture_env(XDG_CACHE_HOME=str(cache), EVA_URL=server.url, EVA_API_KEY="fixture-not-a-token")
        binary = str(Path(os.environ["EVA_BIN"]).resolve())
        def run(*args):
            return subprocess.run([binary, *args], cwd=self.work, env=env, text=True, capture_output=True, timeout=30)
        help_result = run("--help")
        for name in ("schema", "context", "cheatsheet"):
            self.assertIn(name, help_result.stdout)
        server.metadata["large_result"] = "x" * 70000
        raw = run("call", "CmfTask.get_meta")
        self.assertEqual(raw.returncode, 0, raw.stderr)
        self.assertLess(len(raw.stdout), 12000)
        spill = next(cache.rglob("raw-*.json"))
        self.assertEqual(json.loads(spill.read_text()), server.metadata)
        self.assertNotIn("fixture-not-a-token", spill.read_text())
        full = run("call", "CmfTask.get_meta", "--full")
        self.assertEqual(json.loads(full.stdout), server.metadata)
        server.errors["CmfTask.create"] = {"message": "required field: name", "code": -32000}
        error = run("call", "CmfTask.create")
        self.assertEqual(error.returncode, 1)
        self.assertIn("required field: name", error.stderr)
        self.assertIn("--set", error.stderr)
        self.assertEqual(error.stdout, "")
        unknown = run("call", "CmfUnknown.list")
        self.assertEqual(unknown.returncode, 1)
        self.assertIn("Method not found", unknown.stderr)
        self.assertIn("schema --classes", unknown.stderr)

    def test_cheatsheet_is_offline_and_recipes_match_dispatcher(self):
        import re
        import shlex
        result = self.run_driver("cheatsheet", env={"PATH": os.environ["PATH"], "HOME": str(self.work / "missing-home")})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(re.findall(r"^\d+\. ", result.stdout, re.M)), 10)
        commands = [shlex.split(line.strip()) for line in result.stdout.splitlines() if line.strip().startswith("eva ")]
        self.assertGreaterEqual(len(commands), 10)
        main = (ROOT / "src/main.mojo").read_text()
        for command in commands:
            group = command[1]
            if group in ("schema", "context"):
                self.assertIn(f'def {group}(', (ROOT / "src/eva/diagnostics.mojo").read_text())
            else:
                self.assertIn(f'group == "{group}"', main)
            if group in ("task", "time", "project", "attachment"):
                self.assertRegex(main, rf'\b{group} {re.escape(command[2])}\b')
        self.assertIn("DEMO-1", result.stdout)
        self.assertIn("example.invalid", result.stdout)
        self.assertIn("--full", result.stdout)
        self.assertEqual(result.stderr, "")

    def test_context_is_bounded_read_only_and_has_no_project_n_plus_one(self):
        from mock_diagnostics import DiagnosticsServer
        server = DiagnosticsServer()
        self.addCleanup(server.close)
        server.project_count = 100
        server.task_count = 2200
        env = fixture_env(EVA_URL=server.url, EVA_API_KEY="fixture-not-a-token")
        result = self.run_driver("context", env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("alex@example.invalid", result.stdout)
        self.assertIn("the environment", result.stdout)
        self.assertIn("DEMO-0", result.stdout)
        self.assertIn(">=2000", result.stdout)
        self.assertIn(">=200", result.stdout)
        self.assertIn("8 projects", result.stdout)
        self.assertIn("visible", result.stdout)
        self.assertNotIn("fixture-not-a-token", result.stdout + result.stderr)
        self.assertLessEqual(len(result.stdout.splitlines()), 20)
        self.assertEqual(len(server.calls), 4)
        self.assertEqual(sorted(x["method"] for x in server.calls), ["CmfPerson.get_current_user", "CmfProject.list", "CmfTask.list", "CmfTask.list"])
        projects = next(c for c in server.calls if c["method"] == "CmfProject.list")
        self.assertEqual(projects["kwargs"]["slice"], [0, 9])
        task_calls = [c for c in server.calls if c["method"] == "CmfTask.list"]
        self.assertEqual(sorted(c["kwargs"]["slice"][1] for c in task_calls), [201, 2001])
        self.assertTrue(all(c["kwargs"].get("filter") for c in task_calls))

    def test_context_unavailable_sections_are_not_zero(self):
        from mock_diagnostics import DiagnosticsServer
        server = DiagnosticsServer()
        self.addCleanup(server.close)
        server.fail.update(["CmfPerson.get_current_user", "CmfTask.list"])
        result = self.run_driver("context", env=fixture_env(EVA_URL=server.url, EVA_API_KEY="fixture-not-a-token"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("login: unavailable", result.stdout)
        self.assertIn("open unavailable", result.stdout)
        self.assertIn("activity: unavailable", result.stdout)
        self.assertNotIn("open 0", result.stdout)
        self.assertNotIn("fixture-not-a-token", result.stdout + result.stderr)

    def test_schema_filters_locally_refreshes_and_keeps_only_metadata(self):
        import json
        from mock_diagnostics import DiagnosticsServer
        server = DiagnosticsServer()
        self.addCleanup(server.close)
        cache = self.work / "schema-cache"
        env = fixture_env(XDG_CACHE_HOME=str(cache), EVA_URL=server.url, EVA_API_KEY="fixture-not-a-token")
        def run(*opts):
            result = self.run_driver("schema", "CmfTask", *opts, env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout
        first = run("-q", "title")
        self.assertIn("name", first)
        self.assertNotIn("project", first)
        self.assertIn("project", run("--relations"))
        self.assertEqual([x["method"] for x in server.calls], ["CmfTask.get_meta"])
        server.metadata["fields"]["object_link"] = {"widget": "CmfGenericRelation", "models": []}
        relations = run("--relations", "--refresh")
        self.assertIn("object_link", relations)
        server.calls.clear()
        run("--refresh")
        self.assertEqual([x["method"] for x in server.calls], ["CmfTask.get_meta"])
        self.assertNotIn("filter", server.calls[0].get("kwargs", {}))
        paths = list(cache.rglob("schema-*.json"))
        self.assertEqual(len(paths), 1)
        stored = paths[0].read_text()
        self.assertNotIn("NEVER-CACHE", stored)
        self.assertNotIn("fixture-not-a-token", stored)
        self.assertEqual(paths[0].stat().st_mode & 0o777, 0o600)
        run("--refresh")
        self.assertEqual(len(server.calls), 2)
        entry = json.loads(paths[0].read_text())
        entry["created"] = 1
        paths[0].write_text(json.dumps(entry))
        run()
        self.assertEqual(len(server.calls), 3)
        entry["created"] = 9999999999
        paths[0].write_text(json.dumps(entry))
        run()
        self.assertEqual(len(server.calls), 4)
        paths[0].write_text("{not json")
        run()
        self.assertEqual(len(server.calls), 5)
        other = DiagnosticsServer()
        self.addCleanup(other.close)
        result = self.run_driver("schema", "CmfTask", env=dict(env, EVA_URL=other.url))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(other.calls), 1)
        self.assertEqual(len(list(cache.rglob("schema-*.json"))), 2)
        unknown = self.run_driver("schema", "CmfTestPlan", env=env)
        self.assertNotEqual(unknown.returncode, 0)
        self.assertEqual(len(server.calls), 5)

    def test_schema_catalog_covers_literal_model_call_sites(self):
        import re
        result = self.run_driver("schema", "--classes", env={"PATH": os.environ["PATH"]})
        self.assertEqual(result.returncode, 0, result.stderr)
        catalog = set(result.stdout.split())
        self.assertIn("CmfTestplan", catalog)
        self.assertNotIn("CmfTestPlan", catalog)
        classes = set()
        for source in (ROOT / "src/eva").glob("*.mojo"):
            if source.name == "diagnostics.mojo":
                continue
            text = source.read_text()
            classes.update(re.findall(r'"(Cmf[A-Za-z0-9_]+)\.(?:list|get|count|get_meta|create|update|delete)[^"]*"', text))
            for line in text.splitlines():
                if any(name in line for name in ("simple_list(", "id_of(", "get_by_code(", "page_rows(", "page_footer(")):
                    classes.update(re.findall(r'"(Cmf[A-Za-z0-9_]+)"', line))
        self.assertTrue(classes)
        self.assertFalse(classes - catalog, f"Add confirmed new model call sites to SCHEMA_CLASSES: {classes - catalog}")

    def test_large_raw_pipe_is_private_unique_and_bounded(self):
        import json
        payload = {"items": ["x" * 3000 for _ in range(30)]}
        cache = self.work / "raw-cache"
        env = fixture_env(XDG_CACHE_HOME=str(cache), EVA_API_KEY="never-save-this-token")
        result = self.run_driver("raw", json.dumps(payload), env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertLess(len(result.stdout), 12000)
        self.assertIn("bytes", result.stdout)
        self.assertIn("--full", result.stdout)
        paths = list(cache.rglob("raw-*.json"))
        self.assertEqual(len(paths), 1)
        self.assertEqual(json.loads(paths[0].read_text()), payload)
        self.assertEqual(paths[0].stat().st_mode & 0o777, 0o600)
        self.assertNotIn("never-save-this-token", paths[0].read_text())
        again = self.run_driver("raw", json.dumps(payload), env=env)
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertEqual(len(list(cache.rglob("raw-*.json"))), 2)
        full = self.run_driver("raw", json.dumps(payload), "--full", env=env)
        self.assertEqual(json.loads(full.stdout), payload)
        tty = self.run_driver("raw", json.dumps(payload), "--tty=true", env=env)
        self.assertEqual(json.loads(tty.stdout), payload)
        self.assertEqual(len(list(cache.rglob("raw-*.json"))), 2)
        small = self.run_driver("raw", '{"ok":true}', env=env)
        self.assertEqual(json.loads(small.stdout), {"ok": True})

    def test_raw_rejects_symlink_cache_directory(self):
        import json
        cache = self.work / "symlink-cache"
        cache.mkdir()
        target = self.work / "symlink-target"
        target.mkdir()
        (cache / "eva-diagnostics").symlink_to(target, target_is_directory=True)
        result = self.run_driver("raw", json.dumps(["x" * 70000]), env=fixture_env(XDG_CACHE_HOME=str(cache)))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(target.iterdir()), [])

    def test_error_hint_is_separate_and_actionable(self):
        for message in ["required field: name", "field foo is mandatory", "обязательное поле", "Необходимо заполнить Вид услуги"]:
            with self.subTest(message=message):
                result = self.run_driver("hint", message)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("--set", result.stdout)
                self.assertIn("field list", result.stdout)
        self.assertIn("schema --classes", self.run_driver("hint", "Method not found (code -32601)").stdout)
        self.assertEqual(self.run_driver("hint", "unexpected unicorn").stdout.strip(), "")


if __name__ == "__main__":
    unittest.main()
