"""A small JSON tree for EvaTeam requests and responses.

Nodes live in one arena (`JsonDoc.nodes`) and point at their children by
index, which keeps the type non-recursive. Numbers keep their source text, so
an id or a timestamp passes through unchanged.
"""

comptime J_NULL = 0
comptime J_BOOL = 1
comptime J_NUM = 2
comptime J_STR = 3
comptime J_ARR = 4
comptime J_OBJ = 5

comptime NO_NODE = -1


@fieldwise_init
struct JNode(Copyable, Movable):
    var kind: Int
    # String value, number text, or "true"/"false".
    var text: String
    var children: List[Int]
    # Object keys, parallel to `children`.
    var keys: List[String]


struct JsonDoc(Movable):
    var nodes: List[JNode]

    def __init__(out self):
        self.nodes = List[JNode]()

    # ---- building ----

    def _add(mut self, kind: Int, text: String) -> Int:
        self.nodes.append(JNode(kind, text, List[Int](), List[String]()))
        return len(self.nodes) - 1

    def null(mut self) -> Int:
        return self._add(J_NULL, "")

    def boolean(mut self, v: Bool) -> Int:
        return self._add(J_BOOL, "true" if v else "false")

    def number(mut self, v: Int) -> Int:
        return self._add(J_NUM, String(v))

    def number_text(mut self, text: String) -> Int:
        return self._add(J_NUM, text)

    def string(mut self, v: String) -> Int:
        return self._add(J_STR, v)

    def array(mut self) -> Int:
        return self._add(J_ARR, "")

    def object(mut self) -> Int:
        return self._add(J_OBJ, "")

    def push(mut self, arr: Int, child: Int):
        self.nodes[arr].children.append(child)

    def set(mut self, obj: Int, key: String, child: Int):
        """Set `key` on an object, replacing an existing value."""
        for i in range(len(self.nodes[obj].keys)):
            if self.nodes[obj].keys[i] == key:
                self.nodes[obj].children[i] = child
                return
        self.nodes[obj].keys.append(key)
        self.nodes[obj].children.append(child)

    def set_str(mut self, obj: Int, key: String, v: String):
        var c = self.string(v)
        self.set(obj, key, c)

    def str_array(mut self, items: List[String]) -> Int:
        var a = self.array()
        for s in items:
            var c = self.string(s)
            self.push(a, c)
        return a

    def triple(mut self, field: String, op: String, value: Int) -> Int:
        """A BQL condition: [field, op, value]."""
        var a = self.array()
        var f = self.string(field)
        var o = self.string(op)
        self.push(a, f)
        self.push(a, o)
        self.push(a, value)
        return a

    # ---- reading ----

    def kind(self, n: Int) -> Int:
        if n < 0:
            return J_NULL
        return self.nodes[n].kind

    def is_null(self, n: Int) -> Bool:
        return n < 0 or self.nodes[n].kind == J_NULL

    def len(self, n: Int) -> Int:
        if n < 0:
            return 0
        return len(self.nodes[n].children)

    def at(self, n: Int, i: Int) -> Int:
        return self.nodes[n].children[i]

    def key_at(self, n: Int, i: Int) -> String:
        return self.nodes[n].keys[i]

    def get(self, n: Int, key: String) -> Int:
        if n < 0 or self.nodes[n].kind != J_OBJ:
            return NO_NODE
        for i in range(len(self.nodes[n].keys)):
            if self.nodes[n].keys[i] == key:
                return self.nodes[n].children[i]
        return NO_NODE

    def path(self, n: Int, dotted: String) raises -> Int:
        """Follow `a.b.c` through nested objects."""
        var cur = n
        for part in dotted.split("."):
            cur = self.get(cur, String(part))
            if cur < 0:
                return NO_NODE
        return cur

    def text(self, n: Int) -> String:
        """Scalar as display text; "" for null or a missing node."""
        if n < 0:
            return ""
        var k = self.nodes[n].kind
        if k == J_NULL:
            return ""
        if k == J_ARR or k == J_OBJ:
            return self.dump(n)
        return self.nodes[n].text

    def text_at(self, n: Int, dotted: String) raises -> String:
        return self.text(self.path(n, dotted))

    # ---- serialising ----

    def dump(self, n: Int) -> String:
        var out = String()
        self._write(n, out, -1, 0)
        return out

    def dump_pretty(self, n: Int) -> String:
        var out = String()
        self._write(n, out, 2, 0)
        return out

    def _write(self, n: Int, mut out: String, indent: Int, depth: Int):
        if n < 0:
            out += "null"
            return
        var k = self.nodes[n].kind
        if k == J_NULL:
            out += "null"
        elif k == J_BOOL or k == J_NUM:
            out += self.nodes[n].text
        elif k == J_STR:
            write_quoted(self.nodes[n].text, out)
        else:
            var count = len(self.nodes[n].children)
            out += "[" if k == J_ARR else "{"
            if count == 0:
                out += "]" if k == J_ARR else "}"
                return
            for i in range(count):
                if i > 0:
                    out += ","
                if indent >= 0:
                    out += "\n"
                    out += " " * (indent * (depth + 1))
                if k == J_OBJ:
                    write_quoted(self.nodes[n].keys[i], out)
                    out += ": " if indent >= 0 else ":"
                self._write(self.nodes[n].children[i], out, indent, depth + 1)
            if indent >= 0:
                out += "\n"
                out += " " * (indent * depth)
            out += "]" if k == J_ARR else "}"

    # ---- parsing ----

    def parse(mut self, src: String) raises -> Int:
        """Parse `src` into this document and return the new root."""
        var p = Parser(src)
        p.skip_ws()
        var root = p.value(self)
        p.skip_ws()
        if p.pos < len(p.data):
            raise Error("json: trailing data at byte " + String(p.pos))
        return root


