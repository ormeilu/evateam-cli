# Writing

Every write changes a tracker other people read. Before each mutation, tell the
user what will change and wait for their yes. Task create/update/move/log/attach/
comment accept `--dry-run`: they resolve references and print payloads without
mutating. This is not server-side validation. Bulk operations preview by default
and require `--yes` to apply. `trash restore` can recover a deleted task while
the server retains it; successful bulk writes are not rolled back.

`expanded.md` covers the newer commands, replacement/append semantics, bounds
and the unverified document-subscription write.

## Creating a task

```bash
eva task create -p proj -t "Retry uploads on 5xx" -d "Steps:

1. Upload a file
2. Get a 503" -a login@company.ru --sprint SPR-000006
```

`-p` is the project code, `-t` the title. `-d` is plain text: blank lines become
paragraphs, HTML in it is escaped, not rendered. See "Formatting and long text"
below for Markdown and for text from a file. `-a` takes a login. eva prints
the new code (`created PROJ-124 …`); use that code from then on.

A subtask names its parent task. eva takes the epic from the parent, sets the
type by name or code, and `--set` adds any other fields:

```bash
eva task create -p proj -t "Retry uploads" --parent PROJ-123 --type Подзадача
eva task create -p proj -t "Crash on upload" --type bug --set '{"deadline": "2026-12-01"}'
```

When a task gets an epic, EvaTeam makes the epic its parent task too. So eva
creates the subtask under the epic and sets the parent task in a second
request. If EvaTeam still ends up with a different parent, eva prints
`note: EvaTeam did not keep …`; check the task with `eva task get`.

## When a write gets no reply

```text
eva: CmfList.create was sent to https://…, but the connection closed without a reply;
it may have been applied, so check before running it again (a retry can apply it twice)
```

The request reached the server and the answer was lost on the way back. Do not
run the command again yet: look first (`eva task get`, `eva release list -p
PROJ`), because a second create makes a duplicate. `no reply within 30 s` in
the same message means the server took longer than eva waits, which can also
end in an applied write. `cannot reach …` is different: nothing was sent, and
running it again is safe. A read that loses its reply is sent once more on its
own; `got no reply … (tried twice)` means both tries failed.

## Attaching files

```bash
eva task attach PROJ-124 report.html screenshot.png   # prints the new ATT codes
```

eva creates the attachment, uploads the file to EvaTeam's own /files/ address
(the token goes nowhere else) and checks the size the server stored. If the
server refuses a file (size, type), the error says why and no empty attachment
is left. Every file is read before anything is created, so a missing path
changes nothing.

EvaTeam stores a task's files by name. A file with a name the task already has
would replace the existing file's content, so eva refuses it unless `--force`
is given. Rename the file instead unless the user wants it replaced.

## Deleting a task

```bash
eva task delete PROJ-124 --yes
```

In a terminal eva asks first and names the task and how many subtasks it has;
without a terminal it deletes only with `--yes`. Delete a task only when the
user asked for that task by code, and name it in the confirmation you ask for.

## Changing fields

```bash
eva task update PROJ-124 -t "New title" -d "New description" -a login@company.ru
eva task update PROJ-124 --set '{"deadline": "2026-12-01"}'
```

