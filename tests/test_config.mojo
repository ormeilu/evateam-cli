"""Configuration and profiles. Every test runs in a fresh temporary directory
with HOME pointed at it, so nothing touches the real ~/.config or ./.env."""

from std.ffi import external_call, c_int
from std.os import getenv, setenv, unsetenv, makedirs
from std.testing import assert_equal, assert_true, assert_false, assert_raises, TestSuite

from eva.client import (
    Config,
    _group_or_world_readable,
    _take_pair,
    ca_bundle,
    load_config,
    new_callid,
    normalize_url,
    url_host,
    secret_json,
)
from eva.json import JsonDoc
from eva.profiles import Profiles, load_profiles, save_profiles, valid_profile_name, check_profile_name
from requests._dns import _cstr

comptime ENV_VARS = (
    "EVA_URL,EVA_API_KEY,EVA_TOKEN,EVA_PROFILE,EVA_INSECURE,EVA_CA_BUNDLE,REQUESTS_CA_BUNDLE,SSL_CERT_FILE"
)


def sandbox() raises -> String:
    """A new empty directory, made the cwd and HOME, with eva's env cleared."""
    var template = _cstr("/tmp/eva-test-XXXXXX")
    var made = external_call["mkdtemp", Int](template)
    var path = String()
    var i = 0
    while template[unsafe_offset=i] != 0:
        path += chr(Int(template[unsafe_offset=i]))
        i += 1
    template.unsafe_free()
    if made == 0:
        raise Error("mkdtemp failed")
    var c = _cstr(path)
    _ = external_call["chdir", c_int](c)
    c.unsafe_free()
    _ = setenv("HOME", path)
    for name in ENV_VARS.split(","):
        _ = unsetenv(String(name))
    return path


def write(path: String, text: String) raises:
    with open(path, "w") as f:
        f.write(text)


def chmod(path: String, mode: Int):
    var c = _cstr(path)
    _ = external_call["chmod", c_int](c, UInt16(mode))
    c.unsafe_free()


# ---- normalize_url ----


def test_normalize_adds_https_and_trims() raises:
    assert_equal(normalize_url("eva.example.ru", False), "https://eva.example.ru")
    assert_equal(normalize_url("https://eva.example.ru/", False), "https://eva.example.ru")
    assert_equal(normalize_url("https://eva.example.ru/api/", False), "https://eva.example.ru")
    assert_equal(normalize_url("  https://eva.example.ru/api  ", False), "https://eva.example.ru")
    assert_equal(normalize_url("", False), "")


def test_normalize_refuses_plain_http() raises:
    with assert_raises(contains="plain http"):
        _ = normalize_url("http://eva.example.ru", False)
    assert_equal(normalize_url("http://eva.example.ru", True), "http://eva.example.ru")
    assert_equal(normalize_url("http://localhost:8080", False), "http://localhost:8080")
    assert_equal(normalize_url("http://127.0.0.1:9", False), "http://127.0.0.1:9")
    assert_equal(normalize_url("http://[::1]:9", False), "http://[::1]:9")


def test_url_host() raises:
    assert_equal(url_host("https://User@Eva.Example.RU:8443/api?x#y"), "eva.example.ru")
    assert_equal(url_host("http://[::1]:9/"), "[::1]")
    assert_equal(url_host("http://localhost"), "localhost")


def test_normalize_localhost_prefix_is_not_a_bypass() raises:
    # Only the host itself counts, not a name that merely starts like it.
    with assert_raises(contains="plain http"):
        _ = normalize_url("http://localhost.attacker.example", False)
    with assert_raises(contains="plain http"):
        _ = normalize_url("http://127.0.0.1.attacker.example", False)
    with assert_raises(contains="plain http"):
        _ = normalize_url("http://localhost@attacker.example", False)
    with assert_raises(contains="plain http"):
        _ = normalize_url("http://localhost:80@attacker.example/", False)


# ---- the pair rule ----


def test_take_pair() raises:
    var cfg = Config()
    assert_false(_take_pair(cfg, "", "", "x"))
    with assert_raises(contains="sets EVA_URL but not EVA_API_KEY"):
        _ = _take_pair(cfg, "https://a", "", "./.env")
    with assert_raises(contains="sets EVA_API_KEY but not EVA_URL"):
        _ = _take_pair(cfg, "", "t", "./.env")
    assert_true(_take_pair(cfg, "https://a", "t", "here"))
    assert_equal(cfg.source, "here")


def test_env_pair() raises:
    _ = sandbox()
    _ = setenv("EVA_URL", "eva.example.ru/api")
    _ = setenv("EVA_API_KEY", "tok")
    var cfg = load_config()
    assert_equal(cfg.url, "https://eva.example.ru")
    assert_equal(cfg.token, "tok")
    assert_equal(cfg.source, "the environment")


def test_env_token_alias() raises:
    _ = sandbox()
    _ = setenv("EVA_URL", "https://e")
    _ = setenv("EVA_TOKEN", "tok2")
    assert_equal(load_config().token, "tok2")


def test_env_half_pair_is_refused() raises:
    _ = sandbox()
    _ = setenv("EVA_URL", "https://e")
    with assert_raises(contains="but not EVA_API_KEY"):
        _ = load_config()


def test_dotenv_pair_and_quotes() raises:
    _ = sandbox()
    write(".env", "# comment\nexport EVA_URL='https://e.example'\nEVA_API_KEY=\"tok\"\nOTHER=1\n")
    var cfg = load_config()
    assert_equal(cfg.url, "https://e.example")
    assert_equal(cfg.token, "tok")
    assert_equal(cfg.source, "./.env")


