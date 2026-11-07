"""The `eva` command: EvaTeam from the command line."""

from std.sys import argv, exit, stderr

from eva.args import Args
from eva.client import Client, load_config
from eva.task import (
    task_get,
    task_list,
    task_create,
    task_update,
    task_delete,
    task_links,
)
from eva.workflow import task_move, task_statuses, task_path, resolution_list
from eva.resources import project_list, person_list
from eva.documents import doc_get, doc_list
from eva.collaboration import task_comments, task_comment_delete
from eva.commands import raw_call
from eva.common import simple_list, like_filter
from eva.resources import filter_eq
from eva.render import Out
from eva.upgrade import upgrade
from eva.fields import field_get, field_list
from eva.timelog import task_log, time_delete, time_list
from eva.attachments import (
    attachment_download,
    attachment_get,
    doc_download_all,
    task_attach,
    task_attachments,
)
from eva.auth import auth_login, auth_logout, auth_status, auth_use
from eva.diagnostics import (
    schema,
    schema_classes,
    context,
    cheatsheet,
    error_hint,
)
from eva.documents import doc_write, doc_publish
from eva.resources import (
    list_command,
    task_history,
    task_time,
    task_dev,
    notify_list,
    repo_list,
    search,
)
from eva.subscriptions import doc_followers, doc_watch
from eva.task_card import task_card
from eva.reports import time_report
from eva.filters import filter_list
from eva.operations import trash_command, task_bulk
from eva.knowledge import (
    doc_children,
    doc_history,
    doc_version,
    project_get,
    test_command,
    ticket_get,
)
from eva.task_relations import (
    task_link,
    relation_types,
    task_checklist,
    task_check,
    task_template,
)
from eva.collaboration import comment_write, comment_edit, task_watch
from eva.attachments import attachment_delete

comptime VERSION = "0.9.0"  # x-release-please-version

