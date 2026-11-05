"""Reading a line or a secret from stdin, a terminal or a pipe alike.

The builtin input() buffers a chunk of a pipe and drops what follows the first
line, so lines are read here one byte at a time with read(2).
"""

from std.ffi import external_call, c_int
from std.memory.alloc import unsafe_alloc
from std.subprocess import run
from std.sys import stderr

from requests._dns import _cstr


def stdin_is_tty() -> Bool:
    return external_call["isatty", c_int](c_int(0)) == 1


def read_line() raises -> String:
    """One line from stdin without its newline. Raises on EOF before any byte."""
    var buf = unsafe_alloc[UInt8](1)
    var bytes = List[UInt8]()
    var got_any = False
    while True:
        var n = external_call["read", Int](c_int(0), buf, Int(1))
        if n <= 0:
            break
        got_any = True
        var b = buf[unsafe_offset=0]
        if b == 0x0A:
            break
        if b != 0x0D:
            bytes.append(b)
    buf.unsafe_free()
    if not got_any:
        raise Error("no input")
    return String(from_utf8_lossy=Span(bytes))


def _shell(cmd: String):
    var c = _cstr(cmd)
    _ = external_call["system", c_int](c)
    c.unsafe_free()


def prompt_line(prompt: String) raises -> String:
    if stdin_is_tty():
        print(prompt, end="", file=stderr, flush=True)
    return String(read_line().strip())


def prompt_secret(prompt: String) raises -> String:
    """A line typed without echo on a terminal, or read as is from a pipe.

    On a terminal a small shell reads it: its trap turns echo back on even when
    the user presses Ctrl-C. The secret passes through the shell's memory and
    its stdout pipe, never through argv or the environment.
    """
    if not stdin_is_tty():
        return String(read_line().strip())
    print(prompt, end="", file=stderr, flush=True)
    var secret = run("trap 'stty echo' EXIT INT TERM; stty -echo; IFS= read -r s; printf '%s' \"$s\"")
    print("", file=stderr)
    return String(secret.strip())
