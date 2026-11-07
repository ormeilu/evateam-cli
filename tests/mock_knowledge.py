"""Synthetic schema-shaped fixtures for wiki/project/EvaTest/SLA reads."""

def tables(documents):
    return {
        "CmfDocument": documents + [{"id": "CmfDocument:10", "code": "DOC-10", "name": "Child", "tree_parent_id": "CmfDocument:1"}],
        "CmfDocumentHistory": [{"id": "CmfDocumentHistory:1", "code": "DCH-1", "parent_id": "CmfDocument:1", "doc_version": "20261106000000000", "text": "<p>Old revision</p>", "cmf_created_at": "2026-11-06"}],
        "CmfProject": [{"id": "CmfProject:42", "code": "DEV", "name": "Development", "cache_status_type": "OPEN", "cmf_owner": {"login": "me@example.ru"}}],
        "CmfProjectRoleAssign": [{"id": "CmfProjectRoleAssign:1", "parent": {"code": "DEV"}, "project_role": {"name": "Developer"}, "members": [{"id": "CmfPerson:me", "class_name": "CmfPerson", "login": "me@example.ru", "name": "Me"}, {"id": "CmfPersonGroup:1", "class_name": "CmfPersonGroup", "name": "Team"}]}],
        "CmfTestcase": [{"id": "CmfTestcase:1", "code": "DEV-TC-1", "name": "Retry", "project": {"code": "DEV"}, "cmf_ver_number": 1}],
        "CmfTestcaseStep": [{"id": "CmfTestcaseStep:1", "parent_id": "CmfTestcase:1", "step_number": 1, "step_section": "main", "text": "<p>Send request</p>", "expected_result": "<p>Retry happens</p>"}],
        "CmfTestplan": [{"id": "CmfTestplan:1", "code": "DEV-TP-1", "name": "Regression", "project": {"code": "DEV"}}],
        "CmfTestplanTestcase": [{"id": "CmfTestplanTestcase:1", "parent_id": "CmfTestplan:1", "testcase": {"code": "DEV-TC-1", "name": "Retry"}}],
        "CmfTaskQueue": [
            {"id": "CmfTaskQueue:1", "code": "QUE-1", "name": "My queue", "project_id": "CmfProject:42", "bql_filter": {"bql": '["code","==","DEV-1"]'}},
            {"id": "CmfTaskQueue:2", "code": "QUE-2", "name": "Other queue", "project_id": "CmfProject:42", "bql_filter": {"bql": '["code","==","DEV-2"]'}},
            {"id": "CmfTaskQueue:3", "code": "QUE-3", "name": "Legacy queue", "project_id": "CmfProject:42", "task_filter": {"bql": "not evaluated as Python"}},
        ],
        "CmfSDeskSlaCycle": [{"id": "CmfSDeskSlaCycle:1", "parent_id": "CmfTask:1", "current": True, "elapsed_time": 10, "remaining_time": 100, "paused": False, "breached": False}],
    }
