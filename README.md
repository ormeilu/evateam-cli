# eva — EvaTeam from the command line, in Mojo

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
parent: DEV  Development
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

eva is built for macOS on Apple silicon and Linux on x86_64 and arm64 (glibc
2.34 or newer). Pick one way to install it.

With the install script. It installs [pixi](https://pixi.sh) if it is missing,
then eva from the conda channel `prefix.dev/ormeilu`. Run it again to update:

```bash
curl -fsSL https://raw.githubusercontent.com/ormeilu/evateam-cli/main/install.sh | sh
```

With pixi directly, which is what the script does:

```bash
pixi global install -c https://prefix.dev/ormeilu -c https://conda.modular.com/max -c conda-forge evateam-cli
```

From PyPI, if you prefer uv or pipx:

```bash
uvx --from evateam-cli eva --help     # run without installing
uv tool install evateam-cli           # or put `eva` on PATH
pipx install evateam-cli
```

`eva upgrade` updates eva the same way it was installed.

The two routes differ in size. Both carry Mojo's runtime libraries as a
dependency on Modular's `mojo-compiler` package. On PyPI that package is about
70 MB. The conda package brings the whole compiler, and the pixi environment
ends up around 300 MB. The binary itself is under half a megabyte. Either way
eva makes its HTTPS calls through the Python it is installed with, so there is
nothing else to set up.

From source, with [pixi](https://pixi.sh):

```bash
git clone https://github.com/ormeilu/evateam-cli
cd evateam-cli
pixi run build          # → build/eva
```

## Configure

Create a token in EvaTeam: «Моя страница» → «Безопасность» → «Сгенерировать
API токен». Then set two variables, in the environment, in `./.env` or in
`~/.config/eva-cli/env`:

```bash
EVA_URL=https://eva.example.ru
EVA_API_KEY=…
```

`EVA_INSECURE=1` skips TLS verification, for self-hosted servers with their own
certificate. `eva config` shows what was picked up and from where, without
printing the token.

## Commands

| Command | What it does |
|---|---|
| `eva task get CODE [--fields a,b]` | one task: status, people, parent, description |
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
- `src/eva/client.mojo`: configuration and the RPC call. Mojo's standard
  library has no TLS yet, so the HTTPS request itself goes through Python's
  `urllib` via Mojo's Python interop. Request building and reply parsing are
  Mojo.
- `src/eva/render.mojo`: terminal and pipe output, HTML to text, colour via
  [mist](https://github.com/thatstoasty/mist) from the
  [modular-community](https://prefix.dev/channels/modular-community) channel.
- `src/eva/commands.mojo`: the command tree.

The JSON parser is home-made because the `emberjson` build in modular-community
was compiled for Mojo 1.1 and does not load under 1.2.

## Develop

```bash
pixi run test     # unit tests: JSON, rendering, argument parsing
pixi run e2e      # builds eva and runs it against tests/mock_server.py
```

`pixi run conda-package` builds the conda package from `recipe/recipe.yaml`
into `output/`. `pixi run wheel macosx_13_0_arm64` packs `build/eva` into a wheel in `dist/`,
with its rpath pointed at `mojo-compiler`'s libraries in the same
site-packages. A tag `vX.Y.Z` matching `pixi.toml` runs
`.github/workflows/release.yml`: wheels and conda packages for three
platforms, the end-to-end suite against each one installed the way a user
would, then PyPI, prefix.dev and a GitHub release.

`tests/mock_server.py` is a small JSON-RPC server with two canned tasks. The
end-to-end script checks both what `eva` prints and what it sends.

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
