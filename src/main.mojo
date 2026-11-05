"""The `eva` command: EvaTeam from the command line."""

from std.sys import argv, exit, stderr

from eva.args import Args
from eva.client import Client, load_config
from eva.commands import (
    task_get,
    task_list,
    task_create,
    task_update,
    task_comment,
    task_comments,
    task_log,
    task_links,
    task_move,
    task_statuses,
    project_list,
    person_list,
    doc_get,
    doc_list,
    raw_call,
)
from eva.render import Out
from eva.upgrade import upgrade
from eva.auth import auth_login, auth_logout, auth_status, auth_use

comptime VERSION = "0.3.0"  # x-release-please-version

comptime USAGE = """eva — EvaTeam from the command line

usage: eva <command> [options]

tasks
  task get CODE [--fields a,b]          one task: status, people, description
  task list [-p PROJ] [-a LOGIN] [-s open|closed|in_progress|in_review|all|STATUS]
            [-q TEXT] [--filter BQL] [--order -field] [-n 25] [--page 1]
  task create -p PROJ -t TITLE [-d TEXT] [-a LOGIN] [--sprint SPR-1]
  task update CODE [-t TITLE] [-d TEXT] [-s STATUS] [-a LOGIN] [--set JSON]
  task move CODE STATUS [-m COMMENT] [--set JSON]
                                        change status through the workflow
  task statuses CODE                    where the task can move from here
  task comment CODE TEXT                add a comment
  task comments CODE                    read the comments
  task log CODE 1h30m [-m TEXT]         log time spent
  task links CODE                       incoming and outgoing links

other
  project list [-q TEXT]                projects
  person list [-q TEXT]                 people (login, name, email)
  doc list [-q TEXT] | doc get CODE     wiki documents
  call METHOD [--kwargs JSON] [--args JSON] [--flags JSON]
                                        any API method, raw JSON reply
  auth login [--profile NAME] [--url URL]
                                        sign in; the address and token go to the
                                        OS keychain (the token is read hidden or
                                        from stdin, never as an argument)
  auth status | auth use NAME | auth logout [--profile NAME]
  config                                where the URL and token come from
  upgrade                               update eva the way it was installed

options everywhere
  --profile NAME    use that saved profile (or EVA_PROFILE)
  --json            the API's own JSON instead of text
  --full            no truncation through a pipe
  -v, --verbose     show the request and the reply on stderr

configuration, first match wins: --profile/EVA_PROFILE; EVA_URL and
EVA_API_KEY in the environment; ./.env; the default profile from `auth login`;
~/.config/eva-cli/env. Each place must hold both the address and the token. EVA_CA_BUNDLE points at a PEM file for a server signed
by a corporate CA; EVA_INSECURE=1 skips TLS verification altogether.
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
            raise Error("unknown auth command '" + sub_cmd + "': login, status, use or logout")
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
            task_get(client, args, ui)
        elif sub == "list" or sub == "ls" or sub == "find":
            task_list(client, args, ui)
        elif sub == "create" or sub == "new":
            task_create(client, args, ui)
        elif sub == "update" or sub == "edit":
            task_update(client, args, ui)
        elif sub == "comment":
            task_comment(client, args, ui)
        elif sub == "comments":
            task_comments(client, args, ui)
        elif sub == "log":
            task_log(client, args, ui)
        elif sub == "links":
            task_links(client, args, ui)
        elif sub == "move":
            task_move(client, args, ui)
        elif sub == "statuses":
            task_statuses(client, args, ui)
        else:
            raise Error("unknown task command '" + sub + "', see eva --help")
    elif group == "project" or group == "projects":
        project_list(client, args, ui)
    elif group == "person" or group == "people" or group == "user":
        person_list(client, args, ui)
    elif group == "doc" or group == "docs":
        if sub == "get" or sub == "show":
            doc_get(client, args, ui)
        else:
            doc_list(client, args, ui)
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
        exit(1)
