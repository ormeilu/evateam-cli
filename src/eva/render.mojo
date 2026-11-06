"""Output for a person at a terminal and for a program or agent behind a pipe.

A terminal gets colour and the whole text of a description. A pipe gets
plain text, the first lines of a description and a note saying how much was
left out. Text written by EvaTeam users is fenced either way: a `▏` margin in
a terminal, an `<untrusted>` tag in a pipe.
"""

from std.ffi import external_call
import mist

comptime PIPE_LINES = 20


def stdout_is_tty() -> Bool:
    return external_call["isatty", Int32](Int32(1)) == 1


struct Out(Movable):
    var tty: Bool
    var full: Bool

    def __init__(out self, full: Bool):
        self.tty = stdout_is_tty()
        self.full = full

    def bold(self, s: String) -> String:
        if not self.tty:
            return s
        return mist.Style().bold().render(s)

    def dim(self, s: String) -> String:
        if not self.tty:
            return s
        return mist.Style().faint().render(s)

    def accent(self, s: String) -> String:
        if not self.tty:
            return s
        return mist.Style().foreground(12).render(s)

    def status(self, s: String) -> String:
        if not self.tty:
            return s
        var l = s.lower()
        if l.find("закрыт") >= 0 or l.find("готов") >= 0 or l.find("done") >= 0 or l.find("closed") >= 0:
            return mist.Style().foreground(2).render(s)
        if l.find("работ") >= 0 or l.find("progress") >= 0:
            return mist.Style().foreground(3).render(s)
        return mist.Style().foreground(6).render(s)

    def untrusted(self, src: String, html: String):
        """Print somebody else's text with its boundary marked."""
        if self.tty:
            var lines = fence_lines(html)
            if len(lines) == 0:
                return
            print(self.dim("--- " + safe_src(src) + " (written by EvaTeam users)"))
            for line in lines:
                print(self.dim("▏ ") + line)
            return
        var block = fence_pipe(src, html, self.full)
        if block != "":
            print(block, end="")


def safe_src(src: String) -> String:
    """A source label that cannot break out of the src="..." attribute."""
    return String(src.replace('"', "").replace("<", "").replace(">", "").replace("\n", " "))


def defuse_fence(text: String) -> String:
    """Neutralise <untrusted and </untrusted in somebody else's text, in any
    case, so it cannot close the fence early and pass what follows as eva's own
    output."""
    var lower = text.lower()
    if lower.find("untrusted") < 0:
        return text
    var out = String()
    var i = 0
    var n = text.byte_length()
    while i < n:
        var rest = String(lower[byte = i : n])
        if rest.startswith("<untrusted") or rest.startswith("</untrusted"):
            out += "&lt;"
            i += 1
            continue
        var j = rest.find("<")
        if j <= 0:
            if j < 0:
                out += String(text[byte = i : n])
                break
            out += String(text[byte = i : i + 1])
            i += 1
            continue
        out += String(text[byte = i : i + j])
        i += j
    return out


def fence_lines(html: String) -> List[String]:
    """Somebody else's HTML as plain, defused lines; empty if there is no text."""
    var text = defuse_fence(html_to_text(html))
    var out = List[String]()
    if text.strip() == "":
        return out^
    for line in text.split("\n"):
        out.append(String(line))
    return out^


def fence_pipe(src: String, html: String, full: Bool) -> String:
    """The pipe form: an <untrusted> block, capped at PIPE_LINES unless `full`."""
    var lines = fence_lines(html)
    if len(lines) == 0:
        return ""
    var limit = len(lines) if full else min(len(lines), PIPE_LINES)
    var out = '<untrusted src="' + safe_src(src) + '">\n'
    for i in range(limit):
        out += lines[i] + "\n"
    out += "</untrusted>\n"
    if limit < len(lines):
        out += "(+" + String(len(lines) - limit) + " more lines: --full)\n"
    return out


def pad(s: String, width: Int) -> String:
    """Left-align to `width` code points; never cut."""
    var n = len(s.codepoints())
    if n >= width:
        return s
    return s + " " * (width - n)


def clip(s: String, width: Int) -> String:
    """One line, at most `width` code points, with an ellipsis if cut."""
    var flat = String(s.replace("\n", " ").strip())
    var n = 0
    var out = String()
    for cp in flat.codepoints():
        if n == width - 1 and len(flat.codepoints()) > width:
            out += "…"
            return out
        out += String(cp)
        n += 1
    return out


