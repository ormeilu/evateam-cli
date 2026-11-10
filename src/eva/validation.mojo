"""Verify the requested subset of server-normalized field values."""
from std.sys import stderr

from eva.json import JsonDoc, J_OBJ, J_ARR, J_NUM, J_STR, clean


def date_key(s: String) -> String:
    """`YYYY-MM-DD` or `YYYY-MM-DD HH:MM` of a date or datetime, without
    seconds, fraction or offset; "" when `s` is not one."""
    var b = s.as_bytes()
    if len(b) < 10:
        return ""
    for i in range(10):
        var c = Int(b[i])
        if i == 4 or i == 7:
            if c != 0x2D:
                return ""
        elif c < 0x30 or c > 0x39:
            return ""
    var day = String(s[byte=0:10])
    if len(b) == 10:
        return day
    if len(b) < 16 or (Int(b[10]) != 0x54 and Int(b[10]) != 0x20):
        return ""
    if Int(b[13]) != 0x3A:
        return ""
    return day + " " + String(s[byte=11:16])


def markup_key(s: String) -> String:
    """The visible text of an HTML fragment, whitespace collapsed, so that a
    server's sanitizer rewriting tags or attributes still compares equal."""
    var out = String()
    var in_tag = False
    var space = True
    for cp in s.codepoints():
        var c = Int(cp)
        if in_tag:
            if c == 0x3E:
                in_tag = False
                if not space:
                    out += " "
                    space = True
            continue
        if c == 0x3C:
            in_tag = True
            continue
        if c == 0x20 or c == 0x09 or c == 0x0A or c == 0x0D or c == 0xA0:
            if not space:
                out += " "
                space = True
            continue
        out += String(cp)
        space = False
    var text = String(out.strip())
    for pair in [
        ("&nbsp;", " "),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&quot;", '"'),
        ("&#39;", "'"),
        ("&amp;", "&"),
    ]:
        text = text.replace(pair[0], pair[1])
    return text


def text_confirmed(sent: String, stored: String) -> Bool:
    """Whether markup read back (already passed through `clean`) is the markup
    that was sent, allowing for the server's sanitizer."""
    var s = clean(sent)
    return s == stored or markup_key(s) == markup_key(stored)


def _number(s: String) -> Optional[Float64]:
    try:
        return Float64(s)
    except:
        return None


def _strings_match(expected: String, actual: String) -> Bool:
    if expected == actual:
        return True
    var ek = date_key(expected)
    if ek != "":
        var ak = date_key(actual)
        # A date written without a time reads back as a datetime.
        return ak != "" and (ak == ek or String(ak[byte=0:10]) == ek)
    if expected.startswith("<"):
        return markup_key(expected) == markup_key(actual)
    return False


def field_confirmed(expected: JsonDoc, e: Int, actual: JsonDoc, a: Int) raises -> Bool:
    if a < 0:
        return False
    var ek = expected.kind(e)
    var ak = actual.kind(a)
    if ek == J_OBJ:
        if ak != J_OBJ:
            return False
        for i in range(expected.len(e)):
            if not field_confirmed(
                expected,
                expected.at(e, i),
                actual,
                actual.get(a, expected.key_at(e, i)),
            ):
                return False
        return True
    if ek == J_ARR:
        if ak != J_ARR or expected.len(e) != actual.len(a):
            return False
        var used = List[Int]()
        for i in range(expected.len(e)):
            var hit = -1
            for j in range(actual.len(a)):
                var taken = False
                for k in used:
                    if j == k:
                        taken = True
                if not taken and field_confirmed(expected, expected.at(e, i), actual, actual.at(a, j)):
                    hit = j
                    break
            if hit < 0:
                return False
            used.append(hit)
        return True
    if ek == J_STR and ak == J_OBJ:
        var value = expected.text(e)
        return value == actual.text_at(a, "id") or value == actual.text_at(a, "code")
    if ek == J_NUM and (ak == J_NUM or ak == J_STR):
        # Decimal fields can come back as strings ("3.00").
        var x = _number(expected.text(e))
        var y = _number(actual.text(a))
        return Bool(x) and Bool(y) and x.value() == y.value()
    if ek == J_STR and ak == J_STR:
        return _strings_match(expected.text(e), actual.text(a))
    return ek == ak and expected.text(e) == actual.text(a)


def _short(s: String) -> String:
    var out = String()
    var n = 0
    for cp in s.codepoints():
        if n == 80:
            return out + "…"
        out += String(cp)
        n += 1
    return out


def _soft(expected: JsonDoc, e: Int) raises -> Bool:
    """Values whose stored form depends on server rules eva cannot see: time
    zones for datetimes, the sanitizer for markup."""
    if expected.kind(e) != J_STR:
        return False
    var s = expected.text(e)
    return date_key(s) != "" or s.startswith("<")


def require_fields(expected: JsonDoc, kw: Int, actual: JsonDoc, result: Int, code: String) raises:
    for i in range(expected.len(kw)):
        var field = expected.key_at(kw, i)
        var a = actual.get(result, field)
        if field_confirmed(expected, expected.at(kw, i), actual, a):
            continue
        if _soft(expected, expected.at(kw, i)):
            print(
                "note: "
                + code
                + " "
                + field
                + " reads back as "
                + (_short(actual.text(a)) if a >= 0 else "nothing")
                + "; check it if that is not what you meant",
                file=stderr,
            )
            continue
        raise Error(
            code + " was written, but " + field + " was not confirmed by readback; inspect the task before retrying"
        )
