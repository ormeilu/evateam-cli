"""Private, no-follow diagnostics cache, using directory-relative atomic writes.

No Python runtime, shell commands, fixed spill files or process-wide umask changes.
"""
from std.ffi import external_call, c_int
from std.memory.alloc import unsafe_alloc
from std.os import getenv, makedirs
from std.sys import CompilationTarget
from eva.client import new_callid
from requests._dns import _cstr

comptime AT_FDCWD = -2 if CompilationTarget.is_macos() else -100
# Linux arm64 numbers O_DIRECTORY/O_NOFOLLOW differently from x86-64; its
# 0x10000/0x20000 are O_DIRECT/O_LARGEFILE.
comptime NOFOLLOW = 0x100 if CompilationTarget.is_macos() else (0x20000 if CompilationTarget.is_x86() else 0x8000)
comptime NONBLOCK = 0x4 if CompilationTarget.is_macos() else 0x800
comptime DIRECTORY = 0x100000 if CompilationTarget.is_macos() else (0x10000 if CompilationTarget.is_x86() else 0x4000)
comptime CREATE_EXCLUSIVE = (0x200 | 0x800) if CompilationTarget.is_macos() else (0x40 | 0x80)


def server_key(url: String) -> String:
    """Stable server identity without writing an address or credentials to disk."""
    var h = UInt64(14695981039346656037)
    for b in url.as_bytes():
        h = (h ^ UInt64(b)) * UInt64(1099511628211)
    return String(h)


def stdout_is_file() -> Bool:
    """Whether stdout is redirected to a regular file, which wants the whole
    reply rather than the bounded preview a pipe gets."""
    var buf = unsafe_alloc[UInt8](512)
    var rc = external_call["fstat", c_int](Int32(1), buf)
    comptime MODE_OFFSET = 4 if CompilationTarget.is_macos() else (24 if CompilationTarget.is_x86() else 16)
    var mode = Int(buf[unsafe_offset=MODE_OFFSET]) | (Int(buf[unsafe_offset=MODE_OFFSET + 1]) << 8)
    buf.unsafe_free()
    return rc == 0 and (mode & 0o170000) == 0o100000


def _private_fd(fd: Int32, directory: Bool) -> Bool:
    var buf = unsafe_alloc[UInt8](512)
    var rc = external_call["fstat", c_int](fd, buf)
    if rc != 0:
        buf.unsafe_free()
        return False
    comptime MODE_OFFSET = 4 if CompilationTarget.is_macos() else (24 if CompilationTarget.is_x86() else 16)
    comptime UID_OFFSET = 16 if CompilationTarget.is_macos() else (28 if CompilationTarget.is_x86() else 24)
    var mode = Int(buf[unsafe_offset=MODE_OFFSET]) | (Int(buf[unsafe_offset=MODE_OFFSET + 1]) << 8)
    var uid = UInt32(0)
    for i in range(4):
        uid |= UInt32(buf[unsafe_offset=UID_OFFSET + i]) << UInt32(8 * i)
    buf.unsafe_free()
    var expected = 0o040000 if directory else 0o100000
    return (mode & 0o170000) == expected and (mode & 0o077) == 0 and uid == external_call["getuid", UInt32]()


struct PrivateCache(Movable):
    var path: String
    var fd: Int32

    def __init__(out self) raises:
        self.fd = -1
        var base = getenv("XDG_CACHE_HOME")
        if base == "":
            base = getenv("HOME") + "/.cache"
        if not base.startswith("/"):
            raise Error("diagnostics cache requires an absolute XDG_CACHE_HOME")
        makedirs(base, exist_ok=True)
        self.path = base + "/eva-diagnostics"
        makedirs(self.path, mode=0o700, exist_ok=True)
        var path_c = _cstr(self.path)
        self.fd = external_call["openat", c_int, num_fixed_args=3](Int32(AT_FDCWD), path_c, Int32(NOFOLLOW | DIRECTORY))
        path_c.unsafe_free()
        if self.fd < 0:
            raise Error("cannot open private diagnostics cache (symlinks are refused)")
        if not _private_fd(self.fd, True):
            _ = external_call["close", c_int](self.fd)
            self.fd = -1
            raise Error("diagnostics cache must be owned by you with mode 700")

    def __deinit__(deinit self):
        if self.fd >= 0:
            _ = external_call["close", c_int](self.fd)

    def read(self, name: String) raises -> String:
        var name_c = _cstr(name)
        var fd = external_call["openat", c_int, num_fixed_args=3](self.fd, name_c, Int32(NOFOLLOW | NONBLOCK))
        name_c.unsafe_free()
        if fd < 0:
            return ""
        if not _private_fd(fd, False):
            _ = external_call["close", c_int](fd)
            return ""
        var bytes = List[UInt8]()
        var buf = unsafe_alloc[UInt8](8192)
        var failed = False
        while True:
            var n = external_call["read", Int](fd, buf, Int(8192))
            if n == 0:
                break
            if n < 0 or len(bytes) + n > 4194304:
                failed = True
                break
            for i in range(n):
                bytes.append(buf[unsafe_offset=i])
        buf.unsafe_free()
        _ = external_call["close", c_int](fd)
        if failed:
            return ""
        return String(from_utf8_lossy=Span(bytes))

    def write(self, name: String, text: String) raises -> String:
        """Exclusive temp + full write + fsync + rename; never follows a target."""
        var temp = ".pending-" + new_callid()
        var temp_c = _cstr(temp)
        var fd = external_call["openat", c_int, num_fixed_args=3](
            self.fd,
            temp_c,
            Int32(1 | NOFOLLOW | CREATE_EXCLUSIVE),
            UInt32(0o600),
        )
        if fd < 0:
            temp_c.unsafe_free()
            raise Error("cannot create private diagnostics cache file")
        var data = _cstr(text)
        var offset = 0
        var ok = True
        while offset < text.byte_length():
            var n = external_call["write", Int](fd, data.unsafe_offset(offset), text.byte_length() - offset)
            if n <= 0:
                ok = False
                break
            offset += n
        data.unsafe_free()
        if external_call["fsync", c_int](fd) != 0:
            ok = False
        _ = external_call["close", c_int](fd)
        var name_c = _cstr(name)
        if ok:
            ok = external_call["renameat", c_int](self.fd, temp_c, self.fd, name_c) == 0
        if not ok:
            _ = external_call["unlinkat", c_int](self.fd, temp_c, Int32(0))
        temp_c.unsafe_free()
        name_c.unsafe_free()
        if not ok:
            raise Error("cannot save diagnostics cache file")
        return self.path + "/" + name
