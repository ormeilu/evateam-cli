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

You need [pixi](https://pixi.sh). It pulls Mojo 1.2 and everything else.

```bash
git clone https://github.com/ormeilu/evateam-cli
cd evateam-cli
pixi run build          # → build/eva
```

The binary loads `libpython` at run time for HTTPS (see below), so run it from
the pixi environment (`pixi run ./build/eva …`) or with a Python 3.12+ on
`PATH`.

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
| `eva task update CODE [-t] [-d] [-s] [-a] [--set JSON]` | change fields; `--set` passes any field through |
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

`tests/mock_server.py` is a small JSON-RPC server with two canned tasks. The
end-to-end script checks both what `eva` prints and what it sends.

## Status

Checked by hand against a live EvaTeam instance: every read command (`task get`,
`task list` with each filter, `comments`, `links`, `project`, `person`, `doc`,
`call`), paging and counts. The write commands (`create`, `update`, `comment`,
`log`) follow the request shapes in the
[EvaTeam API docs](https://docs.evateam.ru/docs/docs/DOC-000199) and are tested
against the mock only.

## Licence

MIT
