"""Files attached to tasks: list them, read the text EvaTeam extracted from
one, or download the original bytes."""

from std.ffi import external_call, c_int
from std.os import makedirs
from std.os.path import exists

from eva.args import Args
from eva.selection import collect_rows
from eva.writes import preview_write
from eva.client import Client, Reply
from eva.common import id_of, print_json, quote_str, split_csv, want_json
from eva.json import JsonDoc, J_OBJ, clean
from eva.render import Out, pad
from eva.term import stdin_is_tty, prompt_line

comptime ATTACHMENT_FIELDS = "id,code,file_name,file_type,st_size,embedded,cmf_created_at,cmf_author.name,parent_id,url"


def human_size(n: Int) -> String:
    if n < 1024:
        return String(n) + " B"
    if n < 1024 * 1024:
        return String((n + 512) // 1024) + " KB"
    var tenths = (n * 10 + 512 * 1024) // (1024 * 1024)
    return String(tenths // 10) + "." + String(tenths % 10) + " MB"


def safe_file_name(name: String, fallback: String) -> String:
    """A server-supplied file name reduced to one harmless path component."""
    var base = name
    for sep in ["/", "\\"]:
        var i = base.rfind(String(sep))
        if i >= 0:
            var rest = String(base[byte = i + 1 :])
            base = rest
    var out = String()
    for cp in base.codepoints():
        var c = Int(cp)
        if c < 0x20 or c == 0x7F or (c >= 0x80 and c < 0xA0):
            continue
        out += String(cp)
    var trimmed = String(out.strip())
    while trimmed.startswith("."):
        var rest = String(trimmed[byte=1:])
        trimmed = rest
    return trimmed if trimmed != "" else fallback


def attachment_kwargs(ref_: String, fields: String) raises -> String:
    """Filter one attachment by its ATT code or CmfAttachment id."""
    var d = JsonDoc()
    var kw = d.object()
    var v = d.string(ref_)
    var f = d.triple(
        "id" if ref_.startswith("CmfAttachment:") else "code", "==", v
    )
    d.set(kw, "filter", f)
    var fl = d.str_array(split_csv(fields))
    d.set(kw, "fields", fl)
    return d.dump(kw)


def get_attachment(
    client: Client, ref_: String, fields: String
) raises -> Reply:
    var r = client.call("CmfAttachment.get", attachment_kwargs(ref_, fields))
    if r.doc.is_null(r.result) or r.doc.kind(r.result) != J_OBJ:
        raise Error(ref_ + ": no such attachment, or no access to it")
    return r^


def task_attachments(client: Client, args: Args, ui: Out) raises:
    args.check_known(["json", "format", "verbose", "v"])
    var code = args.need(2, "task code")
    var cls = "CmfDocument" if (
        args.pos(0) == "doc" or args.pos(0) == "docs"
    ) else "CmfTask"
    var task_id = code if code.startswith("CmfComment:") else id_of(
        client, cls, "code", code
    )
    var d = JsonDoc()
    var kw = d.object()
    var v = d.string(task_id)
    var f = d.triple("parent_id", "==", v)
    d.set(kw, "filter", f)
    var fl = d.str_array(split_csv(ATTACHMENT_FIELDS))
    d.set(kw, "fields", fl)
    var order = d.str_array([String("cmf_created_at")])
    d.set(kw, "order_by", order)
    var r = client.call("CmfAttachment.list", d.dump(kw))
    if want_json(args):
        print_json(r)
        return
    var n = r.doc.len(r.result)
    for i in range(n):
        var a = r.doc.at(r.result, i)
        var size = (
            Int(r.doc.text_at(a, "st_size")) if r.doc.text_at(a, "st_size")
            != "" else 0
        )
        var line = (
            ui.accent(pad(r.doc.text_at(a, "code"), 12))
            + " "
            + pad(human_size(size), 8)
        )
        line += (
            " "
            + String(r.doc.text_at(a, "cmf_created_at")[byte=0:10])
            + "  "
            + r.doc.text_at(a, "file_name")
        )
        if r.doc.text_at(a, "embedded") == "true":
            line += ui.dim("  (image in the text)")
        print(line)
    print(
        ui.dim(
            String(n)
            + (" attachment" if n == 1 else " attachments")
            + "; read one: eva attachment get ATT-…"
        )
    )


def attachment_get(client: Client, args: Args, ui: Out) raises:
    args.check_known(["json", "format", "full", "verbose", "v"])
    var ref_ = args.need(2, "attachment code, e.g. eva attachment get ATT-1234")
    var r = get_attachment(client, ref_, ATTACHMENT_FIELDS + ",text")
    if want_json(args):
        print_json(r)
        return
    ref d = r.doc
    var a = r.result
    var size = (
        Int(d.text_at(a, "st_size")) if d.text_at(a, "st_size") != "" else 0
    )
    print(ui.bold(d.text_at(a, "code")) + "  " + d.text_at(a, "file_name"))
    print(
        "type: "
        + d.text_at(a, "file_type")
        + "   size: "
        + human_size(size)
        + "   on: "
        + d.text_at(a, "parent_id")
    )
    print(
        ui.dim(
            "added: "
            + d.text_at(a, "cmf_created_at")
            + " by "
            + d.text_at(a, "cmf_author.name")
        )
    )
    var text = d.text_at(a, "text")
    if String(text.strip()) == "":
        print(
            ui.dim(
                "no extracted text; get the file: eva attachment download "
                + d.text_at(a, "code")
            )
        )
        return
    # Plain text, not HTML: escape it so the fence's HTML reading keeps it as is.
    var esc = String(
        text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    )
    ui.untrusted(d.text_at(a, "code") + "/text", esc.replace("\n", "<br>"))


def _write_stdout(data: List[UInt8]) raises:
    var done = 0
    while done < len(data):
        var n = external_call["write", Int](
            c_int(1), data.unsafe_ptr().unsafe_offset(done), len(data) - done
        )
        if n <= 0:
            raise Error("cannot write to stdout")
        done += n


def _fetch(client: Client, d: JsonDoc, a: Int) raises -> List[UInt8]:
    """The bytes of attachment row `a`, refusing a short read or a refusal."""
    var expected = (
        Int(d.text_at(a, "st_size")) if d.text_at(a, "st_size") != "" else -1
    )
    var data = client.download(d.text_at(a, "url"))
    # A refusal comes back as a short JSON reply with HTTP 200. Files uploaded
    # through the API keep st_size 0, so a size of 0 says nothing.
    var head = String(from_utf8_lossy=Span(data)[0 : min(len(data), 200)])
    if expected > 0 and len(data) != expected:
        raise Error(
            "got "
            + String(len(data))
            + " bytes instead of "
            + String(expected)
            + "; the server said: "
            + clean(head)
        )
    if (
        expected <= 0
        and head.startswith('{"error"')
        and not d.text_at(a, "file_type").lower().endswith("json")
    ):
        raise Error("the server refused the download: " + clean(head))
    return data^


def attachment_download(client: Client, args: Args, ui: Out) raises:
    args.check_known(["output", "o", "force", "verbose", "v"])
    var ref_ = args.need(
        2, "attachment code, e.g. eva attachment download ATT-1234"
    )
    var r = get_attachment(client, ref_, ATTACHMENT_FIELDS)
    ref d = r.doc
    var a = r.result
    var code = d.text_at(a, "code")
    var out = args.get("output", "o")
    if out == "":
        out = safe_file_name(
            d.text_at(a, "file_name"), code + d.text_at(a, "file_type")
        )
    if out != "-" and exists(out) and not args.has("force"):
        raise Error(
            out
            + " already exists; pass --force to overwrite it, or -o another"
            " path"
        )
    var data = _fetch(client, d, a)
    if out == "-":
        _write_stdout(data)
        return
    with open(out, "w") as f:
        f.write_bytes(Span(data))
    print("saved " + ui.bold(out) + " (" + human_size(len(data)) + ")")


def doc_download_all(client: Client, args: Args, ui: Out) raises:
    """Every attachment of a document, downloaded one by one into a directory.

    CmfDocument.download_all_attachment is not used: the archive it builds is
    stored on the document as a new attachment, so it is a write.
    """
    args.check_known(["output", "o", "force", "verbose", "v"])
    var code = args.need(2, "document code")
    var id = id_of(client, "CmfDocument", "code", code)
    var rows = collect_rows(
        client,
        "CmfAttachment",
        '["parent_id","==",' + quote_str(id) + "]",
        "code,file_name,file_type,st_size,url",
        1000,
        "cmf_created_at",
    )
    ref d = rows.doc
    var n = d.len(rows.result)
    if n == 0:
        print(code + " has no attachments")
        return
    var dir = args.get("output", "o")
    if dir == "":
        dir = code
    # Name every file first: nothing is written when one of them would clash.
    var names = List[String]()
    var taken = Dict[String, Bool]()
    for i in range(n):
        var a = d.at(rows.result, i)
        var att = d.text_at(a, "code")
        var name = safe_file_name(
            d.text_at(a, "file_name"), att + d.text_at(a, "file_type")
        )
        if name in taken:
            name = att + "-" + name
        taken[name] = True
        if exists(dir + "/" + name) and not args.has("force"):
            raise Error(
                dir
                + "/"
                + name
                + " already exists; pass --force to overwrite it, or -o"
                " another directory"
            )
        names.append(name)
    makedirs(dir, exist_ok=True)
    var total = 0
    for i in range(n):
        var a = d.at(rows.result, i)
        var path = dir + "/" + names[i]
        var data: List[UInt8]
        try:
            data = _fetch(client, d, a)
        except e:
            raise Error(
                d.text_at(a, "code")
                + " ("
                + names[i]
                + "): "
                + String(e)
                + "; "
                + String(i)
                + " of "
                + String(n)
                + " files saved in "
                + dir
            )
        with open(path, "w") as f:
            f.write_bytes(Span(data))
        total += len(data)
        print("saved " + ui.bold(path) + " (" + human_size(len(data)) + ")")
    print(
        ui.dim(
            String(n)
            + (" file, " if n == 1 else " files, ")
            + human_size(total)
            + " in "
            + dir
        )
    )


def attachment_delete(client: Client, args: Args, ui: Out) raises:
    args.check_known(["yes", "y", "force", "verbose", "v"])
    var code = args.need(2, "attachment code")
    var r = get_attachment(client, code, ATTACHMENT_FIELDS)
    var id = r.doc.text_at(r.result, "id")
    var file_name = r.doc.text_at(r.result, "file_name")
    var what = (
        code + "  " + file_name + " on " + r.doc.text_at(r.result, "parent_id")
    )
    # EvaTeam keeps files by name per parent: deleting one attachment removes
    # the bytes of every other attachment there with the same name.
    var siblings = collect_rows(
        client,
        "CmfAttachment",
        '[["parent_id","==",'
        + quote_str(r.doc.text_at(r.result, "parent_id"))
        + '],["file_name","==",'
        + quote_str(file_name)
        + '],["id","!=",'
        + quote_str(id)
        + "]]",
        "code",
        1000,
    )
    var shared = List[String]()
    for i in range(siblings.doc.len(siblings.result)):
        shared.append(
            siblings.doc.text_at(siblings.doc.at(siblings.result, i), "code")
        )
    if len(shared) > 0:
        what += " (shares its file with " + ", ".join(shared) + ")"
        if not args.has("force"):
            raise Error(
                what
                + "; removing it would remove their bytes too. Pass --force"
                " to remove it anyway"
            )
    if not args.has("yes", "y"):
        if not stdin_is_tty():
            raise Error(
                "removing "
                + what
                + " needs confirmation: run it in a terminal, or pass --yes"
            )
        var answer = prompt_line("remove " + what + "? [y/N] ").lower()
        if (
            answer != "y"
            and answer != "yes"
            and answer != "д"
            and answer != "да"
        ):
            print("not removed")
            return
    _ = client.call("CmfAttachment.delete", "", "[" + quote_str(id) + "]")
    var got = client.call(
        "CmfAttachment.get", attachment_kwargs(id, "id,cmf_deleted")
    )
    if (
        got.doc.kind(got.result) == J_OBJ
        and got.doc.text_at(got.result, "cmf_deleted") != "true"
    ):
        raise Error(
            code + ": delete returned, but the attachment is still visible"
        )
    print(
        "removed "
        + ui.bold(code)
        + "; server deletion confirmed, not proof that stored bytes were erased"
    )


def _base_name(path: String) -> String:
    var i = path.rfind("/")
    return String(path[byte = i + 1 :]) if i >= 0 else path


def task_attach(client: Client, args: Args, ui: Out) raises:
    args.check_known(["dry-run", "force", "verbose", "v"])
    var code = args.need(2, "task code")
    var paths = List[String]()
    for i in range(3, len(args.positionals)):
        paths.append(args.positionals[i])
    if len(paths) == 0:
        raise Error("usage: eva task attach CODE FILE [FILE...]")
    var names = Dict[String, Bool]()
    for path in paths:
        var name = _base_name(path)
        if name in names:
            raise Error(
                "two files in this batch have the same name "
                + name
                + "; attach them separately or rename one"
            )
        names[name] = True
    # Read everything first: a missing file stops before anything is created.
    var contents = List[List[UInt8]]()
    for p in paths:
        try:
            with open(p, "r") as f:
                contents.append(f.read_bytes())
        except e:
            raise Error("cannot read " + p + ": " + String(e))
    var cls = "CmfDocument" if (
        args.pos(0) == "doc" or args.pos(0) == "docs"
    ) else "CmfTask"
    var task_id = code if code.startswith("CmfComment:") else id_of(
        client, cls, "code", code
    )
    # EvaTeam keeps a task's files by name: a second file with the same name
    # replaces the first one's bytes, and deleting either removes both.
    var existing = collect_rows(
        client,
        "CmfAttachment",
        '["parent_id","==",' + quote_str(task_id) + "]",
        "code,file_name,name",
        10000,
    )
    var force = args.has("force")
    for p in paths:
        var name = _base_name(p)
        for j in range(existing.doc.len(existing.result)):
            var x = existing.doc.at(existing.result, j)
            if (
                existing.doc.text_at(x, "file_name") == name
                or existing.doc.text_at(x, "name") == name
            ):
                if not force:
                    raise Error(
                        code
                        + " already has "
                        + name
                        + " ("
                        + existing.doc.text_at(x, "code")
                        + "); a file of the same name would replace it. Rename"
                        " the file, or pass --force to replace it"
                    )
    for i in range(len(paths)):
        var name = _base_name(paths[i])
        var d = JsonDoc()
        var kw = d.object()
        d.set_str(kw, "name", name)
        d.set_str(kw, "parent", task_id if cls == "CmfDocument" else code)
        # The server checks the size against its limit before the upload.
        var size_node = d.number(len(contents[i]))
        d.set(kw, "size", size_node)
        if preview_write(
            args.has("dry-run"), "CmfAttachment.create", d.dump(kw)
        ):
            print(
                "upload "
                + paths[i]
                + " follows after the server supplies its attachment URL"
            )
            continue
        var created = client.call("CmfAttachment.create", d.dump(kw))
        var id = created.doc.text(created.result)
        try:
            var a = get_attachment(client, id, "url")
            client.upload(a.doc.text_at(a.result, "url"), name, contents[i])
        except e:
            # Leave no empty attachment behind, unless it shares its file with
            # one that was there before (--force): deleting it would delete that.
            if not force:
                try:
                    _ = client.call(
                        "CmfAttachment.delete", "", "[" + quote_str(id) + "]"
                    )
                except:
                    pass
            raise Error(paths[i] + " was not attached: " + String(e))
        var got = get_attachment(client, id, "code,st_size")
        var size_text = got.doc.text_at(got.result, "st_size")
        var size = Int(size_text) if size_text != "" else -1
        var line = (
            "attached "
            + ui.bold(got.doc.text_at(got.result, "code"))
            + "  "
            + name
            + "  "
            + human_size(len(contents[i]))
        )
        if size > 0 and size != len(contents[i]):
            line += ui.dim("  (the server reports " + String(size) + " bytes)")
        print(line)
