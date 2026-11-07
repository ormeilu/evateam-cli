# Expanded command reference

This supplements `eva --help`. Examples use fictional codes. All mutations
still require the user's go-ahead when an agent drives the CLI.

## Task cards, projections and queues

`task get` includes priority, story points, planned dates, alarm, watchers,
co-assignees, waiting-for, tags, components, sprint/release lists and checklist
progress when readable. Explicit `--fields priority` still prints the raw value.
`task get CODE --with comments,attachments,links` composes the existing text
readers in that order; `--with all` also adds workflow statuses. This is a text
card, not a JSON envelope, and does not collapse the server into one RPC.

`task list --author me`, `--watching me`, `--waiting-for me` and `-a me`
resolve the signed-in person; any of these also accepts a login. `--archived`
selects archived tasks. `--tag NAME` and `--component NAME` match exact names.
Tags are selected from `CmfTag`; components belong to projects.

```bash
eva task list --cols code,status.name,responsible.login --format tsv
eva task get PROJ-123 --fields code,responsible.login --json
```

Projected JSON retains nested objects and arrays, omits implicit server fields,
and preserves requested nulls. Missing paths are omitted. TSV has no header or
footer; tabs, line breaks and backslashes inside cells are escaped. Page with
`-n` and `--page`; an empty page has no data rows. `--json` without `--fields`
or `--cols` preserves the API result.

## Planning, people, labels and lists

Create/update shortcuts:

- `--priority`: numeric code -2 through 3, the exact Russian caption, or
  `lowest`, `low`, `normal`, `high`, `critical`, `blocker`.
- `--story-points`: non-negative finite JSON number.
- `--plan-start`, `--plan-end`: `YYYY-MM-DD`; `none`/`off` clears a date.
- `--alarm`: `YYYY-MM-DD HH:MM`; `off`/`none` clears it.
- `--co-assignee LOGIN` and `--tag NAME`: repeat to **replace** the complete
  set. `none` clears it and cannot be mixed with values.
- `--waiting-for LOGIN|none`: set the person or clear the field.

`--set` still accepts raw fields. Tag/component and custom multi-select values
can be names or IDs; ambiguous names are rejected. The server decides which
labels a project/workflow permits. Typed planning flags write the task fields;
they do not create or reschedule a Gantt object. Readback must confirm what was
written; server-side scheduling propagation is not claimed.

`task watch/unwatch CODE [--login LOGIN]` changes task spectators, defaulting to
self. Repeated calls are no-ops. Groups and departments are not resolved by
these person-oriented commands.

`sprint list/get` and `release list/get` discover lists. `sprint add CODE TASK…`
and `release add CODE TASK…` append membership, preserve other lists, pre-resolve
all task codes and continue after individual server refusals. They do not close
or ship a sprint/release.

## Comments, files, history and checklists

`task comments` and `doc comments` show the newest window of 20 by default,
chronological inside the window. `--page 2` goes earlier, `-n` changes the window,
`--human` hides workflow/system rows, and `--ids` exposes IDs. `--all` collects the
whole matching set with a 10,000-row safety cap and cannot be combined with
paging flags. Text keeps the normal untrusted fences and line limits.

`task/doc comment CODE TEXT --reply-to CmfComment:…` checks that the parent
comment belongs to that task/document. `task/doc comment-edit ID TEXT|-F FILE`
replaces its text. The server owns edited/deleted markers. `--attach FILE`
can be repeated on a new comment. All paths are checked first; upload failure
keeps the already-created comment and names the failed file.

`doc attach/attachments` use the same upload/name-collision checks as tasks.
`attachment delete ATT-1 --yes` confirms removal through the API; it does not
promise physical erasure of stored bytes. `doc download-all` is not implemented:
archive layout and extraction safety are not established.

`task history` contains status transitions only, newest first. `task checklist`
shows each checklist and a page of its ordered items. `task check CHLI-1` sets
DONE; `--undo` sets OPEN. Creating checklists/items is outside this interface.

`task create --template CODE -p PROJ` copies a confirmed task template. Optional
field overrides are validated before creation and applied in a second update.
If that update fails, the created task is kept and its code is reported.

