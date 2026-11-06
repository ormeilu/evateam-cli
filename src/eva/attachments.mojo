"""Files attached to tasks: list them, read the text EvaTeam extracted from
one, or download the original bytes."""

from std.ffi import external_call, c_int
from std.os.path import exists

from eva.args import Args
from eva.client import Client, Reply
from eva.commands import id_of, print_json, split_csv, want_json
from eva.json import JsonDoc, J_OBJ, clean
from eva.render import Out, pad

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
    out = trimmed
    return out if out != "" else fallback


def attachment_kwargs(ref_: String, fields: String) raises -> String:
    """Filter one attachment by its ATT code or CmfAttachment id."""
    var d = JsonDoc()
    var kw = d.object()
    var v = d.string(ref_)
    var f = d.triple("id" if ref_.startswith("CmfAttachment:") else "code", "==", v)
    d.set(kw, "filter", f)
    var fl = d.str_array(split_csv(fields))
    d.set(kw, "fields", fl)
    return d.dump(kw)


def get_attachment(client: Client, ref_: String, fields: String) raises -> Reply:
    var r = client.call("CmfAttachment.get", attachment_kwargs(ref_, fields))
    if r.doc.is_null(r.result) or r.doc.kind(r.result) != J_OBJ:
        raise Error(ref_ + ": no such attachment, or no access to it")
    return r^


def task_attachments(client: Client, args: Args, ui: Out) raises:
    args.check_known(["json", "format", "verbose", "v"])
    var code = args.need(2, "task code")
    var task_id = id_of(client, "CmfTask", "code", code)
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
        var size = Int(r.doc.text_at(a, "st_size")) if r.doc.text_at(a, "st_size") != "" else 0
        var line = ui.accent(pad(r.doc.text_at(a, "code"), 12)) + " " + pad(human_size(size), 8)
        line += " " + String(r.doc.text_at(a, "cmf_created_at")[byte=0:10]) + "  " + r.doc.text_at(a, "file_name")
        if r.doc.text_at(a, "embedded") == "true":
            line += ui.dim("  (image in the text)")
        print(line)
    print(ui.dim(String(n) + (" attachment" if n == 1 else " attachments") + "; read one: eva attachment get ATT-…"))


def attachment_get(client: Client, args: Args, ui: Out) raises:
    args.check_known(["json", "format", "full", "verbose", "v"])
    var ref_ = args.need(2, "attachment code, e.g. eva attachment get ATT-190580")
    var r = get_attachment(client, ref_, ATTACHMENT_FIELDS + ",text")
    if want_json(args):
        print_json(r)
        return
    ref d = r.doc
    var a = r.result
    var size = Int(d.text_at(a, "st_size")) if d.text_at(a, "st_size") != "" else 0
    print(ui.bold(d.text_at(a, "code")) + "  " + d.text_at(a, "file_name"))
    print("type: " + d.text_at(a, "file_type") + "   size: " + human_size(size) + "   on: " + d.text_at(a, "parent_id"))
    print(ui.dim("added: " + d.text_at(a, "cmf_created_at") + " by " + d.text_at(a, "cmf_author.name")))
    var text = d.text_at(a, "text")
    if String(text.strip()) == "":
        print(ui.dim("no extracted text; get the file: eva attachment download " + d.text_at(a, "code")))
        return
    # Plain text, not HTML: escape it so the fence's HTML reading keeps it as is.
    var esc = String(text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))
    ui.untrusted(d.text_at(a, "code") + "/text", esc.replace("\n", "<br>"))


def _write_stdout(data: List[UInt8]) raises:
    var done = 0
    while done < len(data):
        var n = external_call["write", Int](c_int(1), data.unsafe_ptr().unsafe_offset(done), len(data) - done)
        if n <= 0:
            raise Error("cannot write to stdout")
        done += n


def attachment_download(client: Client, args: Args, ui: Out) raises:
    args.check_known(["output", "o", "force", "verbose", "v"])
    var ref_ = args.need(2, "attachment code, e.g. eva attachment download ATT-190580")
    var r = get_attachment(client, ref_, ATTACHMENT_FIELDS)
    ref d = r.doc
    var a = r.result
    var code = d.text_at(a, "code")
    var expected = Int(d.text_at(a, "st_size")) if d.text_at(a, "st_size") != "" else -1
    var out = args.get("output", "o")
    if out == "":
        out = safe_file_name(d.text_at(a, "file_name"), code + d.text_at(a, "file_type"))
    if out != "-" and exists(out) and not args.has("force"):
        raise Error(out + " already exists; pass --force to overwrite it, or -o another path")
    var data = client.download(d.text_at(a, "url"))
    if expected >= 0 and len(data) != expected:
        # A refusal comes back as a short JSON reply with HTTP 200.
        var head = String(from_utf8_lossy=Span(data)[0 : min(len(data), 200)])
        raise Error(
            "got " + String(len(data)) + " bytes instead of " + String(expected) + "; the server said: " + clean(head)
        )
    if out == "-":
        _write_stdout(data)
        return
    with open(out, "w") as f:
        f.write_bytes(Span(data))
    print("saved " + ui.bold(out) + " (" + human_size(len(data)) + ")")
