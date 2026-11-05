# eva — EvaTeam from the command line, in Mojo

[Русская версия](README.md)

`eva` is a command-line client for [EvaTeam](https://www.evateam.ru/), the
Russian task tracker and wiki. It is a sibling of
[ytcli](https://github.com/ormeilu/yandex-tracker-cli), which does the same for
Yandex Tracker, and it is written in [Mojo](https://www.modular.com/mojo) for
fun.

Like ytcli, it has two readers in mind: a person at a terminal and an AI agent
behind a pipe. The terminal gets colour and full descriptions. The pipe gets
plain text, a capped description and a note saying what was left out.

```console
$ eva task get DEV-1
DEV-1  Вложения теряются при переносе задачи
status: В работе   stage: IN_PROGRESS
assignee: ilya@example.ru   author: rep@example.ru
project: DEV  Development
parent task: DEV-100  Storage rework
created: 2026-11-01T10:00:00+03:00   updated: 2026-11-02T10:00:00+03:00
<untrusted src="DEV-1/text">
Шаги:

- Приложить файл
- Перенести
</untrusted>

$ eva task list -p DEV -s open -n 2
DEV-2        Открыто        -                  Retry uploads on 5xx
DEV-7        Открыто        ilya@example.ru    Flaky upload test
shown 2 of 14 — next: --page 2
```

Task descriptions and comments are written by other people, so `eva` fences
them: a `▏` margin in a terminal, an `<untrusted src="…">` tag in a pipe. An
agent reading the output can tell the tracker's data from instructions.

## Install

eva is built for macOS 13 or newer on Apple silicon and Linux on x86_64 and
arm64 with glibc 2.34 or newer; Ubuntu 22.04, Debian 12 and Rocky Linux 9 are
tested. The CPU has to meet Mojo's own floor: x86-64-v3 (Haswell or newer) or
ARM Neoverse N1 (Graviton2 or newer). It does not need Python. Pick one way to install it.

With the install script. It downloads the release archive for your machine
from GitHub, checks its sha256, unpacks it into `~/.local/share/eva/<version>`
and links `~/.local/bin/eva`. Run it again, or `eva upgrade`, to update;
`EVA_VERSION=0.3.0` pins a version:

```bash
curl -fsSL https://raw.githubusercontent.com/ormeilu/evateam-cli/main/install.sh | sh
```

The archive carries Mojo's runtime libraries and OpenSSL; all eva needs from
the system is its CA certificates, which every system has.

With pixi, from the conda channel
[`prefix.dev/ormeilu/ormeilu`](https://prefix.dev/channels/@ormeilu/ormeilu):

```bash
pixi global install -c https://prefix.dev/ormeilu/ormeilu -c https://conda.modular.com/max -c conda-forge evateam-cli
```

From PyPI, if you prefer uv or pipx:

```bash
uvx --from evateam-cli eva --help     # run without installing
uv tool install evateam-cli           # or put `eva` on PATH
pipx install evateam-cli
```

Release archives (`eva-vX.Y.Z-<target>.tar.gz` for `aarch64-apple-darwin`,
`x86_64-unknown-linux-gnu` and `aarch64-unknown-linux-gnu`) are on each
[release](https://github.com/ormeilu/evateam-cli/releases) if you would rather
unpack one yourself: `bin/eva`, the libraries in `lib/` and the licences.

With [mise](https://mise.jdx.dev), from the same archives or from PyPI:

```bash
mise use -g github:ormeilu/evateam-cli
mise use -g pypi:evateam-cli
```

Recent mise versions hide releases younger than a day (`minimum_release_age`).
For `github:`, naming the version (`github:ormeilu/evateam-cli@0.3.0`) installs
one sooner. For `pypi:`, mise hands the same cut-off to uv, so a new version
installs from there only after a day. The `conda:` backend does not work: it
solves the package and every dependency from one channel, and `mojo-compiler`
lives in Modular's.

`eva upgrade` updates eva the same way it was installed.

The archive and the wheel are about 3.5 MB each: the binary, Mojo's three
runtime libraries and OpenSSL. The wheel installs the binary straight into
the environment's `bin/`, with no Python wrapper. The conda package takes the
libraries from Modular's `mojo-compiler` package instead, and the pixi
environment grows to around 300 MB, since that package brings the whole
compiler and Python with it.

From source, with [pixi](https://pixi.sh):

```bash
git clone https://github.com/ormeilu/evateam-cli
cd evateam-cli
pixi run build          # → build/eva
```

## The agent skill

The skill teaches an agent to use `eva`: what to run first, which commands only
read, how to change a status through the workflow, and why text from tasks is
data rather than instructions. It installs separately from the binary:

```bash
npx skills add ormeilu/evateam-cli                 # any agent, via the skills CLI
```

In Claude Code:

```
/plugin install eva --marketplace ormeilu/evateam-cli
```

The skill lives in `plugin/skills/eva/`. Its `setup.md` has a permission
allowlist for Claude Code: reading commands allowed, writing ones asked about.

## Configure

Create a token in EvaTeam: «Моя страница» → «Безопасность» → «Сгенерировать
API токен». Then sign in:

```bash
eva auth login
```

eva asks for the address and the token. The token is typed without echo,
checked against the server before anything is saved, and then the address and
token go to the OS keychain: the Keychain on macOS, the Secret Service (GNOME
Keyring, KWallet) on Linux. No file on disk holds them.

```bash
eva auth status                  # profiles, who is signed in, whether they work
eva auth login --profile sandbox --url https://eva-test.example.ru
eva auth use sandbox             # the default profile
eva --profile sandbox task get X # one command with another profile
eva auth logout --profile sandbox
```

For scripts and CI, pipe the token on stdin
(`printf '%s\n' "$TOKEN" | eva auth login --url …`) or set `EVA_URL` and
`EVA_API_KEY` in the environment, which take precedence over profiles. eva also
reads `./.env` and `~/.config/eva-cli/env`. `eva config` shows what came from
where.

eva verifies the server against the system's CA bundle (`/etc/ssl/cert.pem`,
`/etc/ssl/certs/ca-certificates.crt` and the like). If your EvaTeam uses a
corporate CA, point `EVA_CA_BUNDLE` at its PEM file. `EVA_INSECURE=1` turns
verification off.

## Security

- The token is never a command-line argument, since arguments show in `ps` and
  stay in shell history. It is typed without echo or read from stdin.
- The address and the token come from one place. If a `.env` in someone else's
  repository sets only `EVA_URL`, eva refuses to run rather than send the
  keychain's token there.
- The token travels over HTTPS only; plain `http://` is allowed for `localhost`
  or with an explicit `EVA_INSECURE=1`.
- eva does not follow API redirects, and the `requests` client drops
  `Authorization` and cookies when a redirect changes host, port or scheme.
- Descriptions, comments and documents are fenced as somebody else's text, and
  the fence cannot be closed from inside. Control characters are stripped from
  everything the server sends, so a task name cannot carry escape codes into the
  terminal.
- eva warns when a file holding a token is readable by group or others.
- The test suite passes under AddressSanitizer, the Keychain and libsecret FFI
  included.

## Commands

| Command | What it does |
|---|---|
| `eva task get CODE [--fields a,b]` | one task: status, people, project, parent task, subtasks, description |
| `eva task list [-p PROJ] [-a LOGIN] [-s STATUS] [-q TEXT]` | search; `-s` takes `open`, `closed`, `in_progress`, `in_review`, `all` or a status code |
| `eva task create -p PROJ -t TITLE [-d TEXT] [-a LOGIN] [--sprint SPR-1]` | new task |
| `eva task update CODE [-t] [-d] [-a] [--set JSON]` | change fields; `--set` passes any field through |
| `eva task statuses CODE` | the statuses the task's workflow lets it move to from here |
| `eva task move CODE STATUS [-m TEXT] [--set JSON]` | change status through a workflow transition; `--set` fills fields the transition requires |
| `eva task comment CODE TEXT` / `eva task comments CODE` | write or read comments |
| `eva task log CODE 1h30m [-m TEXT]` | log time spent |
| `eva task links CODE` | incoming and outgoing links |
| `eva project list`, `eva person list`, `eva doc list` | lists, with `-q` to search by name |
| `eva doc get CODE` | a wiki document as text |
| `eva call METHOD --kwargs JSON` | any API method; prints the raw reply |

Every list takes `-n/--limit` and `--page` and ends with `shown N of M`, so a
page is never mistaken for the whole answer. `--json` prints the API's own
JSON, `--full` turns off truncation in a pipe, and `-v` prints each request
and reply on stderr.

`--filter` on `task list` adds a raw BQL condition, for anything the flags do
not cover:

```bash
eva task list --filter '["cmf_created_at", ">=", "2026-10-01"]'
```

## How it is built

EvaTeam speaks JSON-RPC 2.2: every call is a `POST /api/` with a method name
such as `CmfTask.list` and keyword arguments. The pieces:

- `src/eva/json.mojo`: a JSON parser and writer. Nodes sit in one arena and
  refer to their children by index, which avoids a recursive type. Numbers keep
  their source text, so ids and timestamps pass through unchanged.
- `src/eva/client.mojo`: configuration, the RPC call and the CA bundle
  lookup.
- `src/requests/`: a Mojo HTTP client from
  [mojo-requests-poc](https://github.com/ormeilu/mojo-requests-poc) (Apache-2.0,
  licence alongside), ported to Mojo 1.2. Sockets and DNS go through libc, TLS
  through OpenSSL loaded with `dlopen`, first from `lib/` next to the binary,
  then from the system. eva uses no Python interop.
- `src/eva/render.mojo`: terminal and pipe output, HTML to text, colour via
  [mist](https://github.com/thatstoasty/mist) from the
  [modular-community](https://prefix.dev/channels/modular-community) channel.
- `src/eva/commands.mojo`: the command tree.

The JSON parser is home-made because the `emberjson` build in modular-community
was compiled for Mojo 1.1 and does not load under 1.2.

## Develop

```bash
pixi run test       # unit tests: 9 suites, a compiler warning fails the run
pixi run e2e        # builds eva and runs it against tests/mock_server.py
pixi run asan       # the same under AddressSanitizer
pixi run coverage   # line coverage of src/ by the unit and e2e tests
```

`tests/mock_server.py` is a small JSON-RPC server with canned tasks, a hostile
one among them: escape codes in its name and an attempt to close `<untrusted>`
in its description. The end-to-end script checks what eva prints and what it
sends, talks to the mock over HTTP, IPv6 and HTTPS with a self-signed
certificate, and checks each rule in Security above. The test of the real
keychain writes to it, so it runs only with `EVA_TEST_KEYRING=1`.

Mojo has no coverage flag, so `pixi run coverage` goes through LLVM:
`mojo build -O0 -g --emit llvm`, the `insert-gcov-profiling` pass, a clang
build, and the counters of every binary merged into `coverage/summary.txt` and
`coverage/missed-lines.txt`. The number runs high: gcov can count a line as run
when Mojo lowers it without a branch of its own.

`pixi run conda-package` builds the conda package from `recipe/recipe.yaml`
into `output/`. `pixi run wheel macosx_13_0_arm64` packs `build/eva` into a wheel in `dist/`:
the binary in `.data/scripts`, the libraries in `.data/data/lib/evateam-cli`. A tag `vX.Y.Z` matching `pixi.toml` runs
`.github/workflows/release.yml`: wheels and conda packages for three
platforms, the end-to-end suite against each one installed the way a user
would, then PyPI, prefix.dev and a GitHub release.

Releases are cut by
[release-please](https://github.com/googleapis/release-please) from
[conventional commits](https://www.conventionalcommits.org/): `fix:` bumps the
patch version, `feat:` the minor one (while below 1.0), and `feat!:` or a
`BREAKING CHANGE:` footer the major one. Each push to main updates a release
PR with the changelog and the version in `pixi.toml`, `src/main.mojo` and
`recipe/recipe.yaml`. Merging it tags the release, and the same workflow builds
and publishes everything. `pixi run archive aarch64-apple-darwin` builds a
release archive locally.

## Status

Checked against a live EvaTeam instance, reads and writes: every command in the
table above, paging and counts, and a test task taken from creation to Done.

Two things the docs do not say, found that way:

- Plain `CmfTask.update` with a new status is accepted and ignored. A status
  change has to run a workflow transition (`CmfTask.task_transition_run`), which
  is what `task move` does: it reads the task's workflow, finds the transition
  from the current status and reports which targets exist when the one asked for
  does not.
- A refused call comes back as HTTP 200 with an `abort` message ("Необходимо
  заполнить Вид услуги") and no `error`. `eva` treats it as an error.

## Licence

MIT