`relation types` discovers relation codes/names. `task link/unlink A B --type X`
uses an exact code/name; omitted type or `relates` means `system.link`. Unlink
removes only that direction/type, not every relation between the pair.

## Search, notifications, development and time

`search TEXT -t task|doc|all` performs bounded substring search over name **or**
text. It is not an attachment/comment index or relevance-ranked full-text
engine. The limit/page applies separately to each selected object type.

`notify list` reads the signed-in person's unread rows; `--all` includes read
ones and does not mark anything read. `task dev` displays the linked git data
as fenced JSON, preserving provider-specific state/IDs. `repo list` is read-only.

`task time CODE` shows visible actual entries; `--all` includes plans/drafts.
Its totals cover the displayed page only. `time report --from D --to D` collects
visible entries for self, or `-a LOGIN`, groups by project/start-date, and reports
actual, planned (`plan`/`plan_oper`) and other/draft minutes separately. A maximum
of 10,000 rows is enforced; narrow the range when necessary. Entries are not
split across midnight. Permissions can hide other people's records; a successful
report does not prove organization-wide completeness.

## Wiki, projects, tests and ServiceDesk

`doc create/update` writes drafts. Publication requires `--publish` or a separate
`doc publish CODE`; published text is read back. `doc children` returns documents
only, not a complete heterogeneous folder tree. `--depth 1` is the default,
maximum 10; page/limit applies under each parent. `doc history` returns exact
opaque version strings. `doc get CODE --version STRING` selects that string,
not an ordinal revision number. Rollback and diff are not implemented.

`project get` shows owner, **direct role assignments** and project lists. A role
member can be a person, group, organizational unit, company or role. These rows
are not a deduplicated count of effective human members: defaults, groups and
permission inheritance are not expanded.

`testcase list/get` reads case metadata and standalone ordered steps, including
pre/postcondition sections. `testplan list/get` reads plans and case membership.
The actual model spellings are `CmfTestcase` and `CmfTestplan`; run/cycle execution
and reporting are not implemented.

`ticket get` reads native `CmfSDeskSlaCycle` rows. Duration integers stay in
server-native units because units/freshness are not verified. It also pages the
project's visible queue definitions and tests each readable computed JSON BQL
against the ticket ID. Multiple queues can match: these are query-defined views,
not a unique assignment. Missing/legacy Python/UBQL definitions and failed counts
are labelled unknown, never reported as non-matches. No stored code is executed.

## Saved filters and document subscriptions

`filter list` lists **your own** `CmfBqlFilter` rows. `task list --filter CODE`
or an exact name executes the stored JSON `bql`, ANDed with other selectors.
An explicitly stored `[]` remains valid; missing/malformed/UBQL-only BQL is an
error, never an unrestricted fallback. Non-task models and duplicate names are
rejected. Legacy null-model filters are accepted only with valid stored BQL.
No Python/expression evaluation is performed; shared-filter discovery and UBQL
compilation remain outside this interface.

`doc followers` and the default document text view show explicit followers
readable to the account. These differ from spectators, implicit notification
recipients and page viewers. **No `doc watch` write is shipped**: the separate
`CmfFollower` model is confirmed, but its write/permission contract has not been
verified. Issue #68 stays open; do not substitute a spectator update.

## Preview, bulk operations and recovery

`--dry-run` on task create/update/move/log/attach/comment renders `would send:`
with resolved methods/kwargs/args. Read-only lookups may run; mutations do not.
A future ID/upload URL is explicitly unavailable, not fabricated. This is not
server-side validate-only: workflow rules, permissions and later derived state
can still reject the real write.

`task bulk set --filter BQL --set JSON` and `task bulk move STATUS --filter BQL`
preview unless `--yes` is supplied. `--dry-run` wins over `--yes`. An explicit
filter or project selector is required. The complete set is collected before
writes, capped at 1,000, with stable pagination and duplicate/count checks.
Each task failure is named, processing continues, and any failure makes the
command exit nonzero. This is not a transaction: successful changes remain.
Stdin code selection is not supported.

`trash list` uses the deleted-task predicate. Its timestamp is **last modified**,
not a verified deletion time or retention promise. `trash restore CODE --yes`
requires a readable deletion state and confirms restoration with a readback;
already-restored tasks are no-ops. Permission refusals keep the server's wording.
