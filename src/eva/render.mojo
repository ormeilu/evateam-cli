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
