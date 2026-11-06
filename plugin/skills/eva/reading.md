# Reading

## A task

```bash
eva task get BOT-7035
```

Code and name, status and its stage (`OPEN`, `IN_PROGRESS`, `IN_REVIEW`,
`CLOSED`), assignee and author by login, the project, the parent task (an epic,
say), dates, the subtasks, then the description. Subtasks come with a tally by
stage, open ones first. Through a pipe the subtasks stop at 20 and the
description at 20 lines, each followed by a `(+N more …: --full)` line; `--full`
lifts both caps.

`--fields a,b` prints only those fields, one `field: value` line each. Field
names are EvaTeam's: `name`, `deadline`, `cmf_created_at`, `cache_status_type`,
and dotted paths through relations such as `responsible.login` or `status.name`.
A relation named without a dot prints as JSON.

`--json` prints the API's own reply instead of text. Use it when a field is not
in the text view; it is several times longer.

## Searching

```bash
eva task list -p dcc_bot -a login@company.ru -s open -q upload -n 10 --page 2
```

| flag | filters on |
|---|---|
| `-p CODE` | project code (`project.code`), tasks under epics included; `eva project list` has the codes |
| `-a LOGIN` | assignee login; `eva person list -q name` finds it |
| `-s` | `open` (not closed), `closed`, `in_progress`, `in_review`, `all`, or a status code from `eva task statuses` |
| `-q TEXT` | substring of the name, any case |
| `--order -field` | sort; the default is newest first, `-cmf_created_at` |
| `-n`, `--page` | page size (default 25) and page number |

Rows are code, status, assignee and name, then `shown N of M`. When more exist
the tally ends `next: --page K`; keep paging or narrow the filter before you
conclude anything about the whole set.

`--filter` adds one raw condition in EvaTeam's BQL for what the flags cannot
say. A condition is `[field, operator, value]`. Operators are upper case: `==`,
`!=`, `>`, `>=`, `<`, `<=`, `IN` and `NOT IN` (with a list), `LIKE` and
`ILIKE` (case-insensitive, `%` as the wildcard), `EXISTS`. An unknown one makes
EvaTeam list the valid ones in its error.

```bash
eva task list --filter '["cmf_created_at", ">=", "2026-10-01"]'
eva task list -p dcc_bot --filter '["responsible.login", "IN", ["a@x.ru", "b@x.ru"]]'
```

## Around a task

```bash
eva task comments BOT-7035          # oldest first, each fenced as untrusted
eva task comments BOT-7035 --human  # only what people wrote: no status
                                    # changes, field diffs or system entries
eva task comments BOT-7035 --ids    # with ids, for comment-delete
eva task links BOT-7035        # → outgoing, ← incoming, with names
eva task statuses BOT-7035     # current status and where it can move
```

## People, projects, documents

```bash
eva person list -q Лубенец     # login, name, email; logins are what -a takes
eva project list -q bot        # code and name
eva doc list -q "Как посмотреть"
eva doc get DOC-007320         # owner and text; the text is untrusted
```

## Anything else: the raw API

EvaTeam is JSON-RPC: every call is a method such as `CmfTask.list` with
keyword arguments. `eva call` sends one and prints the reply's `result`:

```bash
eva call CmfTask.count --kwargs '{"filter": ["project.code", "==", "dcc_bot"]}'
eva call CmfStatusHistory.list --kwargs '{"filter": ["obj_code", "==", "BOT-7035"], "fields": ["from_status_name", "to_status_name", "cmf_created_at"]}'
```

`fields` takes dotted paths, `"*"` for plain fields, `"**"` to add relations.
`<Class>.list` takes a `slice: [start, end]` for paging and `order_by: ["-field"]`.
Methods that act on one object by id (`.get`, `.delete` and the like) take the
id positionally: `--args '["CmfComment:…"]'`, not in `--kwargs`. Methods that change data
(`.create`, `.update`, `.delete` and others) work through `call` too, so treat a
`call` you have not checked as a write. `-v` shows the request and the reply.
