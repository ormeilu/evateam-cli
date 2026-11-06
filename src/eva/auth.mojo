"""`eva auth`: sign in once, keep the address and token in the OS keychain.

    eva auth login [--profile NAME] [--url URL] [--insecure]
    eva auth status
    eva auth use NAME
    eva auth logout [--profile NAME]

The token is typed without echo, or piped on stdin for scripts; it is never an
argument, since arguments show in `ps` and in shell history.
"""

from std.os import getenv
from std.sys import stderr

from eva.args import Args
from eva.client import Client, Config, load_config, normalize_url, secret_json
from eva.keyring import keyring_delete, keyring_name, keyring_set
from eva.profiles import check_profile_name, load_profiles, save_profiles
from eva.render import Out
from eva.term import prompt_line, prompt_secret, stdin_is_tty


def whoami(cfg: Config) raises -> String:
    """`login (name)` of the token's owner; raises if the server refuses it."""
    var client = Client(cfg.copy(), False)
    var r = client.call("CmfPerson.get_current_user", '{"fields": ["login", "name"]}')
    var login = r.doc.text_at(r.result, "login")
    if login == "":
        raise Error("the server did not say who this token belongs to")
    var name = r.doc.text_at(r.result, "name")
    return login + (" (" + name + ")" if name != "" else "")


comptime TOKEN_DOCS = "https://docs.evateam.ru/docs/DOC-000200"

comptime TOKEN_GUIDE = (
    "eva signs in with your EvaTeam address and an API token. To create the token:\n"
    "  1. In EvaTeam, open «Моя страница» and the «Безопасность» tab.\n"
    "  2. Click «Сгенерировать API токен», then «Создать токен API».\n"
    "  3. Give it a name and an expiry date, and create it.\n"
    "  4. Copy the token now: EvaTeam shows it once and keeps only its hash.\n"
    "Step by step, with screenshots: " + TOKEN_DOCS + "\n"
)


def auth_login(args: Args, ui: Out) raises:
    args.check_known(["profile", "url", "insecure", "verbose", "v"])
    var profiles = load_profiles()
    var profile = args.get("profile")
    if profile == "":
        profile = profiles.default if profiles.default != "" else String("default")
    check_profile_name(profile)
    var insecure = args.has("insecure")

    # In a terminal, the whole procedure first, before anyone goes looking
    # for a token halfway through the questions.
    if stdin_is_tty():
        print(TOKEN_GUIDE, file=stderr)
    var url = args.get("url")
    if url == "":
        url = prompt_line("EvaTeam address, e.g. https://eva.company.ru: ")
    url = normalize_url(url, insecure)
    if url == "":
        raise Error("no address given")
    var token = prompt_secret("API token (typed hidden): ")
    if token == "":
        raise Error("no token given; how to create one: " + TOKEN_DOCS)

    var cfg = Config()
    cfg.url = url
    cfg.token = token
    cfg.insecure = insecure
    var who: String
    try:
        who = whoami(cfg)
    except e:
        raise Error("not saved: " + String(e))

    keyring_set(profile, secret_json(url, token, insecure))
    profiles.add(profile)
    save_profiles(profiles)
    print("signed in to " + url + " as " + ui.bold(who))
    print(
        "saved in " + keyring_name() + " as profile '" + profile + "'"
        + (" (the default)" if profiles.default == profile else "")
    )
    if getenv("EVA_URL") != "" or getenv("EVA_API_KEY") != "":
        print(
            ui.dim(
                "note: EVA_URL/EVA_API_KEY in the environment take precedence over"
                " profiles until they are unset"
            )
        )


def auth_status(args: Args, ui: Out) raises:
    args.check_known(["verbose", "v"])
    var active = load_config("")
    print("in use: " + (active.url if active.url != "" else "(nothing)") + "  from " + active.source)
    var profiles = load_profiles()
    if len(profiles.names) == 0:
        print(ui.dim("no saved profiles; `eva auth login` creates one"))
        return
    for name in profiles.names:
        var mark = "*" if name == profiles.default else " "
        var line = mark + " " + name + "  "
        try:
            var cfg = load_config(name)
            line += cfg.url + "  " + whoami(cfg)
        except e:
            line += ui.dim("error: " + String(e))
        print(line)
    print(ui.dim("* is the default; --profile NAME or EVA_PROFILE picks another"))


def auth_use(args: Args, ui: Out) raises:
    args.check_known(["verbose", "v"])
    var name = args.need(2, "profile name")
    check_profile_name(name)
    var profiles = load_profiles()
    if not profiles.has(name):
        raise Error("no profile '" + name + "'; `eva auth status` lists them")
    profiles.default = name
    save_profiles(profiles)
    print("default profile: " + name)


def auth_logout(args: Args, ui: Out) raises:
    args.check_known(["profile", "verbose", "v"])
    var profiles = load_profiles()
    var profile = args.get("profile")
    if profile == "":
        profile = profiles.default if profiles.default != "" else String("default")
    check_profile_name(profile)
    var removed = keyring_delete(profile)
    var listed = profiles.has(profile)
    profiles.remove(profile)
    save_profiles(profiles)
    if not removed and not listed:
        raise Error("no profile '" + profile + "' to remove")
    print("signed out: profile '" + profile + "' removed from " + keyring_name())
    if profiles.default != "":
        print("default profile is now '" + profiles.default + "'")
