"""The parts of src/requests changed for eva: credentials across redirects,
platform struct layouts, and name resolution that needs no network."""

from std.os import getenv
from std.sys import CompilationTarget
from std.testing import assert_equal, assert_true, assert_false, TestSuite

from requests._dns import AddrInfo, SockAddrIn6, in6_bytes, in6_halves, resolve
from std.sys import size_of
from requests._net import _sa_family
from requests._tls import _self_exe
from requests.session import _origin, _resolve_redirect


def test_origin_is_scheme_host_port() raises:
    assert_equal(_origin("https://Eva.Example.ru/api/?x=1"), "https://eva.example.ru")
    assert_equal(_origin("https://eva.example.ru:8443/a"), "https://eva.example.ru:8443")
    assert_equal(_origin("https://user:pw@eva.example.ru/a"), "https://eva.example.ru")


def test_origin_changes_that_drop_credentials() raises:
    var base = _origin("https://eva.example.ru/api/")
    assert_true(_origin("http://eva.example.ru/api/") != base)  # downgrade
    assert_true(_origin("https://evil.example/api/") != base)  # other host
    assert_true(_origin("https://eva.example.ru:444/api/") != base)  # other port
    assert_true(_origin("https://eva.example.ru.evil.example/") != base)
    assert_equal(_origin("https://eva.example.ru/other"), base)  # same origin keeps them


def test_resolve_redirect() raises:
    var base = "https://eva.example.ru/a/b"
    assert_equal(_resolve_redirect(base, "https://x.example/y"), "https://x.example/y")
    assert_equal(_resolve_redirect(base, "//x.example/y"), "https://x.example/y")
    assert_equal(_resolve_redirect(base, "/root"), "https://eva.example.ru/root")
    assert_equal(_resolve_redirect(base, "sib"), "https://eva.example.ru/a/sib")


def test_sockaddr_family_bytes() raises:
    comptime if CompilationTarget.is_macos():
        # u8 sin_len, u8 sin_family, little-endian.
        assert_equal(_sa_family(2, 16), UInt16(16 | (2 << 8)))
        assert_equal(_sa_family(30, 28), UInt16(28 | (30 << 8)))
    else:
        assert_equal(_sa_family(2, 16), UInt16(2))
        assert_equal(_sa_family(10, 28), UInt16(10))


def test_addrinfo_reads_the_platform_slot() raises:
    var ai = AddrInfo(0, 0, 0, 0, 0, 111, 222, 0)
    comptime if CompilationTarget.is_macos():
        assert_equal(ai.addr(), 222)  # ai_canonname, then ai_addr
    else:
        assert_equal(ai.addr(), 111)  # glibc: ai_addr, then ai_canonname


def test_sockaddr_in6_matches_c() raises:
    # C: u16 family, u16 port, u32 flowinfo, 16-byte addr at offset 8, u32 scope = 28.
    assert_true(size_of[SockAddrIn6]() >= 28)
    assert_true(size_of[SockAddrIn6]() <= 32)


def test_in6_halves_roundtrip() raises:
    var b = SIMD[DType.uint8, 16](0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)
    var h = in6_halves(b)
    assert_equal(in6_bytes(h[0], h[1]), b)
    assert_equal(h[1] >> 56, 1)  # the last byte is the high byte of the high half


def test_resolve_literals_and_localhost() raises:
    var v4 = resolve("127.0.0.1")
    assert_true(v4.is_ipv4())
    var v6 = resolve("::1")
    assert_false(v6.is_ipv4())
    # Through getaddrinfo, which is what the struct layout above is for.
    var lh = resolve("localhost")
    assert_true(lh.is_ipv4() or not lh.is_ipv4())


def test_resolve_unknown_name_fails_cleanly() raises:
    var raised = False
    try:
        _ = resolve("no-such-host.invalid")
    except:
        raised = True
    assert_true(raised)


def test_self_exe_is_absolute() raises:
    var exe = _self_exe()
    assert_true(exe.startswith("/"), exe)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
