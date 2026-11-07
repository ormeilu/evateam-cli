"""Loopback-only JSON-RPC fixture for diagnostics; never imports real config."""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread
from typing import cast


class DiagnosticsServer(ThreadingHTTPServer):
    def __init__(self):
        super().__init__(("127.0.0.1", 0), Handler)
        self.calls = []
        self.fail = set()
        self.project_count = 2
        self.task_count = 2
        self.hidden_tasks = False
        self.errors = {}
        self.metadata = {
            "fields": {
                "id": {"widget": "CmfStr", "nullable": False, "api_allow": True},
                "name": {"widget": "CmfStr", "caption": "Task title", "nullable": False},
                "project": {"widget": "CmfGenericRelation", "models": ["CmfProject"], "nullable": True},
            },
            "private_body": "NEVER-CACHE-METADATA-BODY",
            "token": "NEVER-CACHE-METADATA-TOKEN",
        }
        self.thread = Thread(target=self.serve_forever, daemon=True)
        self.thread.start()

    @property
    def url(self):
        return "http://127.0.0.1:" + str(self.server_address[1])

    def close(self):
        self.shutdown()
        self.server_close()
        self.thread.join()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_POST(self):
        server = cast(DiagnosticsServer, self.server)
        call = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        server.calls.append(call)
        method = call["method"]
        kw = call.get("kwargs", {})
        error = None
        result = None
        if method in server.errors:
            error = server.errors[method]
        elif method in server.fail:
            error = {"message": "permission denied", "code": 403}
        elif method.endswith(".get_meta"):
            result = server.metadata
        elif method == "CmfPerson.get_current_user":
            result = {"id": "person-1", "login": "alex@example.invalid", "name": "Alex Example"}
        elif method == "CmfProject.list":
            result = [{"id": f"project-{i}", "code": f"DEMO-{i}", "name": f"Example project {i}"} for i in range(min(server.project_count, kw.get("slice", [0, 11])[1]))]
        elif method == "CmfTask.list":
            from datetime import datetime
            result = [{"id": f"task-{i}", "project_id": "project-0", "code": f"DEMO-{i}", "cmf_modified_at": datetime.now().strftime("%Y-%m-%d 12:00:00")} for i in range(min(server.task_count, kw.get("slice", [0, 201])[1]))]
            if server.hidden_tasks and result:
                result[0] = {"id": "hidden-task"}
        elif method == "CmfTask.count":
            result = 7
        else:
            error = {"message": "Method not found", "code": -32601}
        body = json.dumps({"jsonrpc": "2.2", **({"error": error} if error else {"result": result})}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