def parse_json(src: String, mut doc: JsonDoc) raises -> Int:
    return doc.parse(src)


def write_quoted(s: String, mut out: String):
    out += '"'
    var b = s.as_bytes()
    var start = 0
    for i in range(len(b)):
        var c = Int(b[i])
        if c == 0x22 or c == 0x5C or c < 0x20:
            if i > start:
                out += String(s[byte=start:i])
            if c == 0x22:
                out += '\\"'
            elif c == 0x5C:
                out += "\\\\"
            elif c == 0x0A:
                out += "\\n"
            elif c == 0x0D:
                out += "\\r"
            elif c == 0x09:
                out += "\\t"
            else:
                out += "\\u00"
                out += hex_digit(c >> 4)
                out += hex_digit(c & 15)
            start = i + 1
    if start < len(b):
        out += String(s[byte=start : len(b)])
    out += '"'


def quote(s: String) -> String:
    var out = String()
    write_quoted(s, out)
    return out


def hex_digit(v: Int) -> String:
    return String("0123456789abcdef"[byte=v : v + 1])


def hex_value(c: Int) raises -> Int:
    if c >= 0x30 and c <= 0x39:
        return c - 0x30
    if c >= 0x61 and c <= 0x66:
        return c - 0x61 + 10
    if c >= 0x41 and c <= 0x46:
        return c - 0x41 + 10
    raise Error("json: bad hex digit")


