"""Wiki writes. Drafts stay drafts unless publishing is explicitly requested."""
from eva.args import Args
from eva.subscriptions import doc_followers
from eva.client import Client, Reply
from eva.common import (
    body_html,
    get_by_code,
    quote_str,
    split_csv,
    text_from,
    simple_list,
    like_filter,
    print_json,
    want_json,
)
from eva.json import JsonDoc
from eva.render import Out


def document_by_id(client: Client, id: String) raises -> Reply:
    return client.call(
        "CmfDocument.get",
        '{"filter":["id","==",'
        + quote_str(id)
        + '],"fields":["id","code","name","text","text_draft"]}',
    )


def doc_write(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        [
            "title",
            "t",
            "description",
            "d",
            "file",
            "F",
            "parent",
            "md",
            "html",
            "publish",
            "verbose",
            "v",
        ]
    )
    var create = args.pos(1) == "create"
    var code: String
    var id = String()
    var title = args.get("title", "t")
    var text = text_from(args, args.get("description", "d"), "the document")
    var d = JsonDoc()
    var kw = d.object()
    if create:
        if title == "" or args.get("parent") == "":
            raise Error("doc create requires -t TITLE and --parent CODE")
        d.set_str(kw, "tree_parent", args.get("parent"))
    else:
        if args.has("parent"):
            raise Error("--parent is only supported by doc create")
        code = args.need(2, "document code")
        var before = get_by_code(
            client, "CmfDocument", code, split_csv("id,code")
        )
        id = before.doc.text_at(before.result, "id")
    if title != "":
        d.set_str(kw, "name", title)
    if text != "":
        d.set_str(kw, "text_draft", body_html(args, text))
    if d.len(kw) == 0:
        raise Error(
            "nothing to change: pass -t, -d or -F; use doc publish to publish a"
            " draft"
        )
    if create:
        var r = client.call("CmfDocument.create", d.dump(kw))
        id = r.doc.text(r.result)
    else:
        _ = client.call(
            "CmfDocument.update", d.dump(kw), "[" + quote_str(id) + "]"
        )
    var got = document_by_id(client, id)
    code = got.doc.text_at(got.result, "code")
    if code == "":
        raise Error(
            "document write returned "
            + id
            + ", but readback did not return its code"
        )
    for i in range(d.len(kw)):
        var key = d.key_at(kw, i)
        if key != "tree_parent" and got.doc.text_at(got.result, key) != d.text(
            d.at(kw, i)
        ):
            raise Error(
                code + " was written, but readback did not confirm " + key
            )
    print(
        ("created " if create else "updated ")
        + ui.bold(code)
        + " (draft; doc publish "
        + code
        + " makes it public)"
    )
    if args.has("publish"):
        do_publish(client, code, id)


def do_publish(client: Client, code: String, id: String) raises:
    var before = document_by_id(client, id)
    var draft = before.doc.text_at(before.result, "text_draft")
    # An empty draft would publish a blank page over the current text.
    if draft == "":
        raise Error(code + " has no draft to publish")
    if draft == before.doc.text_at(before.result, "text"):
        print(code + ": the draft is already the published text")
        return
    _ = client.call("CmfDocument.do_publish", "", "[" + quote_str(id) + "]")
    var after = document_by_id(client, id)
    if after.doc.text_at(after.result, "text") != draft:
        raise Error(
            code
            + ": publish returned, but published text does not match the draft"
        )
    print("published " + code)


def doc_publish(client: Client, args: Args, ui: Out) raises:
    args.check_known(["verbose", "v"])
    var code = args.need(2, "document code")
    var r = get_by_code(client, "CmfDocument", code, split_csv("id,code"))
    do_publish(client, code, r.doc.text_at(r.result, "id"))


def doc_list(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        ["query", "q", "limit", "n", "page", "json", "format", "verbose", "v"]
    )
    var f = like_filter("name", args.get("query", "q"), "")
    simple_list(
        client,
        args,
        ui,
        "CmfDocument",
        [String("code"), String("name")],
        f,
        "code",
        [String("name")],
    )


def doc_get(client: Client, args: Args, ui: Out) raises:
    args.check_known(["json", "format", "full", "verbose", "v"])
    var code = args.need(2, "document code, e.g. DOC-000123")
    var r = get_by_code(
        client,
        "CmfDocument",
        code,
        [
            String("code"),
            String("name"),
            String("text"),
            String("cmf_owner.login"),
        ],
    )
    if want_json(args):
        print_json(r)
        return
    print(
        ui.bold(r.doc.text_at(r.result, "code"))
        + "  "
        + String(r.doc.text_at(r.result, "name").strip())
    )
    print(ui.dim("owner: " + r.doc.text_at(r.result, "cmf_owner.login")))
    ui.untrusted(code + "/text", r.doc.text_at(r.result, "text"))
    var followers = Args([String("doc"), String("followers"), code])
    try:
        doc_followers(client, followers, ui)
    except e:
        print("explicit followers unavailable: " + String(e))


# ---- escape hatch ----
