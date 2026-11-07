"""CLI integration regressions for the open-issues batch; no live writes."""
import json
import copy
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest
from http.server import HTTPServer

import mock_server


class Features(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.log = Path(cls.tmp.name) / "requests.jsonl"
        cls.log.touch()
        os.environ["MOCK_LOG"] = str(cls.log)
        cls.server = HTTPServer(("127.0.0.1", 0), mock_server.Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.env = {key: value for key, value in os.environ.items() if not key.startswith("EVA_")}
        cls.env.update(EVA_URL=f"http://127.0.0.1:{cls.server.server_port}",
                       EVA_API_KEY="test-token", XDG_CACHE_HOME=cls.tmp.name)
        cls.binary = os.environ.get("EVA_BIN", str(Path("build/eva").resolve()))
        cls.initial = copy.deepcopy({key: getattr(mock_server, key) for key in ["TASKS", "COMMENTS", "ATTACHMENTS", "CREATED", "CREATED_ATTACHMENTS", "DOCUMENTS", "LISTS", "RELATIONS", "CHECK_ITEMS", "CHECKLISTS", "TRASH", "WORKLOG"]})

    def setUp(self):
        for key, value in copy.deepcopy(self.initial).items():
            setattr(mock_server, key, value)
        self.log.write_text("")

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()
        cls.tmp.cleanup()

    def run_cli(self, *args, ok=True):
        proc = subprocess.run([self.binary, *args], env=self.env, input="", text=True,
                              capture_output=True, timeout=20)
        if ok:
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        else:
            self.assertNotEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        return proc.stdout + proc.stderr

    def requests(self, method):
        return [r for r in map(json.loads, self.log.read_text().splitlines())
                if r["method"] == method]

    def test_document_draft_and_explicit_publish(self):
        self.assertIn("created DOC-2", self.run_cli("doc", "create", "-t", "Policy", "--parent", "DOC-1", "-d", "<draft>"))
        req = self.requests("CmfDocument.create")[-1]
        self.assertEqual(req["kwargs"], {"name": "Policy", "tree_parent": "DOC-1", "text_draft": "<p>&lt;draft&gt;</p>"})
        self.assertFalse(self.requests("CmfDocument.do_publish"))
        self.assertIn("draft", self.run_cli("doc", "update", "DOC-2", "-d", "Revised"))
        self.assertIn("published DOC-2", self.run_cli("doc", "publish", "DOC-2"))
        self.assertEqual(self.requests("CmfDocument.do_publish")[-1]["args"], ["CmfDocument:2"])
        self.assertIn("Revised", self.run_cli("doc", "get", "DOC-2"))
        self.assertIn("nothing to change", self.run_cli("doc", "update", "DOC-2", ok=False))
        self.assertIn("not found", self.run_cli("doc", "publish", "DOC-404", ok=False))

    def test_document_comments_and_attachments(self):
        self.assertIn("commented on DOC-1", self.run_cli("doc", "comment", "DOC-1", "Hello"))
        self.assertIn("Hello", self.run_cli("doc", "comments", "DOC-1", "--human", "--ids"))
        path = Path(self.tmp.name) / "wiki.txt"
        path.write_text("wiki file")
        self.assertIn("attached", self.run_cli("doc", "attach", "DOC-1", str(path)))
        self.assertIn("wiki.txt", self.run_cli("doc", "attachments", "DOC-1"))
        self.assertIn("not found", self.run_cli("doc", "comments", "DOC-404", ok=False))

    def test_comment_reply_edit_and_files(self):
        path = Path(self.tmp.name) / "comment.txt"
        path.write_text("evidence")
        self.assertIn("commented on DEV-1", self.run_cli("task", "comment", "DEV-1", "Reply", "--reply-to", "CmfComment:c1", "--attach", str(path)))
        req = self.requests("CmfComment.create")[-1]
        self.assertEqual(req["kwargs"]["tree_parent"], "CmfComment:c1")
        parent = self.requests("CmfAttachment.create")[-1]["kwargs"]["parent"]
        self.assertTrue(parent.startswith("CmfComment:"))
        self.assertIn("edited", self.run_cli("task", "comment-edit", parent, "Fixed"))
        self.assertIn("Fixed", self.run_cli("task", "comments", "DEV-1"))
        self.assertIn("another task", self.run_cli("task", "comment", "DEV-2", "Bad", "--reply-to", "CmfComment:c1", ok=False))
        self.assertIn("cannot read", self.run_cli("task", "comment", "DEV-1", "Bad file", "--attach", str(path) + "missing", ok=False))
        self.assertIn("missing comment text", self.run_cli("task", "comment", "DEV-1", "--attach", str(path), ok=False))

    def test_attachment_delete_confirmation_and_repeat(self):
        path = Path(self.tmp.name) / "remove.txt"
        path.write_text("remove me")
        self.run_cli("doc", "attach", "DOC-1", str(path))
        code = json.loads(self.run_cli("doc", "attachments", "DOC-1", "--json"))[-1]["code"]
        self.assertIn("needs confirmation", self.run_cli("attachment", "delete", code, ok=False))
        self.assertIn("removed", self.run_cli("attachment", "delete", code, "--yes"))
        self.assertIn("no such attachment", self.run_cli("attachment", "get", code, ok=False))
        self.assertIn("no such attachment", self.run_cli("attachment", "delete", code, "--yes", ok=False))

    def test_task_planning_participants_and_tags(self):
        out = self.run_cli("task", "get", "DEV-1")
        for text in ["priority: Высокий", "story points: 3", "planned:", "alarm:", "watchers:", "co-assignees:", "waiting for:", "tags:"]:
            self.assertIn(text, out)
        self.run_cli("task", "update", "DEV-1", "--priority", "low", "--story-points", "5.5", "--plan-start", "2026-11-10", "--plan-end", "2026-11-14", "--alarm", "off", "--co-assignee", "me", "--waiting-for", "me", "--tag", "Backend")
        kw = self.requests("CmfTask.update")[-1]["kwargs"]
        self.assertEqual(kw["priority"], -1)
        self.assertEqual(kw["agile_story_points"], 5.5)
        self.assertIsNone(kw["alarm_date"])
        self.assertEqual(kw["executors"], ["CmfPerson:me"])
        self.assertEqual(kw["waiting_for"], "CmfPerson:me")
        self.assertEqual(kw["tags"], ["CmfTag:backend"])
        self.assertIn("Backend", self.run_cli("tag", "list"))
        for flags in [("--priority", "hihg"), ("--story-points", "nan"), ("--plan-start", "2026-02-30"), ("--plan-start", "2026-11-14", "--plan-end", "2026-11-10")]:
            self.run_cli("task", "update", "DEV-1", *flags, ok=False)
        self.run_cli("task", "update", "DEV-1", "--co-assignee", "none", "--waiting-for", "none", "--tag", "none")
        kw = self.requests("CmfTask.update")[-1]["kwargs"]
        self.assertEqual(kw["tags"], [])
        self.assertIsNone(kw["waiting_for"])

    def test_task_desk_filters(self):
        self.run_cli("task", "list", "--author", "me", "--watching", "me", "--waiting-for", "me", "--archived", "--tag", "Backend")
        flt = self.requests("CmfTask.list")[-1]["kwargs"]["filter"]
        for field in ["cmf_author.login", "spectators.login", "waiting_for.login"]:
            self.assertIn([field, "==", "me@example.ru"], flt)
        self.assertIn(["cmf_archived", "==", True], flt)
        self.assertIn(["tags.name", "==", "Backend"], flt)
        self.run_cli("task", "list", "-a", "me")
        self.assertIn(["responsible.login", "==", "me@example.ru"], self.requests("CmfTask.list")[-1]["kwargs"]["filter"])

    def test_watch_unwatch_idempotent(self):
        for _ in range(2):
            self.assertIn("watching", self.run_cli("task", "watch", "DEV-1"))
        for _ in range(2):
            self.assertIn("not watching", self.run_cli("task", "unwatch", "DEV-1"))
        self.assertIn("not found", self.run_cli("task", "watch", "DEV-404", ok=False))

    def test_sprints_releases_and_membership(self):
        self.assertIn("SPR-1", self.run_cli("sprint", "list", "-p", "DEV"))
        self.assertIn("REL-1", self.run_cli("release", "list", "-p", "DEV"))
        self.assertIn("DEV-1", self.run_cli("sprint", "get", "SPR-1"))
        for group, code, field in [("sprint", "SPR-1", "lists"), ("release", "REL-1", "fix_versions")]:
            for _ in range(2):
                self.assertIn("DEV-1", self.run_cli(group, "add", code, "DEV-1"))
            self.assertIn("not found", self.run_cli(group, "add", code, "DEV-404", ok=False))
        self.assertIn("not a sprint", self.run_cli("sprint", "get", "REL-1", ok=False))
        self.run_cli("sprint", "list", "-s", "bad", ok=False)

    def test_read_history_time_dev_notifications(self):
        self.assertIn("In Review → Done", self.run_cli("task", "history", "DEV-1"))
        self.assertIn("fact", self.run_cli("task", "time", "DEV-1"))
        self.assertIn("visible", self.run_cli("task", "time", "DEV-1"))
        self.assertIn("f540fec", self.run_cli("task", "dev", "DEV-1"))
        self.assertIn("GRP-1", self.run_cli("repo", "list"))
        self.assertIn("assigned", self.run_cli("notify", "list"))
        self.assertIn(["person_id", "==", "CmfPerson:me"], self.requests("CmfNotify.list")[-1]["kwargs"]["filter"])
        self.assertIn("shown 0 of 0", self.run_cli("task", "history", "DEV-2"))

    def test_links_types_and_noops(self):
        self.assertIn("system.link", self.run_cli("relation", "types"))
        for _ in range(2):
            self.assertIn("linked", self.run_cli("task", "link", "DEV-1", "DEV-2"))
        self.assertIn("system.link", self.run_cli("task", "links", "DEV-1"))
        for _ in range(2):
            self.assertIn("unlinked", self.run_cli("task", "unlink", "DEV-1", "DEV-2"))
        self.assertIn("unknown relation", self.run_cli("task", "link", "DEV-1", "DEV-2", "--type", "bogus", ok=False))
        self.assertIn("not found", self.run_cli("task", "link", "DEV-1", "DEV-404", ok=False))

    def test_checklists_and_template(self):
        self.assertIn("CHLI-1", self.run_cli("task", "checklist", "DEV-1"))
        for _ in range(2):
            self.assertIn("DONE", self.run_cli("task", "check", "CHLI-1"))
        self.assertIn("OPEN", self.run_cli("task", "check", "CHLI-1", "--undo"))
        self.assertIn("not found", self.run_cli("task", "check", "CHLI-404", ok=False))
        self.assertIn("created DEV-3", self.run_cli("task", "create", "--template", "DEV-1", "-p", "DEV", "-t", "Override", "--priority", "high"))
        self.assertEqual(self.requests("CmfTask.create_task_from_template")[-1]["kwargs"]["params"]["parent"], "DEV")
        self.assertEqual(self.requests("CmfTask.update")[-1]["kwargs"]["name"], "Override")

    def test_search_bounded_text_and_fenced(self):
        out = self.run_cli("search", "previous instructions", "-t", "task", "-n", "1")
        self.assertIn("DEV-1", out)
        self.assertIn("<untrusted", out)
        self.assertIn("slice", self.requests("CmfTask.list")[-1]["kwargs"])
        self.assertIn("shown 0 of 0", self.run_cli("search", "not-present-anywhere", "-t", "doc"))
        self.run_cli("search", "x", "-t", "unknown", ok=False)
        self.run_cli("search", "x", "-n", "0", ok=False)

    def test_wiki_children_history_and_versions(self):
        self.assertIn("DOC-10", self.run_cli("doc", "children", "DOC-1"))
        self.assertIn("document-only", self.run_cli("doc", "children", "DOC-1"))
        self.assertIn("20261106000000000", self.run_cli("doc", "history", "DOC-1"))
        self.assertIn("Old revision", self.run_cli("doc", "get", "DOC-1", "--version", "20261106000000000"))
        self.assertIn("not found", self.run_cli("doc", "get", "DOC-1", "--version", "3", ok=False))
        self.assertIn("shown 0 of 0", self.run_cli("doc", "children", "DOC-10"))
        self.run_cli("doc", "children", "DOC-1", "--depth", "0", ok=False)

    def test_project_testcases_and_sla(self):
        self.assertIn("direct role assignments", self.run_cli("project", "get", "DEV"))
        self.assertIn("Developer", self.run_cli("project", "get", "DEV"))
        self.assertIn("DEV-TC-1", self.run_cli("testcase", "list", "-p", "DEV"))
        self.assertIn("Expected result", self.run_cli("testcase", "get", "DEV-TC-1"))
        self.assertIn("DEV-TP-1", self.run_cli("testplan", "list", "-p", "DEV"))
        self.assertIn("DEV-TC-1", self.run_cli("testplan", "get", "DEV-TP-1"))
        self.assertIn("remaining_time", self.run_cli("ticket", "get", "DEV-1"))
        self.assertIn("queue membership", self.run_cli("ticket", "get", "DEV-1"))
        ticket = json.loads(self.run_cli("ticket", "get", "DEV-1", "--json"))
        self.assertTrue(ticket["queues_page"][0]["matches"])
        self.assertFalse(ticket["queues_page"][1]["matches"])
        self.assertIsNone(ticket["queues_page"][2]["matches"])
        self.assertIn("JSON BQL", ticket["queues_page"][2]["unavailable"])
        self.run_cli("testcase", "get", "DEV-TC-404", ok=False)

    def test_write_previews_never_mutate(self):
        path = Path(self.tmp.name) / "preview.txt"
        path.write_text("preview")
        cases = [
            ("task", "create", "-p", "DEV", "-t", "Preview"),
            ("task", "update", "DEV-1", "-t", "Preview"),
            ("task", "move", "DEV-1", "closed", "--set", '{"cf_kind":"dev"}'),
            ("task", "log", "DEV-1", "30m"),
            ("task", "attach", "DEV-1", str(path)),
            ("task", "comment", "DEV-1", "Preview"),
        ]
        for case in cases:
            before = len(self.log.read_text().splitlines())
            self.assertIn("would send:", self.run_cli(*case, "--dry-run"))
            calls = list(map(json.loads, self.log.read_text().splitlines()[before:]))
            self.assertTrue(all(r["method"].rsplit(".", 1)[-1] in {"get", "list", "count", "get_meta", "get_current_user"} for r in calls), calls)

    def test_trash_restore_and_safe_bulk(self):
        self.assertIn("DEV-9", self.run_cli("trash", "list"))
        self.assertIn("needs confirmation", self.run_cli("trash", "restore", "DEV-9", ok=False))
        self.assertIn("restored", self.run_cli("trash", "restore", "DEV-9", "--yes"))
        self.assertIn("already", self.run_cli("trash", "restore", "DEV-9", "--yes"))
        selector = '["project.code","==","DEV"]'
        before = len(self.requests("CmfTask.update"))
        self.assertIn("dry run", self.run_cli("task", "bulk", "set", "--filter", selector, "--set", '{"name":"Batch"}'))
        self.assertEqual(len(self.requests("CmfTask.update")), before)
        self.assertIn("succeeded", self.run_cli("task", "bulk", "set", "--filter", selector, "--set", '{"name":"Batch"}', "--yes"))
        self.assertIn("resolved 0", self.run_cli("task", "bulk", "set", "--filter", '["code","==","DEV-404"]', "--set", '{"name":"Empty"}', "--yes"))
        self.run_cli("task", "bulk", "set", "--set", '{"name":"Unsafe"}', "--yes", ok=False)

    def test_json_projection_columns_and_comment_windows(self):
        row = json.loads(self.run_cli("task", "get", "DEV-1", "--fields", "code,responsible.login", "--json"))
        self.assertEqual(set(row), {"code", "responsible"})
        self.assertEqual(set(row["responsible"]), {"login"})
        text = self.run_cli("task", "list", "--cols", "code,responsible.login", "--format", "tsv")
        self.assertIn("DEV-1\tilya@example.ru", text)
        self.assertNotIn("shown", text)
        projected = json.loads(self.run_cli("task", "list", "--cols", "code", "--json"))
        self.assertTrue(all(set(r) == {"code"} for r in projected))
        self.run_cli("task", "list", "--format", "xml", ok=False)
        page = self.run_cli("task", "comments", "DEV-1", "-n", "1")
        self.assertIn("earlier: --page 2", page)
        self.assertIn("shown 1 of", page)
        all_rows = json.loads(self.run_cli("task", "comments", "DEV-1", "--all", "--json"))
        self.assertGreater(len(all_rows), 1)
        self.assertEqual(len(json.loads(self.run_cli("task", "comments", "DEV-1", "-n", "1", "--json"))), 1)
        self.assertIn("attachments", self.run_cli("task", "get", "DEV-1", "--with", "comments,attachments,links"))
        self.run_cli("task", "get", "DEV-1", "--with", "wrong", ok=False)

    def test_components_saved_filters_and_subscriptions(self):
        self.assertIn("PCOM-1", self.run_cli("component", "list", "-p", "DEV"))
        self.run_cli("task", "list", "--component", "Platform")
        self.assertIn(["components.name", "==", "Platform"], self.requests("CmfTask.list")[-1]["kwargs"]["filter"])
        self.assertIn("RFBF-1", self.run_cli("filter", "list"))
        self.assertIn("DEV-1", self.run_cli("task", "list", "--filter", "RFBF-1"))
        self.assertIn(["code", "==", "DEV-1"], self.requests("CmfTask.list")[-1]["kwargs"]["filter"])
        self.assertIn("not found", self.run_cli("task", "list", "--filter", "RFBF-404", ok=False))
        self.assertIn("explicit followers", self.run_cli("doc", "followers", "DOC-1"))
        self.assertIn("explicit followers", self.run_cli("doc", "get", "DOC-1"))

    def test_time_report_grouped_visible_minutes(self):
        out = self.run_cli("time", "report", "--from", "2026-11-02", "--to", "2026-11-03")
        self.assertIn("16h00 actual", out)
        self.assertIn("visible", out)
        report = json.loads(self.run_cli("time", "report", "--from", "2026-11-02", "--to", "2026-11-03", "--json"))
        self.assertEqual(report["actual_minutes"], 960)
        self.assertEqual(len(report["groups"]), 3)
        self.run_cli("time", "report", "--from", "2026-11-04", "--to", "2026-11-03", ok=False)

    def test_write_readback_and_partial_bulk_failure(self):
        mock_server.DROP_UPDATES = True
        try:
            self.assertIn("not confirmed", self.run_cli("task", "update", "DEV-1", "-t", "Ignored", ok=False))
        finally:
            mock_server.DROP_UPDATES = False
        out = self.run_cli("task", "bulk", "set", "--filter", '["code","IN",["DEV-1","DEV-2"]]', "--set", '{"cf_fail":true}', "--yes", ok=False)
        self.assertIn("failed DEV-2", out)
        self.assertIn("successful changes were kept", out)
        self.assertIn("1 changes succeeded, 1 failed", out)
        self.run_cli("task", "update", "DEV-1", "--story-points", "1e9999", ok=False)

    def test_complete_selection_pages_and_bulk_cap(self):
        for i in range(201):
            mock_server.WORKLOG.append({"id": f"CmfTimeTrackerHistory:page{i}", "cmf_author_id": "CmfPerson:me", "start_date": "2031-01-01T09:00:00+00:00", "time_spent": 1, "history_type": "fact", "project": {"code": "PAGE"}})
        report = json.loads(self.run_cli("time", "report", "--from", "2031-01-01", "--to", "2031-01-01", "--json"))
        self.assertEqual(report["actual_minutes"], 201)
        slices = [r["kwargs"]["slice"] for r in self.requests("CmfTimeTrackerHistory.list")]
        self.assertEqual(slices, [[0, 200], [200, 201]])
        for i in range(1001):
            mock_server.TASKS.append({"id": f"CmfTask:cap{i}", "code": f"CAP-{i}", "name": "Cap", "system": False, "project": {"code": "CAP"}})
        out = self.run_cli("task", "bulk", "set", "--filter", '["project.code","==","CAP"]', "--set", '{"name":"Unsafe"}', "--yes", ok=False)
        self.assertIn("safety cap", out)
        self.assertFalse(self.requests("CmfTask.update"))

    def test_comment_upload_failure_and_duplicate_batch_names(self):
        big = Path(self.tmp.name) / "big.bin"
        big.write_bytes(b"x")
        out = self.run_cli("task", "comment", "DEV-1", "Keep comment", "--attach", str(big), ok=False)
        self.assertIn("is kept", out)
        self.assertIn("big.bin", out)
        self.assertIn("Keep comment", self.run_cli("task", "comments", "DEV-1"))
        duplicate = Path(self.tmp.name) / "twice.txt"
        duplicate.write_text("one")
        before = len(self.requests("CmfAttachment.create"))
        self.assertIn("same name", self.run_cli("task", "attach", "DEV-1", str(duplicate), str(duplicate), ok=False))
        self.assertEqual(len(self.requests("CmfAttachment.create")), before)

    def test_move_already_target_is_a_noop(self):
        task = next(t for t in mock_server.TASKS if t["code"] == "DEV-1")
        task["status"] = {"name": "Done", "code": "closed"}
        task["status_id"] = "CmfStatus:3"
        for flags in [(), ("--dry-run",)]:
            self.assertIn("already", self.run_cli("task", "move", "DEV-1", "closed", *flags))
        self.assertFalse(self.requests("CmfTask.task_transition_run"))
        self.assertIn("0 steps", self.run_cli("task", "path", "DEV-1", "closed"))
        self.assertIn("would not apply", self.run_cli("task", "move", "DEV-1", "closed", "--resolution", "done", ok=False))


if __name__ == "__main__":
    unittest.main(verbosity=2)