comptime USAGE = """eva — EvaTeam from the command line

usage: eva <command> [options]

  task get CODE [--fields a,b] [--with comments,attachments,links|all]
      task card; priority, planning, participants, tags, lists and checklist counts
  task list [-p PROJ] [-a LOGIN|me] [-s STATUS] [-q TEXT]
      name search; --author, --watching, --waiting-for LOGIN|me, --archived
  task create -p PROJ -t TITLE [-d TEXT|-F FILE] [--template CODE]
      create; --parent CODE, --type TYPE, --sprint CODE, --set JSON
  task update CODE [-t TITLE] [-d TEXT|-F FILE] [-a LOGIN|me] [--set JSON]
      replace requested fields; -s STATUS moves after the field update
  task delete CODE [--yes]
      confirm first; --yes is required without a terminal
  task move CODE STATUS [--path] [--resolution CODE] [--set JSON] [-m TEXT]
      run workflow transitions, stopping on a refusal
  task statuses CODE
      where this task can move from here
  task path CODE STATUS
      show a workflow route without moving
  task comment CODE TEXT|-F FILE [--reply-to ID] [--attach FILE...]
      plain text, --md or --html; uploads belong to the new comment
  task comments CODE [--human] [--ids] [-n 20] [--page 1] [--all]
      newest window, chronological inside it; page 2 is earlier
  task comment-edit ID TEXT|-F FILE [--md|--html]
      edit a comment; the server controls its edited marker
  task comment-delete ID
      hide a comment; the server keeps a deleted-comment entry
  task log CODE 1h30m [-m TEXT] [--date D] [--at HH:MM]
      log time ending now or on a selected day
  task history CODE [-n 25] [--page 1]
      status transitions, newest first
  task time CODE [--all] [-n 25] [--page 1]
      visible actual work log; --all includes planned/draft entries
  task dev CODE
      linked repositories, branches, commits and merge requests
  task links CODE
      incoming/outgoing links and their relation types
  task link CODE OTHER [--type relates|CODE|NAME]
      create a typed link; duplicate calls are no-ops
  task unlink CODE OTHER [--type relates|CODE|NAME]
      remove only matching links of this type; absent links are a no-op
  task checklist CODE [-n 25] [--page 1]
      checklists and paginated items
  task check CHLI-1 [--undo]
      DONE, or OPEN with --undo
  task watch CODE [--login LOGIN]
      watch as yourself by default
  task unwatch CODE [--login LOGIN]
      remove that watcher, idempotently
  task attachments CODE
      list files attached to a task
  task attach CODE FILE [FILE...] [--force]
      upload; refuse existing names unless --force replaces them
  task bulk set --filter BQL --set JSON [--yes] [--dry-run]
      resolve the set first; preview by default, continue after per-task failures
  task bulk move STATUS --filter BQL [--path] [--set JSON] [--yes]
      workflow changes on the resolved set, not an atomic transaction
  time list [--from D] [--to D] [-a LOGIN]
      daily work log against the working calendar; this week by default
  time report --from D --to D [-p PROJ] [-a LOGIN|me]
      visible totals by project and entry start-date; actual/planned/other minutes
  time log CODE 1h30m [--date D] [--at HH:MM]
      alias for task log
  time delete TTH-1
      delete a work-log entry
  attachment get ATT-1
      metadata and extracted text
  attachment download ATT-1 [-o PATH|-] [--force]
      original bytes; no overwrite without --force
  attachment delete ATT-1 [--yes]
      confirm removal; does not claim stored bytes were erased
  project list [-q TEXT]
      project codes and names
  project get CODE
      owner, direct role assignments and project lists, not expanded effective membership
  person list [-q TEXT]
      people: login, name, email
  doc list [-q TEXT]
      wiki documents by name
  doc get CODE [--version OPAQUE_VERSION]
      published text, or an exact historical doc_version; not ordinal revision 3
  doc create -t TITLE --parent CODE [-d TEXT|-F FILE] [--publish]
      create a draft; publish only when explicitly requested
  doc update CODE [-t TITLE] [-d TEXT|-F FILE] [--publish]
      update a draft
  doc publish CODE
      publish the current draft and verify its text
  doc comment CODE TEXT|-F FILE [--reply-to ID] [--attach FILE...]
      same text/reply/file rules as task comments
  doc comment-edit ID TEXT|-F FILE
      edit a document comment
  doc comments CODE [--human] [--ids] [-n 20] [--page 1] [--all]
      same window and fencing as task comments
  doc attachments CODE
      files attached to a document
  doc attach CODE FILE [FILE...] [--force]
      same upload safeguards as task attach
  doc download-all CODE [-o DIR] [--force]
      every attachment into DIR (default CODE/), one download each
  doc children CODE [--depth 1] [-n 25] [--page 1]
      document-only children; paginated per parent, depth capped at 10
  doc history CODE [-n 25] [--page 1]
      opaque version strings and history IDs, newest first
  doc followers CODE [-n 25] [--page 1]
      explicit followers only, not viewers or implicit recipients
  doc watch CODE [--children] [--off] [--dry-run]
      follow a document as yourself; --children adds pages under it
  sprint list [-p PROJ] [-s open|closed|all]
      discover sprint codes
  sprint get CODE [-n 25] [--page 1]
      sprint metadata and its tasks
  sprint add CODE TASK [TASK...]
      append tasks without replacing their other sprints
  release list [-p PROJ] [-s open|closed|all]
      discover release codes
  release get CODE [-n 25] [--page 1]
      release metadata and its tasks
  release add CODE TASK [TASK...]
      append tasks without replacing their other releases
  relation types [-n 25] [--page 1]
      relation codes and names
  tag list [-q TEXT]
      tag names; task update --tag replaces the tag set
  component list [-p PROJ] [-q TEXT]
      project-scoped components; task list --component NAME
  filter list [-q TEXT] [-p PROJ]
      your saved BQL filters; task list --filter CODE|NAME executes stored JSON BQL
  notify list [-n 25] [--page 1] [--all]
      your unread notifications; --all includes read rows
  repo list [-q TEXT]
      repository code, name and URL
  search TEXT [-t task|doc|all] [-p PROJ] [-n 25] [--page 1]
      substring over name OR text; the page limit applies to each type
  testcase list [-p PROJ] [-q TEXT]
      test cases
  testcase get CODE [-n 25] [--page 1]
      version, steps, pre/postcondition sections and expected results
  testplan list [-p PROJ] [-q TEXT]
      test plans
  testplan get CODE [-n 25] [--page 1]
      plan metadata and paginated testcase membership
  ticket get CODE [-n 25] [--page 1]
      native SLA cycles, raw duration units; queue membership is not guessed
  trash list [-p PROJ] [-n 25] [--page 1]
      deleted tasks; displayed timestamp is last-modified, not a retention promise
  trash restore CODE [--yes]
      restore a deleted task after confirmation
  field list [-q TEXT]
      custom task fields
  field get NAME
      values of a custom choice or multi-select
  resolution list
      resolution codes and names
  schema CmfTask [-q TEXT] [--relations] [--refresh]
      filtered cached metadata; schema --classes lists known model names
  context
      read-only orientation: account, visible projects and recent activity
  cheatsheet
      copy-paste recipes without signing in
  call METHOD [--kwargs JSON] [--args JSON] [--flags JSON]
      raw JSON-RPC result; oversized piped replies spill to a private file
  auth login [--profile NAME] [--url URL]
      read the token hidden or on stdin; save only to the OS keychain
  auth status
      account and saved profiles
  auth use NAME
      select the default profile
  auth logout [--profile NAME]
      remove a saved profile
  config
      configuration source; never prints the token
  upgrade
      update through the original installation method

shared task create/update flags
  --priority -2..3|lowest|low|normal|high|critical|blocker (or Russian caption)
  --story-points NUMBER   --plan-start YYYY-MM-DD   --plan-end YYYY-MM-DD
  --alarm "YYYY-MM-DD HH:MM"|off
  --co-assignee LOGIN [--co-assignee LOGIN...]    --waiting-for LOGIN|none
  --tag NAME [--tag NAME...]   (none clears; these multi-select flags replace)

task list projections and selectors
  --tag NAME    --component NAME    --filter BQL|SAVED_CODE|SAVED_NAME
  --cols code,status.name,responsible.login --format tsv
  --fields a,b --json    nested JSON projection; --json alone keeps the reply
  -n/--limit N --page K  bounded pages; TSV has data rows only, no footer

write previews
  --dry-run on task create/update/move/log/attach/comment prints would send:
  with exact resolved payloads; no mutations, no server-side acceptance claim
  bulk requires --yes to apply; --dry-run wins over --yes

options
  --profile NAME    saved profile (or EVA_PROFILE)
  --json            API result (projected when task --fields/--cols is given)
  --full            no text/raw-call truncation through a pipe
  -v, --verbose     requests and replies on stderr

text is plain by default; --md converts Markdown, --html sends HTML unchanged.
configuration precedence: --profile/EVA_PROFILE; environment EVA_URL +
EVA_API_KEY; ./.env; default keychain profile; ~/.config/eva-cli/env.
Each source must contain both URL and token. EVA_CA_BUNDLE selects a PEM CA;
EVA_INSECURE=1 explicitly disables TLS verification.
"""


