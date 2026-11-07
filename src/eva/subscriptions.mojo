"""Explicit document followers, distinct from implicit recipients and viewers.

A CmfFollower record ties one person to a document; on the server each one is
made by the person who follows, so eva only subscribes or unsubscribes you.
Task watchers are a different mechanism (spectators).
"""
from eva.args import Args
from eva.client import Client, Reply
from eva.common import id_of, split_csv, simple_list, quote_str
from eva.resources import filter_eq
from eva.selection import collect_rows
from eva.task_options import person_id
from eva.writes import preview_write
from eva.json import JsonDoc
from eva.render import Out


def doc_followers(client: Client, args: Args, ui: Out) raises:
    args.check_known(["limit", "n", "page", "json", "format", "verbose", "v"])
    var code = args.need(2, "document code")
    var id = id_of(client, "CmfDocument", "code", code)
    var filter = (
        "[" + filter_eq("parent_id", id) + ',["cmf_deleted","!=",true]]'
    )
    if not args.has("json") and args.get("format") != "json":
        print(
            "explicit followers visible to this account (not viewers or"
            " implicit notification recipients):"
        )
    simple_list(
        client,
        args,
        ui,
        "CmfFollower",
        split_csv(
            "code,person.login,person.name,follow_children,notify_volume"
        ),
        filter,
        "code",
        split_csv("person.login,person.name,follow_children,notify_volume"),
    )


def _mine(client: Client, doc_id: String, me: String) raises -> Reply:
    return collect_rows(
        client,
        "CmfFollower",
        "["
        + filter_eq("parent_id", doc_id)
        + ","
        + filter_eq("person_id", me)
        + ',["cmf_deleted","!=",true]]',
        "code,follow_children",
        100,
    )


def doc_watch(client: Client, args: Args, ui: Out) raises:
    """Follow a document as yourself; --children also follows the pages under
    it, --off stops following. Repeating a command is a no-op."""
    args.check_known(["off", "children", "dry-run", "verbose", "v"])
    var code = args.need(2, "document code")
    var doc_id = id_of(client, "CmfDocument", "code", code)
    var me = person_id(client, "me")
    var dry = args.has("dry-run")
    var rows = _mine(client, doc_id, me)
    ref d = rows.doc
    var n = d.len(rows.result)
    if args.has("off"):
        if args.has("children"):
            raise Error("--off stops following entirely; drop --children")
        if n == 0:
            print("you do not follow " + code)
            return
        # The web UI can leave more than one record for the same person.
        for i in range(n):
            var id = d.text_at(d.at(rows.result, i), "id")
            if preview_write(
                dry, "CmfFollower.delete", "", "[" + quote_str(id) + "]"
            ):
                continue
            _ = client.call("CmfFollower.delete", "", "[" + quote_str(id) + "]")
        if dry:
            return
        var left = _mine(client, doc_id, me)
        if left.doc.len(left.result) != 0:
            raise Error(code + ": unfollow returned, but you still follow it")
        print("stopped following " + ui.bold(code))
        return
    var children = args.has("children")
    var what = code + (" and the pages under it" if children else "")
    for i in range(n):
        var row = d.at(rows.result, i)
        if (d.text_at(row, "follow_children") == "true") == children:
            print("already following " + what)
            return
    var kw = JsonDoc()
    var fields = kw.object()
    var flag = kw.boolean(children)
    kw.set(fields, "follow_children", flag)
    if n > 0:
        var id = d.text_at(d.at(rows.result, 0), "id")
        if preview_write(
            dry,
            "CmfFollower.update",
            kw.dump(fields),
            "[" + quote_str(id) + "]",
        ):
            return
        _ = client.call(
            "CmfFollower.update", kw.dump(fields), "[" + quote_str(id) + "]"
        )
    else:
        kw.set_str(fields, "parent", doc_id)
        kw.set_str(fields, "person", me)
        if preview_write(dry, "CmfFollower.create", kw.dump(fields)):
            return
        _ = client.call("CmfFollower.create", kw.dump(fields))
    var after = _mine(client, doc_id, me)
    var confirmed = False
    for i in range(after.doc.len(after.result)):
        if (
            after.doc.text_at(after.doc.at(after.result, i), "follow_children")
            == "true"
        ) == children:
            confirmed = True
    if not confirmed:
        raise Error(code + ": follow returned, but readback did not confirm it")
    print("following " + ui.bold(what))
