"""Explicit document followers, distinct from implicit recipients and viewers.

Subscription mutation is deliberately not inferred from task spectators:
its write contract has not been verified on the supported server.
"""
from eva.args import Args
from eva.client import Client
from eva.common import id_of, split_csv, simple_list
from eva.resources import filter_eq
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
