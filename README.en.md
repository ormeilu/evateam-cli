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

Once a day eva checks for a newer release, in a background process that
commands never wait for. It asks GitHub's `/releases/latest`, the same address
the install script reads, and sends neither the token nor the EvaTeam address.
When a newer version is out, a command prints one line on stderr, at most once
a day per version: `eva 0.10.0 is out (you have 0.9.0); update with: eva upgrade`.
`eva --version` and `eva context` show that line every time; stdout of other
commands stays as it was. A failed check prints nothing. `EVA_NO_UPDATE_CHECK=1`
turns the check off, it never runs when `CI` is set, and `EVA_UPDATE_CHECK_HOURS=6`
checks every six hours instead.

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

First create an API token in EvaTeam ([EvaTeam's guide, in Russian](https://docs.evateam.ru/docs/DOC-000200)):

1. Open «Моя страница» (My page) and its «Безопасность» (Security) tab.
2. Click «Сгенерировать API токен», then «Создать токен API».
3. Give it a name and an expiry date, and create it.
4. Copy the token at once: EvaTeam shows it a single time and keeps only its hash.

<details>
<summary>Screenshots from EvaTeam's documentation</summary>

<img src="https://docs.evateam.ru/files/obj/CmfDocument/CmfDocument%3A8de0005e-5913-11ed-91cf-cf78a90a1ccb/image-20230807-161836.png?version=1" alt="«Моя страница»" width="300">

<img src="https://docs.evateam.ru/files/obj/CmfDocument/CmfDocument%3A8de/CmfDocument%3A8de0005e-5913-11ed-91cf-cf78a90a1ccb/image-mce-20260527-115633583.png?version=1" alt="the «Безопасность» tab" width="700">

<img src="https://docs.evateam.ru/files/obj/CmfDocument/CmfDocument%3A8de/CmfDocument%3A8de0005e-5913-11ed-91cf-cf78a90a1ccb/image-mce-20260527-115842904.png?version=1" alt="«Сгенерировать API токен»" width="700">

<img src="https://docs.evateam.ru/files/obj/CmfDocument/CmfDocument%3A8de/CmfDocument%3A8de0005e-5913-11ed-91cf-cf78a90a1ccb/image-mce-20260527-120135821.png?version=1" alt="«Создать токен API»" width="600">

<img src="https://docs.evateam.ru/files/obj/CmfDocument/CmfDocument%253A8de0005e-5913-11ed-91cf-cf78a90a1ccb/image-20230317-122341.png" alt="the new token" width="600">

<img src="https://docs.evateam.ru/files/obj/CmfDocument/CmfDocument%3A8de/CmfDocument%3A8de0005e-5913-11ed-91cf-cf78a90a1ccb/image-mce-20260527-120731383.png?version=1" alt="the token panel" width="700">

</details>

Then sign in (in a terminal, `eva auth login` repeats these steps first):

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
- The update check talks to GitHub alone, with no credentials and no EvaTeam
  address. It keeps its state in the same private cache as the schema files,
  and only digits, letters, dots and dashes of the version it reads reach the
  terminal.
- The test suite passes under AddressSanitizer, the Keychain and libsecret FFI
  included.

## Commands

| Command | What it does |
|---|---|
| `eva task get CODE [--fields a,b] [--with comments,attachments,links\|all]` | task card; priority, planning, participants, tags, lists and checklist counts |
| `eva task list [-p PROJ] [-a LOGIN\|me] [-s STATUS] [-q TEXT]` | name search; --author, --watching, --waiting-for LOGIN\|me, --archived |
| `eva task create -p PROJ -t TITLE [-d TEXT\|-F FILE] [--template CODE]` | create; --parent CODE, --type TYPE, --sprint CODE, --set JSON |
| `eva task update CODE [-t TITLE] [-d TEXT\|-F FILE] [-a LOGIN\|me] [--set JSON]` | replace requested fields; -s STATUS moves after the field update |
| `eva task delete CODE [--yes]` | confirm first; --yes is required without a terminal |
| `eva task move CODE STATUS [--path] [--resolution CODE] [--set JSON] [-m TEXT]` | run workflow transitions, stopping on a refusal |
| `eva task statuses CODE` | where this task can move from here |
| `eva task path CODE STATUS` | show a workflow route without moving |
| `eva task comment CODE TEXT\|-F FILE [--reply-to ID] [--attach FILE...]` | plain text, --md or --html; uploads belong to the new comment |
| `eva task comments CODE [--human] [--ids] [-n 20] [--page 1] [--all]` | newest window, chronological inside it; page 2 is earlier |
| `eva task comment-edit ID TEXT\|-F FILE [--md\|--html]` | edit a comment; the server controls its edited marker |
| `eva task comment-delete ID` | hide a comment; the server keeps a deleted-comment entry |
| `eva task log CODE 1h30m [-m TEXT] [--date D] [--at HH:MM]` | log time ending now or on a selected day |
| `eva task history CODE [-n 25] [--page 1]` | status transitions, newest first |
| `eva task time CODE [--all] [-n 25] [--page 1]` | visible actual work log; --all includes planned/draft entries |
| `eva task dev CODE` | linked repositories, branches, commits and merge requests |
| `eva task links CODE` | incoming/outgoing links and their relation types |
| `eva task link CODE OTHER [--type relates\|CODE\|NAME]` | create a typed link; duplicate calls are no-ops |
| `eva task unlink CODE OTHER [--type relates\|CODE\|NAME]` | remove only matching links of this type; absent links are a no-op |
| `eva task checklist CODE [-n 25] [--page 1]` | checklists and paginated items |
| `eva task check CHLI-1 [--undo]` | DONE, or OPEN with --undo |
| `eva task watch CODE [--login LOGIN]` | watch as yourself by default |
| `eva task unwatch CODE [--login LOGIN]` | remove that watcher, idempotently |
| `eva task attachments CODE` | list files attached to a task |
| `eva task attach CODE FILE [FILE...] [--force]` | upload; refuse existing names unless --force replaces them |
| `eva task bulk set --filter BQL --set JSON [--yes] [--dry-run]` | resolve the set first; preview by default, continue after per-task failures |
| `eva task bulk move STATUS --filter BQL [--path] [--set JSON] [--yes]` | workflow changes on the resolved set, not an atomic transaction |
| `eva time list [--from D] [--to D] [-a LOGIN]` | daily work log against the working calendar; this week by default |
| `eva time report --from D --to D [-p PROJ] [-a LOGIN\|me]` | visible totals by project and entry start-date; actual/planned/other minutes |
| `eva time log CODE 1h30m [--date D] [--at HH:MM]` | alias for task log |
| `eva time delete TTH-1` | delete a work-log entry |
| `eva attachment get ATT-1` | metadata and extracted text |
| `eva attachment download ATT-1 [-o PATH\|-] [--force]` | original bytes; no overwrite without --force |
| `eva attachment delete ATT-1 [--yes]` | confirm removal; does not claim stored bytes were erased |
| `eva project list [-q TEXT]` | project codes and names |
| `eva project get CODE` | owner, direct role assignments and project lists, not expanded effective membership |
| `eva person list [-q TEXT]` | people: login, name, email |
| `eva doc list [-q TEXT]` | wiki documents by name |
| `eva doc get CODE [--version OPAQUE_VERSION]` | published text, or an exact historical doc_version; not ordinal revision 3 |
| `eva doc create -t TITLE --parent CODE [-d TEXT\|-F FILE] [--publish]` | create a draft; publish only when explicitly requested |
| `eva doc update CODE [-t TITLE] [-d TEXT\|-F FILE] [--publish]` | update a draft |
| `eva doc publish CODE` | publish the current draft and verify its text |
| `eva doc comment CODE TEXT\|-F FILE [--reply-to ID] [--attach FILE...]` | same text/reply/file rules as task comments |
| `eva doc comment-edit ID TEXT\|-F FILE` | edit a document comment |
| `eva doc comments CODE [--human] [--ids] [-n 20] [--page 1] [--all]` | same window and fencing as task comments |
| `eva doc attachments CODE` | files attached to a document |
| `eva doc attach CODE FILE [FILE...] [--force]` | same upload safeguards as task attach |
| `eva doc download-all CODE [-o DIR] [--force]` | every attachment into a directory, one download each, no server-side archive |
| `eva doc children CODE [--depth 1] [-n 25] [--page 1]` | document-only children; paginated per parent, depth capped at 10 |
| `eva doc history CODE [-n 25] [--page 1]` | opaque version strings and history IDs, newest first |
| `eva doc followers CODE [-n 25] [--page 1]` | explicit followers only, not viewers or implicit recipients |
| `eva doc watch CODE [--children] [--off] [--dry-run]` | follow a document as yourself; `--children` adds the pages under it, `--off` stops |
| `eva sprint list [-p PROJ] [-s open\|closed\|all]` | discover sprint codes |
| `eva sprint get CODE [-n 25] [--page 1]` | sprint metadata and its tasks |
| `eva sprint add CODE TASK [TASK...]` | append tasks without replacing their other sprints |
| `eva release list [-p PROJ] [-s open\|closed\|all]` | discover release codes |
| `eva release get CODE [-n 25] [--page 1]` | release metadata and its tasks |
| `eva release add CODE TASK [TASK...]` | append tasks without replacing their other releases |
| `eva relation types [-n 25] [--page 1]` | relation codes and names |
| `eva tag list [-q TEXT]` | tag names; task update --tag replaces the tag set |
| `eva component list [-p PROJ] [-q TEXT]` | project-scoped components; task list --component NAME |
| `eva filter list [-q TEXT] [-p PROJ]` | your saved BQL filters; task list --filter CODE\|NAME executes stored JSON BQL |
| `eva notify list [-n 25] [--page 1] [--all]` | your unread notifications; --all includes read rows |
| `eva repo list [-q TEXT]` | repository code, name and URL |
| `eva search TEXT [-t task\|doc\|all] [-p PROJ] [-n 25] [--page 1]` | substring over name OR text; the page limit applies to each type |
| `eva testcase list [-p PROJ] [-q TEXT]` | test cases |
| `eva testcase get CODE [-n 25] [--page 1]` | version, steps, pre/postcondition sections and expected results |
| `eva testplan list [-p PROJ] [-q TEXT]` | test plans |
| `eva testplan get CODE [-n 25] [--page 1]` | plan metadata and paginated testcase membership |
| `eva ticket get CODE [-n 25] [--page 1]` | native SLA cycles, raw duration units; queue membership is not guessed |
| `eva trash list [-p PROJ] [-n 25] [--page 1]` | deleted tasks; displayed timestamp is last-modified, not a retention promise |
| `eva trash restore CODE [--yes]` | restore a deleted task after confirmation |
| `eva field list [-q TEXT]` | custom task fields |
| `eva field get NAME` | values of a custom choice or multi-select |
| `eva resolution list` | resolution codes and names |
| `eva schema CmfTask [-q TEXT] [--relations] [--refresh]` | filtered cached metadata; schema --classes lists known model names |
| `eva context` | read-only orientation: account, visible projects and recent activity |
| `eva cheatsheet` | copy-paste recipes without signing in |
| `eva call METHOD [--kwargs JSON] [--args JSON] [--flags JSON]` | raw JSON-RPC result; oversized piped replies spill to a private file |
| `eva auth login [--profile NAME] [--url URL]` | read the token hidden or on stdin; save only to the OS keychain |
| `eva auth status` | account and saved profiles |
| `eva auth use NAME` | select the default profile |
| `eva auth logout [--profile NAME]` | remove a saved profile |
| `eva config` | configuration source; never prints the token |
| `eva upgrade` | update through the original installation method |

Lists are paginated. `task comments` starts with the newest window of 20,
oldest-to-newest inside that window; `--page 2` goes earlier and `--all` fetches
the full bounded set. `--cols … --format tsv` prints data rows only.
`task get/list --fields … --json` projects nested JSON and omits implicit API
fields; `--json` without projection keeps the result.

`task create/update` accept `--priority`, `--story-points`, `--plan-start`,
`--plan-end`, `--alarm`, `--co-assignee`, `--waiting-for` and `--tag`.
`--co-assignee` and `--tag` replace the set; `none` clears it. Repeated flags
supply several values. Sprint/release `add` appends instead of replacing.

Planned dates are written to the task card. The Gantt chart keeps its own
schedule, aligned to the working calendar, and `--plan-start` does not move it;
`task get` prints it on a separate `gantt schedule` line.

`--dry-run` previews task create/update/move/log/attach/comment without mutations.
It resolves references but does not validate server permissions or workflow rules.
Bulk operations preview unless `--yes` is present, cap the resolved set at 1,000,
and report each failure; successful writes are not rolled back.

`doc watch` subscribes only you: on the server each follower record is made by
the person who follows. Repeating it changes nothing. `doc followers` reads
explicit subscriptions, not implicit recipients or page readers.
`doc download-all` avoids the server's archive call, which stores its zip as a
new attachment on the document. See [scope and verification notes](docs/issue-batch.md),
[reading](plugin/skills/eva/reading.md), [writing](plugin/skills/eva/writing.md)
and the [expanded reference](plugin/skills/eva/expanded.md).

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
- `src/main.mojo`: command dispatch and help.
- `src/eva/common.mojo`, `selection.mojo`: shared lookups, paginated output and
  complete bounded selections; commands do not import another command monolith.
- `task.mojo`, `workflow.mojo`, `collaboration.mojo`, `documents.mojo`,
  `attachments.mojo`: task fields, transitions, comments, wiki writes and files.
- `dates.mojo`, `projection.mojo`, `validation.mojo`, `writes.mojo`: shared date,
  projection, readback and preview logic. `commands.mojo` only owns raw calls.

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
`tests/test_update_check.py` stands in for GitHub's release redirect through
`EVA_UPDATE_URL`; every other test sets `EVA_NO_UPDATE_CHECK=1`.

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