struct Parser:
    var src: String
    var data: List[UInt8]
    var pos: Int

    def __init__(out self, src: String):
        self.src = src
        self.data = List[UInt8]()
        for b in src.as_bytes():
            self.data.append(b)
        self.pos = 0

    def peek(self) -> Int:
        if self.pos >= len(self.data):
            return -1
        return Int(self.data[self.pos])

    def fail(self, what: String) raises:
        raise Error("json: " + what + " at byte " + String(self.pos))

    def skip_ws(mut self):
        while self.pos < len(self.data):
            var c = Int(self.data[self.pos])
            if c == 0x20 or c == 0x0A or c == 0x0D or c == 0x09:
                self.pos += 1
            else:
                break

    def expect_word(mut self, word: String) raises:
        var w = word.as_bytes()
        for i in range(len(w)):
            if self.pos + i >= len(self.data) or self.data[self.pos + i] != w[i]:
                self.fail("expected " + word)
        self.pos += len(w)

    def value(mut self, mut doc: JsonDoc) raises -> Int:
        var c = self.peek()
        if c == 0x7B:  # {
            return self.obj(doc)
        if c == 0x5B:  # [
            return self.arr(doc)
        if c == 0x22:  # "
            var s = self.str()
            return doc.string(s)
        if c == 0x74:
            self.expect_word("true")
            return doc.boolean(True)
        if c == 0x66:
            self.expect_word("false")
            return doc.boolean(False)
        if c == 0x6E:
            self.expect_word("null")
            return doc.null()
        if c == 0x2D or (c >= 0x30 and c <= 0x39):
            return self.num(doc)
        self.fail("unexpected character")
        return NO_NODE

    def obj(mut self, mut doc: JsonDoc) raises -> Int:
        var n = doc.object()
        self.pos += 1
        self.skip_ws()
        if self.peek() == 0x7D:
            self.pos += 1
            return n
        while True:
            self.skip_ws()
            if self.peek() != 0x22:
                self.fail("expected object key")
            var key = self.str()
            self.skip_ws()
            if self.peek() != 0x3A:
                self.fail("expected ':'")
            self.pos += 1
            self.skip_ws()
            var v = self.value(doc)
            doc.nodes[n].keys.append(key)
            doc.nodes[n].children.append(v)
            self.skip_ws()
            var c = self.peek()
            self.pos += 1
            if c == 0x2C:
                continue
            if c == 0x7D:
                return n
            self.pos -= 1
            self.fail("expected ',' or '}'")

    def arr(mut self, mut doc: JsonDoc) raises -> Int:
        var n = doc.array()
        self.pos += 1
        self.skip_ws()
        if self.peek() == 0x5D:
            self.pos += 1
            return n
        while True:
            self.skip_ws()
            var v = self.value(doc)
            doc.nodes[n].children.append(v)
            self.skip_ws()
            var c = self.peek()
            self.pos += 1
            if c == 0x2C:
                continue
            if c == 0x5D:
                return n
            self.pos -= 1
            self.fail("expected ',' or ']'")

    def num(mut self, mut doc: JsonDoc) raises -> Int:
        var start = self.pos
        while self.pos < len(self.data):
            var c = Int(self.data[self.pos])
            if (c >= 0x30 and c <= 0x39) or c == 0x2D or c == 0x2B or c == 0x2E or c == 0x65 or c == 0x45:
                self.pos += 1
            else:
                break
        return doc.number_text(String(self.src[byte=start : self.pos]))

    def hex4(mut self) raises -> Int:
        if self.pos + 4 > len(self.data):
            self.fail("short \\u escape")
        var v = 0
        for i in range(4):
            v = v * 16 + hex_value(Int(self.data[self.pos + i]))
        self.pos += 4
        return v

    def str(mut self) raises -> String:
        self.pos += 1  # opening quote
        var out = String()
        var start = self.pos
        while True:
            if self.pos >= len(self.data):
                self.fail("unterminated string")
            var c = Int(self.data[self.pos])
            if c == 0x22:
                if self.pos > start:
                    out += String(self.src[byte=start : self.pos])
                self.pos += 1
                return out
            if c != 0x5C:
                self.pos += 1
                continue
            if self.pos > start:
                out += String(self.src[byte=start : self.pos])
            self.pos += 1
            var e = self.peek()
            self.pos += 1
            if e == 0x22:
                out += '"'
            elif e == 0x5C:
                out += "\\"
            elif e == 0x2F:
                out += "/"
            elif e == 0x62:
                out += chr(8)
            elif e == 0x66:
                out += chr(12)
            elif e == 0x6E:
                out += "\n"
            elif e == 0x72:
                out += "\r"
            elif e == 0x74:
                out += "\t"
            elif e == 0x75:
                var cp = self.hex4()
                # A UTF-16 surrogate pair spells one code point.
                if cp >= 0xD800 and cp <= 0xDBFF and self.peek() == 0x5C:
                    self.pos += 2
                    var lo = self.hex4()
                    cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00)
                out += chr(cp)
            else:
                self.pos -= 1
                self.fail("bad escape")
            start = self.pos
