"""One text card composed from the existing, independently useful readers."""
from eva.args import Args
from eva.client import Client
from eva.common import split_csv
from eva.task import task_get, task_links
from eva.collaboration import task_comments
from eva.attachments import task_attachments
from eva.workflow import task_statuses
from eva.render import Out


def task_card(client: Client, args: Args, ui: Out) raises:
    if args.has("json") or args.has("fields") or args.get("format") != "":
        raise Error(
            "--with is a text card; use the individual readers for JSON or"
            " field projection"
        )
    var code = args.need(2, "task code")
    var sections = split_csv(args.get("with"))
    if args.get("with") == "all":
        sections = ["comments", "attachments", "links", "statuses"]
    if len(sections) == 0:
        raise Error("--with needs comments,attachments,links,statuses or all")
    for section in sections:
        if (
            section != "comments"
            and section != "attachments"
            and section != "links"
            and section != "statuses"
        ):
            raise Error("unknown --with section " + section)
    var raw: List[String] = ["task", "get", code]
    for i in range(len(args.keys)):
        if args.keys[i] != "with":
            raw.append("--" + args.keys[i] + "=" + args.values[i])
    var base = Args(raw)
    task_get(client, base, ui)
    var seen = List[String]()
    for section in sections:
        var duplicate = False
        for s in seen:
            if s == section:
                duplicate = True
        if duplicate:
            continue
        seen.append(section)
        print("\n" + section + ":")
        var one = Args([String("task"), section, code])
        if section == "comments":
            task_comments(client, one, ui)
        elif section == "attachments":
            task_attachments(client, one, ui)
        elif section == "links":
            task_links(client, one, ui)
        else:
            task_statuses(client, one, ui)
