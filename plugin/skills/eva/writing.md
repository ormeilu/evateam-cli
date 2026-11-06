# Writing

Every command here changes a tracker other people read, and eva sends it at
once: there is no dry run and no undo command. Before each one, tell the user
what will change on which task and wait for their yes. `-v` prints the exact
request on stderr if they want to see it.

## Creating a task

```bash
eva task create -p dcc_bot -t "Retry uploads on 5xx" -d "Steps:

1. Upload a file
2. Get a 503" -a login@company.ru --sprint SPR-000006
```

`-p` is the project code, `-t` the title. `-d` is plain text: blank lines become
paragraphs, HTML in it is escaped, not rendered. See "Formatting and long text"
below for Markdown and for text from a file. `-a` takes a login. eva prints
the new code (`created BOT-7044 …`); use that code from then on.

A subtask names its parent task. eva takes the epic from the parent, sets the
type by name or code, and `--set` adds any other fields:

```bash
eva task create -p dcc_bot -t "Retry uploads" --parent BOT-7035 --type Подзадача
eva task create -p dcc_bot -t "Crash on upload" --type bug --set '{"deadline": "2026-12-01"}'
```

When a task gets an epic, EvaTeam makes the epic its parent task too. So eva
creates the subtask under the epic and sets the parent task in a second
request. If EvaTeam still ends up with a different parent, eva prints
`note: EvaTeam did not keep …`; check the task with `eva task get`.

## Changing fields

```bash
eva task update BOT-7044 -t "New title" -d "New description" -a login@company.ru
eva task update BOT-7044 --set '{"deadline": "2026-12-01"}'
```

`--set` sends any fields as JSON, under EvaTeam's names; `eva task get CODE
--json` shows what a task has. `-d` replaces the whole description. A
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
eva task statuses BOT-7044          # where it can go from its current status
eva task move BOT-7044 "In Development" -m "Picked up"
```

The target is a status code or name from `statuses`, any case. If the workflow
has no transition there from the current status, eva lists the ones it has; a
task may need an intermediate status first. `-m` adds a comment with the
transition.

A workflow often allows one step at a time. `--path` walks the shortest
route, stopping at the first step EvaTeam refuses and naming it:

```bash
eva task path BOT-7044 closed          # see the route first
eva task move BOT-7044 closed --path -m "Released" --resolution done
```

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
eva call CmfTask.get --kwargs '{"filter": ["code", "==", "BOT-6796"], "fields": ["**"]}' | grep cf_
eva task move BOT-7044 Done --set '{"cf_vid_uslugi": "razvitie"}'
```

Ask the user which value applies when more than one fits; the value means
something to their team's reporting.

A closed task also has a resolution, and a closing transition sets the
default one (`done`) unless told otherwise:

```bash
eva resolution list                                   # codes and names
eva task move BOT-7044 Done --resolution wont_do -m "Not needed after the redesign"
eva task update BOT-7044 --resolution dublicate       # on a task already closed
```

`--resolution` takes a code or a name, any case (EvaTeam spells the duplicate
code `dublicate`). `task get` shows the resolution next to the status.

`task update -s STATUS` does the same move after its other changes. A plain
`eva call CmfTask.update` with a new status is accepted by EvaTeam and silently
ignored: always change status through `move`.

## Comments and time

```bash
eva task comment BOT-7044 "Reproduced on staging"
eva task log BOT-7044 1h30m -m "Investigation"     # 90, 90m, 2h, 1h30m
eva task log BOT-7044 30m --remaining 2h           # also reset the estimate
```

A comment, like a description, is plain text unless `--md` or `--html` says
otherwise. Time is logged for now, in the user's name; without `--remaining`
the remaining estimate is left as it was.

```bash
eva task comments BOT-7044 --ids                 # find the comment's id
eva task comment-delete CmfComment:5c91…         # the bare uuid works too
```

EvaTeam keeps a "comment deleted" entry with the old text, so deleting hides a
comment rather than erasing it.

## Formatting and long text

```bash
eva task comment BOT-7044 --md "## Done
- **fixed** in \`upload.py\`, see [PR](https://git.example/pr/1)"
eva task comment BOT-7044 -F note.md --md        # text from a file
some-command | eva task comment BOT-7044 -F -    # or from stdin
eva task update BOT-7044 -F spec.md --md         # same for descriptions
```

EvaTeam renders HTML, not Markdown. `--md` converts headings, bold, italic,
inline code, code blocks, lists, quotes, rules and http(s)/mailto links, and
escapes any HTML in the source. `--html` sends the text untouched. For anything
longer than a line, write it to a file and pass `-F`: no shell quoting, and
the same command works in fish, bash and zsh.