def html_to_text(html: String) -> String:
    """EvaTeam stores rich text as HTML. Keep the words, drop the markup."""
    var out = String()
    var b = html.as_bytes()
    var i = 0
    var start = 0
    while i < len(b):
        var c = Int(b[i])
        if c == 0x3C:  # <
            if i > start:
                out += String(html[byte=start:i])
            var close = i
            while close < len(b) and Int(b[close]) != 0x3E:
                close += 1
            var tag = String(html[byte = i + 1 : close]).lower()
            if (
                tag.startswith("br")
                or tag == "p"
                or tag.startswith("p ")
                or tag.startswith("/p")
                or tag.startswith("/ol")
                or tag.startswith("/ul")
                or tag.startswith("/div")
                or tag.startswith("/h")
                or tag.startswith("/tr")
                or tag.startswith("/blockquote")
                or tag.startswith("/pre")
            ):
                out += "\n"
            elif tag.startswith("li"):
                out += "\n- "
            elif tag.startswith("td") or tag.startswith("th"):
                # A separator between cells, not before the first one in a row.
                if out.byte_length() > 0 and not out.endswith("\n"):
                    out += " | "
            i = close + 1
            start = i
            continue
        i += 1
    if start < len(b):
        out += String(html[byte = start : len(b)])
    var text = unescape_entities(out)
    # Collapse runs of blank lines left by nested blocks.
    var lines = text.split("\n")
    var res = String()
    var blank = 0
    var started = False
    for line in lines:
        var l = String(line.rstrip())
        if l == "":
            blank += 1
            continue
        if started:
            res += "\n\n" if blank > 0 else "\n"
        res += l
        started = True
        blank = 0
    return res


def unescape_entities(s: String) -> String:
    return String(
        s.replace("&nbsp;", " ")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", '"')
        .replace("&#39;", "'")
        .replace("&laquo;", "«")
        .replace("&raquo;", "»")
        .replace("&mdash;", "—")
        .replace("&ndash;", "–")
        .replace("&amp;", "&")
    )


def text_to_html(s: String) -> String:
    """Plain text from the command line becomes paragraphs."""
    var esc = String(s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))
    var out = String()
    for para in esc.split("\n\n"):
        out += "<p>" + String(para).replace("\n", "<br>") + "</p>"
    return out


