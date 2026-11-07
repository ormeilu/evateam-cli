# Diagnostics and agent workflows

## Schema discovery

```sh
eva schema --classes
eva schema CmfTask -q project --relations
eva schema CmfTask --refresh --json
```

`--classes` is an offline catalog of confirmed built-in command targets, not a
server inventory or a probe of speculative names. Spellings are case-sensitive:
`CmfTestplan`, not `CmfTestPlan`. Generated custom-choice models are not listed.
A listed model can still be unavailable to a particular account/server version.

Schema discovery reads `CLASS.get_meta` once and filters locally by field name,
caption, widget and relation target. Only field names and allowlisted metadata
(`widget`, `caption`, `model`, `models`, `choices`, `nullable`, `virtual`,
`api_allow`) are retained. Arbitrary bodies and credentials are not cached.
`--relations` includes polymorphic relations without a concrete target model.
Piped text shows at most 50 matching fields; narrow with `-q` or use `--full`.
`--json` returns the complete selected metadata object. “Not nullable” does not
mean every create request must supply the field: IDs, for example, are generated.

The cache expires after 24 hours. Expired, future-dated, corrupt, non-regular,
symlinked and non-private entries are rejected. `--refresh` fetches fresh data;
a failed refresh never silently returns stale data. Keys include server identity,
class and a principal fingerprint; neither token nor URL is saved in the body.
An unavailable cache produces a warning and does not prevent fresh schema reads.

Custom-field discovery in `fields.mojo` uses this same cache. The old separate
plaintext custom-field cache is no longer read or written. Existing files are
not deleted automatically.

`tests/test_diagnostics.py` checks the static catalog against literal model call
sites. Update `SCHEMA_CLASSES` when adding a confirmed model; do not add guessed
names just to satisfy the test.

## Read-only session context

```sh
eva context
```

The summary contains sanitized server origin, configuration source, current
login, up to eight projects with visible open-task tallies, and this local
week's visible tasks modified from Monday through today.

At most four read calls are used: current user, a nine-row project probe, one
batched open-task read and one activity read. Open-task sampling is capped at
2,000 rows, activity at 200; each requests an extra sentinel to detect truncation.
A `>=` tally is a lower bound when caps/hidden rows prevent an exact visible
count. These are not organization-wide totals. Activity counts tasks, not events,
hours worked or actions by the signed-in person.

Failed/malformed sections say `unavailable`, not zero. Project failure does not
prevent the independent activity read. No task/project bodies are requested,
no server data is changed and no summary is persisted. Address display omits
userinfo, path, query and fragment because they can contain secrets.

## Separate error hints

Required-field refusals suggest `--set JSON` and `eva field list`; missing API
methods suggest `eva schema --classes`. Advice is printed as a separate `hint:`
line on stderr, after the original error. Its wording is a suggestion, not a
server statement. The original error and nonzero exit status are preserved.

## Bounded raw replies

```sh
eva call CmfTask.get --kwargs '{"filter":["code","==","DEMO-1"],"fields":["code","name"]}'
```

Small raw results remain pretty-printed JSON. Through a pipe, a result larger
than 65,536 bytes goes to a unique private JSON file. Stdout contains the first
40 lines (at most 160 characters each), byte/line statistics and the file path.
`--full` and terminal output preserve complete JSON. Only the API result is
saved, not the request/envelope/authorization token. Results can themselves
contain sensitive data; protect and delete spill files. They do not expire
or get overwritten automatically.

Metadata and raw files live in `$XDG_CACHE_HOME/eva-diagnostics`, falling back
to `$HOME/.cache/eva-diagnostics`. The directory must be private, owned by the
current user and not symlinked. Files use mode 600, exclusive temporary names,
complete writes, sync and atomic directory-relative rename. Reads reject
symlinks/non-regular files; nonblocking opens prevent FIFO hangs. No process-wide
umask change or fixed `last-call.json` overwrite is used.

## Offline cheatsheet

```sh
eva cheatsheet
```

Ten workflows are available without loading configuration or credentials.
Examples use fictional `DEMO-1`, `ATT-1` and `alex@example.invalid`. Substitute
actual codes/required fields, and review writes before executing them. Recipes
cover orientation, triage, task inspection, creation, editing, workflow moves,
comments, time logging, attachments and schema-assisted raw reads.

## Module boundaries and verification

`diagnostics.mojo` owns schema/context/cheatsheet/hints/raw-output policy;
`state.mojo` owns private cache/spill storage. Neither makes the client depend
on command handlers. `main.mojo` dispatches offline commands before creating a
client and authenticated commands afterward. `commands.mojo` retains raw calls.
`schema_metadata(client, cls, refresh=False)` is shared with custom-field reads.

```sh
pixi run test
pixi run e2e
pixi run asan
```

The e2e runner includes Python unittest discovery and sets `EVA_BIN` so tests
exercise the integrated binary. Diagnostics tests also build a Mojo scratch
driver for pure helpers, raw-boundary and terminal-mode checks. Loopback HTTP
fixtures inspect actual requests, cache contents and filesystem permissions;
no local credentials are read and no live server is mutated. Coverage includes
TTL/refresh/corruption, server separation, catalog drift, atomic private writes,
symlink/FIFO safety, UTF-8/output caps, secret omission, bounded context calls,
hidden/unavailable rows, offline recipes and separate stderr hints.