def run(var raw: List[String]) raises:
    var args = Args(raw)
    if args.has("version") and len(args.positionals) == 0:
        print("eva " + VERSION)
        return
    var group = args.pos(0)
    if group == "" or group == "help" or args.has("help", "h"):
        print(USAGE)
        return
    # Global: which keychain profile to use, for every command but auth's own.
    var profile = args.take("profile") if group != "auth" else String("")
    var ui = Out(args.has("full"))
    var verbose = args.has("verbose", "v")

    if group == "cheatsheet":
        args.check_known(["full", "verbose", "v"])
        cheatsheet()
        return
    if group == "schema" and args.has("classes"):
        args.check_known(
            ["classes", "query", "q", "json", "format", "full", "verbose", "v"]
        )
        if args.pos(1) != "":
            raise Error("schema --classes takes no class argument")
        schema_classes(
            args.get("query", "q"),
            args.has("json") or args.get("format") == "json",
        )
        return
    if group == "upgrade" or group == "self-update":
        var code = upgrade()
        if code != 0:
            exit(code)
        return

    if group == "auth":
        var sub_cmd = args.pos(1)
        if sub_cmd == "login":
            auth_login(args, ui)
        elif sub_cmd == "status":
            auth_status(args, ui)
        elif sub_cmd == "use":
            auth_use(args, ui)
        elif sub_cmd == "logout":
            auth_logout(args, ui)
        else:
            raise Error(
                "unknown auth command '"
                + sub_cmd
                + "': login, status, use or logout"
            )
        return

    if group == "config":
        var cfg = load_config(profile)
        print("url:      " + (cfg.url if cfg.url != "" else "(not set)"))
        print("token:    " + ("set" if cfg.token != "" else "(not set)"))
        print("insecure: " + String(cfg.insecure))
        print("from:     " + cfg.source)
        return

    var client = Client(load_config(profile), verbose)
    var sub = args.pos(1)
    if group == "call":
        raw_call(client, args, ui)
    elif group == "task" or group == "tasks" or group == "t":
        if sub == "get" or sub == "show":
            if args.has("with"):
                task_card(client, args, ui)
            else:
                task_get(client, args, ui)
        elif sub == "list" or sub == "ls" or sub == "find":
            task_list(client, args, ui)
        elif sub == "create" or sub == "new":
            if args.has("template"):
                task_template(client, args, ui)
            else:
                task_create(client, args, ui)
        elif sub == "bulk":
            task_bulk(client, args, ui)
        elif sub == "update" or sub == "edit":
            task_update(client, args, ui)
        elif sub == "delete" or sub == "rm":
            task_delete(client, args, ui)
        elif sub == "comment":
            comment_write(client, args, ui)
        elif sub == "comment-edit":
            comment_edit(client, args, ui)
        elif sub == "comments":
            task_comments(client, args, ui)
        elif sub == "comment-delete" or sub == "uncomment":
            task_comment_delete(client, args, ui)
        elif sub == "history":
            task_history(client, args, ui)
        elif sub == "time":
            task_time(client, args, ui)
        elif sub == "dev":
            task_dev(client, args, ui)
        elif sub == "log":
            task_log(client, args, ui)
        elif sub == "watch" or sub == "unwatch":
            task_watch(client, args, ui)
        elif sub == "link" or sub == "unlink":
            task_link(client, args, ui)
        elif sub == "checklist":
            task_checklist(client, args, ui)
        elif sub == "check":
            task_check(client, args, ui)
        elif sub == "links":
            task_links(client, args, ui)
        elif sub == "move":
            task_move(client, args, ui)
        elif sub == "statuses":
            task_statuses(client, args, ui)
        elif sub == "path":
            task_path(client, args, ui)
        elif sub == "attachments" or sub == "files":
            task_attachments(client, args, ui)
        elif sub == "attach":
            task_attach(client, args, ui)
        else:
            raise Error("unknown task command '" + sub + "', see eva --help")
    elif group == "field" or group == "fields":
        if sub == "get" or sub == "show":
            field_get(client, args, ui)
        else:
            field_list(client, args, ui)
    elif group == "time" or group == "worklog":
        if sub == "list" or sub == "ls" or sub == "":
            time_list(client, args, ui)
        elif sub == "report":
            time_report(client, args, ui)
        elif sub == "delete" or sub == "rm":
            time_delete(client, args, ui)
        elif sub == "log":
            # eva time log CODE 1h30m: the same as eva task log.
            task_log(client, args, ui)
        else:
            raise Error(
                "unknown time command '" + sub + "': list, log or delete"
            )
    elif group == "attachment" or group == "attachments" or group == "file":
        if sub == "get" or sub == "show":
            attachment_get(client, args, ui)
        elif sub == "delete" or sub == "rm":
            attachment_delete(client, args, ui)
        elif sub == "download" or sub == "dl":
            attachment_download(client, args, ui)
        else:
            raise Error(
                "unknown attachment command '" + sub + "': get or download"
            )
    elif group == "schema":
        schema(client, args, ui)
    elif group == "context":
        context(client, args, ui)
    elif group == "trash":
        trash_command(client, args, ui)
    elif group == "search":
        search(client, args, ui)
    elif group == "relation":
        relation_types(client, args, ui)
    elif group == "sprint" or group == "release":
        list_command(client, args, ui)
    elif group == "notify":
        notify_list(client, args, ui)
    elif group == "repo":
        repo_list(client, args, ui)
    elif group == "filter":
        filter_list(client, args, ui)
    elif group == "component":
        args.check_known(
            [
                "project",
                "p",
                "query",
                "q",
                "limit",
                "n",
                "page",
                "json",
                "format",
                "verbose",
                "v",
            ]
        )
        var base = String("")
        if args.get("project", "p") != "":
            base = filter_eq("project.code", args.get("project", "p"))
        simple_list(
            client,
            args,
            ui,
            "CmfComponent",
            [String("code"), String("name"), String("project.code")],
            like_filter("name", args.get("query", "q"), base),
            "code",
            [String("name"), String("project.code")],
        )
    elif group == "tag":
        args.check_known(
            ["query", "q", "limit", "n", "page", "json", "verbose", "v"]
        )
        simple_list(
            client,
            args,
            ui,
            "CmfTag",
            [String("id"), String("name")],
            like_filter("name", args.get("query", "q"), ""),
            "id",
            [String("name")],
        )
    elif group == "resolution" or group == "resolutions":
        resolution_list(client, args, ui)
    elif group == "project" or group == "projects":
        if sub == "get":
            project_get(client, args, ui)
        else:
            project_list(client, args, ui)
    elif group == "testcase" or group == "testplan":
        test_command(client, args, ui)
    elif group == "ticket":
        ticket_get(client, args, ui)
    elif group == "person" or group == "people" or group == "user":
        person_list(client, args, ui)
    elif group == "doc" or group == "docs":
        if sub == "create" or sub == "update":
            doc_write(client, args, ui)
        elif sub == "publish":
            doc_publish(client, args, ui)
        elif sub == "followers":
            doc_followers(client, args, ui)
        elif sub == "watch":
            doc_watch(client, args, ui)
        elif sub == "children":
            doc_children(client, args, ui)
        elif sub == "history":
            doc_history(client, args, ui)
        elif sub == "get" or sub == "show":
            if args.has("version"):
                doc_version(client, args, ui)
            else:
                doc_get(client, args, ui)
        elif sub == "comment":
            comment_write(client, args, ui)
        elif sub == "comment-edit":
            comment_edit(client, args, ui)
        elif sub == "comments":
            task_comments(client, args, ui)
        elif sub == "attach":
            task_attach(client, args, ui)
        elif sub == "attachments":
            task_attachments(client, args, ui)
        elif sub == "download-all":
            doc_download_all(client, args, ui)
        elif sub == "list" or sub == "ls" or sub == "":
            doc_list(client, args, ui)
        else:
            raise Error("unknown doc command " + sub)
    else:
        raise Error("unknown command '" + group + "', see eva --help")


def main():
    var raw = List[String]()
    var all = argv()
    for i in range(1, len(all)):
        raw.append(String(all[i]))
    try:
        run(raw^)
    except e:
        print("eva: " + String(e), file=stderr)
        var hint = error_hint(String(e))
        if hint != "":
            print("hint: " + hint, file=stderr)
        exit(1)