def escape_html(s: String) -> String:
    return String(s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;"))


def _is_word_byte(b: UInt8) -> Bool:
    """Letters, digits and anything non-ASCII: `_` inside a word is not emphasis."""
    var c = Int(b)
    return (c >= 0x30 and c <= 0x39) or (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A) or c >= 0x80


def _safe_href(url: String) -> Bool:
    var l = url.lower()
    return (l.startswith("https://") or l.startswith("http://") or l.startswith("mailto:")) and url.find(" ") < 0


def md_inline(s: String) -> String:
    """`code`, **bold**, __bold__, *italic*, _italic_ and [text](url) in one line;
    everything else escaped."""
    var b = s.as_bytes()
    var n = len(b)
    var out = String()
    var start = 0
    var i = 0
    while i < n:
        var c = Int(b[i])
        var end = -1
        var html = String()
        if c == 0x60:  # `
            var j = s.find("`", i + 1)
            if j > i + 1:
                html = "<code>" + escape_html(String(s[byte = i + 1 : j])) + "</code>"
                end = j + 1
        elif (c == 0x2A or c == 0x5F) and i + 1 < n and Int(b[i + 1]) == c:  # ** or __
            var mark = "**" if c == 0x2A else "__"
            var j = s.find(mark, i + 2)
            if j > i + 2:
                html = "<strong>" + md_inline(String(s[byte = i + 2 : j])) + "</strong>"
                end = j + 2
        elif c == 0x2A or (c == 0x5F and (i == 0 or not _is_word_byte(b[i - 1]))):  # * or _
            var j = s.find("*" if c == 0x2A else "_", i + 1)
            if (
                j > i + 1
                and Int(b[i + 1]) != 0x20
                and (c == 0x2A or j + 1 >= n or not _is_word_byte(b[j + 1]))
            ):
                html = "<em>" + md_inline(String(s[byte = i + 1 : j])) + "</em>"
                end = j + 1
        elif c == 0x5B:  # [text](url)
            var j = s.find("](", i + 1)
            var k = s.find(")", j + 2) if j > i else -1
            if j > i and k > j:
                var url = String(s[byte = j + 2 : k])
                if _safe_href(url):
                    html = '<a href="' + escape_html(url) + '">' + md_inline(String(s[byte = i + 1 : j])) + "</a>"
                    end = k + 1
        if end < 0:
            i += 1
            continue
        out += escape_html(String(s[byte=start:i])) + html
        i = end
        start = end
    return out + escape_html(String(s[byte=start:n]))


def _list_item(line: String) -> Tuple[String, String]:
    """("ul" or "ol", the item's text) for a list line, or ("", "")."""
    var t = String(line.lstrip())
    if t.startswith("- ") or t.startswith("* ") or t.startswith("+ "):
        return (String("ul"), String(t[byte=2:]))
    var b = t.as_bytes()
    var i = 0
    while i < len(b) and Int(b[i]) >= 0x30 and Int(b[i]) <= 0x39:
        i += 1
    if i > 0 and i + 1 < len(b) and (Int(b[i]) == 0x2E or Int(b[i]) == 0x29) and Int(b[i + 1]) == 0x20:
        return (String("ol"), String(t[byte = i + 2 :]))
    return (String(""), String(""))


def _heading(line: String) -> Tuple[Int, String]:
    var b = line.as_bytes()
    var i = 0
    while i < len(b) and Int(b[i]) == 0x23:
        i += 1
    if i >= 1 and i <= 6 and i < len(b) and Int(b[i]) == 0x20:
        return (min(i, 3), String(String(line[byte = i + 1 :]).strip()))
    return (0, String(""))


def _is_rule(line: String) -> Bool:
    var t = String(line.strip().replace(" ", ""))
    return t.byte_length() >= 3 and (t == "-" * t.byte_length() or t == "*" * t.byte_length() or t == "_" * t.byte_length())


struct _Md:
    """The HTML so far plus the paragraph, list or quote still open."""

    var out: String
    var para: List[String]
    var list_kind: String
    var quote: List[String]

    def __init__(out self):
        self.out = String()
        self.para = List[String]()
        self.list_kind = String()
        self.quote = List[String]()

    def close(mut self, para: Bool = True, list: Bool = True, quote: Bool = True):
        if para and len(self.para) > 0:
            self.out += "<p>" + "<br>".join(self.para) + "</p>"
            self.para.clear()
        if list and self.list_kind != "":
            self.out += "</" + self.list_kind + ">"
            self.list_kind = ""
        if quote and len(self.quote) > 0:
            self.out += "<blockquote>" + "<br>".join(self.quote) + "</blockquote>"
            self.quote.clear()


def markdown_to_html(src: String) -> String:
    """The Markdown people write in comments, as the HTML EvaTeam renders:
    headings (h1-h3), paragraphs, lists, quotes, code blocks, rules, and the
    inline forms md_inline knows. Raw HTML in the source is escaped."""
    var lines = List[String]()
    for l in src.replace("\r\n", "\n").split("\n"):
        lines.append(String(l))
    var md = _Md()
    var i = 0
    while i < len(lines):
        var line = lines[i]
        i += 1
        var stripped = String(line.strip())
        if stripped.startswith("```"):
            md.close()
            var code = List[String]()
            while i < len(lines) and not String(lines[i].strip()).startswith("```"):
                code.append(escape_html(lines[i]))
                i += 1
            i += 1  # the closing fence, if there is one
            md.out += "<pre><code>" + "\n".join(code) + "</code></pre>"
            continue
        if stripped == "":
            md.close()
            continue
        var h = _heading(stripped)
        if h[0] > 0:
            md.close()
            md.out += "<h" + String(h[0]) + ">" + md_inline(h[1]) + "</h" + String(h[0]) + ">"
            continue
        if _is_rule(stripped):
            md.close()
            md.out += "<hr>"
            continue
        var item = _list_item(line)
        if item[0] != "":
            md.close(list=False)
            if md.list_kind != item[0]:
                md.close()
                md.list_kind = item[0]
                md.out += "<" + md.list_kind + ">"
            md.out += "<li>" + md_inline(String(item[1].strip())) + "</li>"
            continue
        if stripped.startswith(">"):
            md.close(quote=False)
            md.quote.append(md_inline(String(String(stripped[byte=1:]).strip())))
            continue
        md.close(para=False)
        md.para.append(md_inline(stripped))
    md.close()
    return md.out