`--set` sends any fields as JSON, under EvaTeam's names; `eva task get CODE
--json` shows what a task has, and `eva field list` the custom ones. A
multi-select takes value names, which eva turns into ids, and a choice takes a
key from `eva field get NAME`:

```bash
eva task update PROJ-124 --set '{"cf_direction": ["iOS", "BE"]}'
eva task update PROJ-124 --set '{"cf_102_1ind": "k8s"}'
```

 `-d` replaces the whole description. A
reference field goes by its name without `_id`, with the id as the value:
`{"epic": "CmfTask:…"}`, `{"parent_task": "CmfTask:…"}`,
`{"logic_type": "CmfLogicType:…"}`. A create with `epic_id` or
`parent_task_id` is refused ("Это служебное поле…").

EvaTeam derives some fields from others: setting `epic` also moves the parent
task to the epic. After an update eva re-reads the parent task, epic, type,
assignee and status, and prints `note: EvaTeam also changed …` for any that
changed without being asked. To change both, set the epic first and the parent
last, in two updates.

## Moving through the workflow

```bash
eva task statuses PROJ-124          # where it can go from its current status
eva task move PROJ-124 "In Development" -m "Picked up"
```

The target is a status code or name from `statuses`, any case. If the workflow
has no transition there from the current status, eva lists the ones it has; a
task may need an intermediate status first. `-m` adds a comment with the
transition.

A workflow often allows one step at a time. `--path` walks the shortest
route, stopping at the first step EvaTeam refuses and naming it:

```bash
eva task path PROJ-124 closed          # see the route first
eva task move PROJ-124 closed --path -m "Released" --resolution done
```

A transition marked "from any status" in `statuses` is one the workflow allows
from every status, often a system one straight to Done or back to Backlog. A
status's own transition to the same place is used before it.

The route avoids side statuses such as On Hold. `--set` goes with every step,
and `-m` and `--resolution` go with the last one. A transition the workflow
attaches a condition to is marked "conditional" in `statuses`. Such a
condition is often a role, so EvaTeam may refuse it for this user even though
it is listed. eva cannot see role rules in advance: when a walk stops on such a
refusal, tell the user who usually makes that move (`eva call
CmfStatusHistory.list` shows past moves) rather than looking for a way around it.

A transition can require fields. EvaTeam refuses it and names the field:

```
eva: CmfTask.task_transition_run refused: Необходимо заполнить Вид услуги
```

Find the field's internal name and an allowed value on a task that already
passed this transition, then send it with the move:

```bash
eva call CmfTask.get --kwargs '{"filter": ["code", "==", "PROJ-126"], "fields": ["**"]}' | grep cf_
eva task move PROJ-124 Done --set '{"cf_vid_uslugi": "razvitie"}'
```

Ask the user which value applies when more than one fits; the value means
something to their team's reporting.

A closed task also has a resolution, and a closing transition sets the
default one (`done`) unless told otherwise:

```bash
eva resolution list                                   # codes and names
eva task move PROJ-124 Done --resolution wont_do -m "Not needed after the redesign"
eva task update PROJ-124 --resolution dublicate       # on a task already closed
```

`--resolution` takes a code or a name, any case (EvaTeam spells the duplicate
code `dublicate`). `task get` shows the resolution next to the status.

`task update -s STATUS` does the same move after its other changes. A plain
`eva call CmfTask.update` with a new status is accepted by EvaTeam and silently
ignored: always change status through `move`.

## Comments and time

```bash
eva task comment PROJ-124 "Reproduced on staging"
eva task log PROJ-124 1h30m -m "Investigation"     # 90, 90m, 2h, 1h30m; ends now
eva task log PROJ-124 2h --date yesterday          # after yesterday's last entry
eva task log PROJ-124 45m --date 2026-11-05 --at 14:15
eva task log PROJ-124 30m --remaining 2h           # also reset the estimate
```

A comment, like a description, is plain text unless `--md` or `--html` says
otherwise. Time is logged in the user's name. Without `--date` or `--at` the
entry ends now. With `--date` alone it starts where that day's last entry ends,
or at 09:00 on an empty day, so a day can be filled entry by entry. Without
`--remaining` the remaining estimate is left as it was.

## Filling the work log

```bash
eva time list                              # this week: per day logged, norm, left
eva time list --from 2026-11-01 --to 2026-11-30
eva time delete TTH-1205075                # an entry logged by mistake
```

The norm for each day comes from the user's working calendar: their own days
first, then the production calendar, so holidays and days off show as such.
To fill a week, read `time list`, ask the user what they worked on each day
that still has time left, confirm the plan, then log it with `--date`. Write
nothing for a day the user did not describe.

```bash
eva task comments PROJ-124 --ids                 # find the comment's id
eva task comment-delete CmfComment:5c91…         # the bare uuid works too
```

EvaTeam keeps a "comment deleted" entry with the old text, so deleting hides a
comment rather than erasing it.

## Following a document

```bash
eva doc watch DOC-000123             # follow it yourself; a repeat is a no-op
eva doc watch DOC-000123 --children  # also the pages under it
eva doc watch DOC-000123 --off       # stop following
```

Only you can be subscribed this way; task watchers are `task watch`.

## Formatting and long text

```bash
eva task comment PROJ-124 --md "## Done
- **fixed** in \`upload.py\`, see [PR](https://git.example/pr/1)"
eva task comment PROJ-124 -F note.md --md        # text from a file
some-command | eva task comment PROJ-124 -F -    # or from stdin
eva task update PROJ-124 -F spec.md --md         # same for descriptions
```

EvaTeam renders HTML, not Markdown. `--md` converts headings, bold, italic,
inline code, code blocks, lists, quotes, rules and http(s)/mailto links, and
escapes any HTML in the source. `--html` sends the text untouched. For anything
longer than a line, write it to a file and pass `-F`: no shell quoting, and
the same command works in fish, bash and zsh.