def test_hostile_dotenv_cannot_borrow_a_token() raises:
    var home = sandbox()
    write(".env", "EVA_URL=https://attacker.example\n")
    makedirs(home + "/.config/eva-cli", exist_ok=True)
    write(home + "/.config/eva-cli/env", "EVA_URL=https://good.example\nEVA_API_KEY=secret\n")
    with assert_raises(contains="./.env sets EVA_URL but not EVA_API_KEY"):
        _ = load_config()


def test_unrelated_dotenv_is_ignored() raises:
    var home = sandbox()
    write(".env", "DATABASE_URL=postgres://x\n")
    makedirs(home + "/.config/eva-cli", exist_ok=True)
    write(home + "/.config/eva-cli/env", "EVA_URL=https://good.example\nEVA_API_KEY=secret\n")
    chmod(home + "/.config/eva-cli/env", 0o600)
    var cfg = load_config()
    assert_equal(cfg.url, "https://good.example")
    assert_equal(cfg.source, "~/.config/eva-cli/env")


def test_environment_beats_dotenv() raises:
    _ = sandbox()
    write(".env", "EVA_URL=https://file.example\nEVA_API_KEY=f\n")
    _ = setenv("EVA_URL", "https://env.example")
    _ = setenv("EVA_API_KEY", "e")
    assert_equal(load_config().url, "https://env.example")


def test_insecure_from_file() raises:
    _ = sandbox()
    write(".env", "EVA_URL=http://plain.example\nEVA_API_KEY=t\nEVA_INSECURE=1\n")
    var cfg = load_config()
    assert_true(cfg.insecure)
    assert_equal(cfg.url, "http://plain.example")


def test_plain_http_from_file_is_refused() raises:
    _ = sandbox()
    write(".env", "EVA_URL=http://plain.example\nEVA_API_KEY=t\n")
    with assert_raises(contains="plain http"):
        _ = load_config()


def test_nothing_configured() raises:
    _ = sandbox()
    var cfg = load_config()
    assert_equal(cfg.url, "")
    assert_equal(cfg.source, "nothing")


def test_profile_name_is_validated_before_use() raises:
    _ = sandbox()
    _ = setenv("EVA_PROFILE", "../../etc")
    with assert_raises(contains="not allowed"):
        _ = load_config()


def test_world_readable_token_file() raises:
    var home = sandbox()
    write(home + "/f", "x")
    chmod(home + "/f", 0o644)
    assert_true(_group_or_world_readable(home + "/f"))
    chmod(home + "/f", 0o600)
    assert_false(_group_or_world_readable(home + "/f"))


# ---- secrets, CA bundle, callid ----


def test_secret_json() raises:
    var d = JsonDoc()
    var r = d.parse(secret_json("https://e", 'to"k', False))
    assert_equal(d.text_at(r, "url"), "https://e")
    assert_equal(d.text_at(r, "token"), 'to"k')
    assert_equal(d.text_at(r, "insecure"), "")
    var r2 = d.parse(secret_json("https://e", "t", True))
    assert_equal(d.text_at(r2, "insecure"), "true")


def test_ca_bundle_order() raises:
    _ = sandbox()
    _ = setenv("SSL_CERT_FILE", "/c")
    _ = setenv("REQUESTS_CA_BUNDLE", "/b")
    _ = setenv("EVA_CA_BUNDLE", "/a")
    assert_equal(ca_bundle(), "/a")
    _ = unsetenv("EVA_CA_BUNDLE")
    assert_equal(ca_bundle(), "/b")
    _ = unsetenv("REQUESTS_CA_BUNDLE")
    assert_equal(ca_bundle(), "/c")
    _ = unsetenv("SSL_CERT_FILE")
    # Falls back to a bundle the system has (or "" where it has none).
    var system = ca_bundle()
    assert_true(system == "" or system.startswith("/etc/"))


def test_callid_is_unique() raises:
    var a = new_callid()
    var b = new_callid()
    assert_true(a.startswith("eva-"))
    assert_true(a != b)


# ---- profiles ----


def test_profile_names() raises:
    for good in ["default", "s7", "work.prod", "a_b-c", "A1"]:
        assert_true(valid_profile_name(String(good)), String(good))
    for bad in ["", "a b", "../x", "a/b", "x;rm", "名前", "a" * 65]:
        assert_false(valid_profile_name(String(bad)), String(bad))
    with assert_raises(contains="not allowed"):
        check_profile_name("a b")


def test_profiles_default_follows_changes() raises:
    var p = Profiles()
    p.add("one")
    p.add("two")
    p.add("one")
    assert_equal(len(p.names), 2)
    assert_equal(p.default, "one")
    p.remove("one")
    assert_equal(p.default, "two")
    p.remove("two")
    assert_equal(p.default, "")


def test_profiles_roundtrip() raises:
    _ = sandbox()
    var p = Profiles()
    p.add("s7")
    p.add("sandbox")
    p.default = "sandbox"
    save_profiles(p)
    var q = load_profiles()
    assert_equal(q.default, "sandbox")
    assert_equal(len(q.names), 2)
    assert_true(q.has("s7"))


def test_profiles_file_ignores_junk() raises:
    var home = sandbox()
    makedirs(home + "/.config/eva-cli", exist_ok=True)
    write(home + "/.config/eva-cli/profiles", "garbage\nprofile=ok\nprofile=bad name\ndefault=../x\n")
    var q = load_profiles()
    assert_equal(len(q.names), 1)
    assert_equal(q.default, "ok")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
