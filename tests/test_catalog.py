"""Keep the hand-maintained CLI help, READMEs and permissions aligned."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


def command_key(syntax):
    words = syntax.split()
    if words[:2] == ["task", "bulk"]:
        return " ".join(words[:3])
    if len(words) > 1 and re.fullmatch(r"[a-z][a-z-]*", words[1]):
        return " ".join(words[:2])
    return words[0]


class Catalog(unittest.TestCase):
    def test_batch_ledger_has_unique_scope_and_real_test_references(self):
        ledger = (ROOT / "docs/issue-batch.md").read_text()
        rows = re.findall(r"^\| #(\d+) \| (implemented|partial) \|", ledger, re.M)
        ids = [int(number) for number, _ in rows]
        self.assertEqual(ids, list(range(36, 81)))
        self.assertEqual([int(n) for n, state in rows if state == "partial"], [])
        definitions = set()
        for source in (ROOT / "tests").iterdir():
            if source.suffix in (".py", ".mojo"):
                definitions.update(re.findall(r"^\s*def (test_\w+)\(", source.read_text(), re.M))
        for reference in re.findall(r"`(test_\w+)`", ledger):
            self.assertIn(reference, definitions, reference)
        shell = (ROOT / "tests/e2e.sh").read_text()
        self.assertIn('check "update notes side change"', shell)
        self.assertRegex(shell, r'(?m)^no\s+"update no false note"')

    def test_help_readmes_and_permissions_cover_dispatch(self):
        main = (ROOT / "src/main.mojo").read_text()
        help_text = main.split('comptime USAGE = """', 1)[1].split('"""', 1)[0]
        # Exclude prose-only option sections; command rows have a separate
        # description line beginning with six spaces.
        commands = {command_key(m.group(1)) for m in
                    re.finditer(r"^  ([a-z][^\n]+)\n      ", help_text, re.M)}
        table = (ROOT / "src/eva/cli.mojo").read_text()
        dispatched = {group if sub == "ANY" else group + " " + sub.strip('"') for group, sub in
                      re.findall(r'Command\("([a-z-]+)", (ANY|"[a-z-]+")', table)}
        self.assertGreater(len(dispatched), 80)
        for command in dispatched:
            self.assertTrue(any(c == command or c.startswith(command + " ") for c in commands), command)
        setup = (ROOT / "plugin/skills/eva/setup.md").read_text()
        permissions = json.loads(re.search(r"```json\n(.*?)\n```", setup, re.S).group(1))["permissions"]
        classified = {}
        for kind in ("allow", "ask"):
            for pattern in permissions[kind]:
                command = pattern.removeprefix("Bash(eva ").removesuffix(":*)")
                self.assertNotIn(command, classified, command)
                classified[command] = kind
        for command in commands:
            self.assertTrue(any(command == p or command.startswith(p + " ") for p in classified), command)
            for name in ("README.md", "README.en.md"):
                self.assertIn("eva " + command, (ROOT / name).read_text(), (name, command))
        for mutation in ["task bulk", "task create", "task update", "task delete", "task move", "task comment",
                         "task comment-edit", "task comment-delete", "task log", "task attach", "task watch",
                         "task unwatch", "task link", "task unlink", "task check", "time log", "time delete",
                         "doc create", "doc update", "doc publish", "doc comment", "doc comment-edit", "doc attach",
                         "doc watch", "sprint add", "release add", "sprint remove", "release remove",
                         "sprint create", "release create", "sprint update", "release update", "sprint rename",
                         "release rename", "attachment delete", "trash restore", "call"]:
            self.assertEqual(classified[mutation], "ask", mutation)


if __name__ == "__main__":
    unittest.main()
