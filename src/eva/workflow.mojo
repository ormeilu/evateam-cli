"""Task transitions and resolutions."""
from eva.args import Args
from eva.writes import preview_write
from eva.client import Client
from eva.json import JsonDoc, J_OBJ
from eva.render import Out, pad, text_to_html
from eva.common import (
    split_csv,
    get_by_code,
    print_json,
    want_json,
    quote_str,
)

# `froms` of a transition whose status_from is empty: EvaTeam runs it from any
# status, like a system "from all statuses to Done".
comptime FROM_ANY = "*"


struct Transitions(Movable):
    """A task's workflow: every transition, and where the task is now."""

    var task_id: String
    var current_id: String
    var current: String
    var current_code: String
    var trans_ids: List[String]
    var trans_names: List[String]
    var to_ids: List[String]
    var to_codes: List[String]
    var to_names: List[String]
    # Comma-separated status ids each transition starts from, or FROM_ANY.
    var froms: List[String]
    # "" for a plain transition; "conditional" when the workflow attaches a
    # condition the server checks when it runs (roles, fields); "automatic"
    # when it cannot be run by hand.
    var limits: List[String]

    def __init__(out self):
        self.task_id = ""
        self.current_id = ""
        self.current = ""
        self.current_code = ""
        self.trans_ids = List[String]()
        self.trans_names = List[String]()
        self.to_ids = List[String]()
        self.to_codes = List[String]()
        self.to_names = List[String]()
        self.froms = List[String]()
        self.limits = List[String]()

    def starts_from(self, i: Int, status_id: String) -> Bool:
        if self.froms[i] == FROM_ANY:
            return True
        for f in self.froms[i].split(","):
            if String(f) == status_id:
                return True
        return False

    def runnable(self, i: Int, status_id: String) -> Bool:
        """Transition i leads somewhere else from status_id and can be run by hand.
        """
        return (
            self.to_ids[i] != status_id
            and self.starts_from(i, status_id)
            and self.limits[i] != "automatic"
        )

    def matches(self, i: Int, target: String) -> Bool:
        var want = String(target.strip()).lower()
        return (
            self.to_codes[i].lower() == want or self.to_names[i].lower() == want
        )

    def by_preference(self) -> List[Int]:
        """Transition indexes, those from named statuses before those from any
        status, so the status's own transition wins where both lead somewhere.
        """
        var out = List[Int]()
        for i in range(len(self.trans_ids)):
            if self.froms[i] != FROM_ANY:
                out.append(i)
        for i in range(len(self.trans_ids)):
            if self.froms[i] == FROM_ANY:
                out.append(i)
        return out^

    def from_here(self) -> List[Int]:
        var out = List[Int]()
        for i in self.by_preference():
            if not self.runnable(i, self.current_id):
                continue
            if self.froms[i] == FROM_ANY:
                var covered = False
                for j in out:
                    if self.to_ids[j] == self.to_ids[i]:
                        covered = True
                        break
                if covered:
                    continue
            out.append(i)
        return out^

    def is_hub(self, status_id: String) -> Bool:
        """A side status most of the workflow leads into: On Hold, Cancelled,
        and Done itself. A walk does not pass through one on its way elsewhere.
        """
        var statuses = List[String]()
        for i in range(len(self.trans_ids)):
            if self.froms[i] == FROM_ANY:
                continue
            for f in self.froms[i].split(","):
                var s = String(f)
                var known = False
                for x in statuses:
                    if x == s:
                        known = True
                        break
                if not known:
                    statuses.append(s)
        var into = 0
        for i in range(len(self.trans_ids)):
            if self.to_ids[i] != status_id:
                continue
            if self.froms[i] == FROM_ANY:
                for s in statuses:
                    if s != status_id:
                        into += 1
                continue
            for f in self.froms[i].split(","):
                if String(f) != status_id:
                    into += 1
        return into * 2 > len(statuses)

    def path_to(self, target: String) -> List[Int]:
        """The fewest transitions from the current status to `target` that
        avoid side statuses on the way, or failing that any path; empty if none.
        """
        var steps = self._bfs(target, True)
        if len(steps) == 0:
            steps = self._bfs(target, False)
        return steps^

    def _bfs(self, target: String, avoid_hubs: Bool) -> List[Int]:
        """Breadth-first search over the transitions runnable by hand."""
        var seen = List[String]()
        seen.append(self.current_id)
        var queue = List[String]()
        queue.append(self.current_id)
        # How each status was reached: the transition index, and the status before it.
        var via = List[Int]()
        var prev = List[String]()
        var reached = List[String]()
        var order = self.by_preference()
        var head = 0
        while head < len(queue):
            var at = queue[head]
            head += 1
            for i in order:
                if not self.runnable(i, at):
                    continue
                var to = self.to_ids[i]
                var known = False
                for s in seen:
                    if s == to:
                        known = True
                        break
                if known:
                    continue
                if (
                    avoid_hubs
                    and not self.matches(i, target)
                    and self.is_hub(to)
                ):
                    continue
                seen.append(to)
                queue.append(to)
                reached.append(to)
                via.append(i)
                prev.append(at)
                if self.matches(i, target):
                    var steps = List[Int]()
                    var k = len(reached) - 1
                    while True:
                        steps.append(via[k])
                        var back = prev[k]
                        if back == self.current_id:
                            break
                        for j in range(len(reached)):
                            if reached[j] == back:
                                k = j
                                break
                    steps.reverse()
                    return steps^
        return List[Int]()


@fieldwise_init
struct Resolution(Copyable, Movable):
    var id: String
    var code: String
    var name: String


def transitions_for(client: Client, code: String) raises -> Transitions:
    var t = get_by_code(
        client,
        "CmfTask",
        code,
        split_csv("id,status_id,status.name,status.code,workflow_id"),
    )
    var out = Transitions()
    out.task_id = t.doc.text_at(t.result, "id")
    out.current = t.doc.text_at(t.result, "status.name")
    out.current_code = t.doc.text_at(t.result, "status.code")
    out.current_id = t.doc.text_at(t.result, "status_id")
    var wf = t.doc.text_at(t.result, "workflow_id")
    if wf == "":
        raise Error(code + ": the task has no workflow")

    var d = JsonDoc()
    var kw = d.object()
    var v = d.string(wf)
    var f = d.triple("workflow_id", "==", v)
    d.set(kw, "filter", f)
    var fl = d.str_array(
        split_csv(
            "name,status_to_id,status_to.code,status_to.name,status_from.id,"
            "do_filter_by_id,restrict_manual_trans,is_create_transition"
        )
    )
    d.set(kw, "fields", fl)
    var s = d.array()
    var lo = d.number(0)
    var hi = d.number(1000)
    d.push(s, lo)
    d.push(s, hi)
    d.set(kw, "slice", s)
    var r = client.call("CmfTrans.list", d.dump(kw))
    if r.doc.len(r.result) >= 1000:
        raise Error(
            "workflow transition list reached its 1000-row cap; refusing to"
            " plan an incomplete path"
        )
    for i in range(r.doc.len(r.result)):
        var tr = r.doc.at(r.result, i)
        var from_list = r.doc.get(tr, "status_from")
        var ids = List[String]()
        for j in range(r.doc.len(from_list)):
            ids.append(r.doc.text_at(r.doc.at(from_list, j), "id"))
        if len(ids) == 0:
            # Empty status_from: the creation transition, which a move never
            # runs, or one EvaTeam runs from any status.
            if r.doc.text_at(tr, "is_create_transition") == "true":
                continue
            ids.append(FROM_ANY)
        out.trans_ids.append(r.doc.text_at(tr, "id"))
        out.trans_names.append(r.doc.text_at(tr, "name"))
        out.to_ids.append(r.doc.text_at(tr, "status_to_id"))
        out.to_codes.append(r.doc.text_at(tr, "status_to.code"))
        out.to_names.append(r.doc.text_at(tr, "status_to.name"))
        out.froms.append(",".join(ids))
        if r.doc.text_at(tr, "restrict_manual_trans") == "true":
            out.limits.append("automatic")
        elif r.doc.text_at(tr, "do_filter_by_id") != "":
            out.limits.append("conditional")
        else:
            out.limits.append("")
    return out^


def find_resolution(client: Client, want: String) raises -> Resolution:
    """A resolution by code or name, any case; the error lists the codes."""
    var r = client.call(
        "CmfResolution.list", '{"fields":["id","code","name"],"slice":[0,500]}'
    )
    var w = String(want.strip()).lower()
    var codes = List[String]()
    for i in range(r.doc.len(r.result)):
        var x = r.doc.at(r.result, i)
        var code = r.doc.text_at(x, "code")
        var name = r.doc.text_at(x, "name")
        if code.lower() == w or name.lower() == w:
            return Resolution(r.doc.text_at(x, "id"), code, name)
        codes.append(code)
    raise Error(
        "no resolution "
        + want
        + "; eva resolution list shows them: "
        + ", ".join(codes)
    )


def run_transition(
    client: Client,
    tr: Transitions,
    i: Int,
    comment: String,
    fields: String,
    res: Resolution,
    dry_run: Bool = False,
) raises:
    var d = JsonDoc()
    var kw = d.object()
    d.set_str(
        kw, "comment_append", text_to_html(comment) if comment != "" else ""
    )
    var changed = d.object()
    if fields != "":
        # Fields the transition requires, e.g. --set '{"cf_vid_uslugi": "razvitie"}'.
        changed = d.parse(fields)
        if d.kind(changed) != J_OBJ:
            raise Error("--set expects a JSON object")
    d.set_str(changed, "status", tr.to_ids[i])
    if res.id != "":
        d.set_str(changed, "resolution", res.id)
    d.set(kw, "changed_fields", changed)
    var args_json = (
        "[" + quote_str(tr.task_id) + "," + quote_str(tr.trans_ids[i]) + "]"
    )
    if preview_write(
        dry_run, "CmfTask.task_transition_run", d.dump(kw), args_json
    ):
        return
    _ = client.call("CmfTask.task_transition_run", d.dump(kw), args_json)


def keep_resolution(
    client: Client, code: String, task_id: String, res: Resolution
) raises:
    """A closing transition may put its default resolution over the one sent
    with it; set it again after the move if so."""
    var after = get_by_code(
        client, "CmfTask", code, [String("resolution.code")]
    )
    if after.doc.text_at(after.result, "resolution.code") != res.code:
        var u = JsonDoc()
        var uk = u.object()
        u.set_str(uk, "resolution", res.id)
        _ = client.call(
            "CmfTask.update", u.dump(uk), "[" + quote_str(task_id) + "]"
        )


def shell_word(s: String) -> String:
    """`s` as one word in a suggested command line."""
    if s.find(" ") < 0 and s.find("'") < 0 and s.find('"') < 0:
        return s
    return "'" + s.replace("'", "'\\''") + "'"


def path_text(tr: Transitions, steps: List[Int]) -> String:
    var out = tr.current
    for i in steps:
        out += " → " + tr.to_names[i]
    return out


def refuse_noop_move(client: Client, code: String, target: String) raises:
    """Raise when `code` is already in `target`: no transition would run, so a
    comment or resolution meant for it would be lost."""
    var tr = transitions_for(client, code)
    var want = String(target.strip()).lower()
    if want == tr.current.lower() or (
        tr.current_code != "" and want == tr.current_code.lower()
    ):
        raise Error(
            code
            + " is already in "
            + tr.current
            + "; no transition would run, so -m/--resolution would not apply."
            " Drop -s to set --resolution, or use eva task comment"
        )


def move_task(
    client: Client,
    code: String,
    target: String,
    comment: String,
    fields: String,
    resolution: String,
    ui: Out,
    walk: Bool = False,
    dry_run: Bool = False,
) raises:
    var tr = transitions_for(client, code)
    var want = String(target.strip()).lower()
    if want == tr.current.lower() or (
        tr.current_code != "" and want == tr.current_code.lower()
    ):
        if fields != "" or comment != "" or resolution != "":
            raise Error(
                code
                + " is already in "
                + tr.current
                + "; no transition would run, so its fields/comment/resolution"
                " would not apply; use task update"
            )
        print(code + " is already in " + tr.current)
        return
    var steps = List[Int]()
    if walk:
        steps = tr.path_to(target)
        if len(steps) == 0:
            raise Error(
                code
                + " is in "
                + tr.current
                + " and the workflow has no path to "
                + target
                + " through transitions run by hand; see eva task statuses "
                + code
            )
    else:
        for i in tr.from_here():
            if tr.matches(i, target):
                steps.append(i)
                break
        if len(steps) == 0:
            var options = List[String]()
            for i in tr.from_here():
                options.append(tr.to_codes[i] + " (" + tr.to_names[i] + ")")
            var hint = String("")
            if len(tr.path_to(target)) > 0:
                hint = (
                    "; it can get there in steps: eva task move "
                    + code
                    + " "
                    + shell_word(target)
                    + " --path"
                )
            raise Error(
                code
                + " is in "
                + tr.current
                + " and cannot move to "
                + target
                + "; it can move to: "
                + (", ".join(options) if len(options) > 0 else "nothing")
                + hint
            )
    var res = Resolution("", "", "")
    if resolution != "":
        res = find_resolution(client, resolution)
    var none = Resolution("", "", "")
    for k in range(len(steps)):
        var i = steps[k]
        var last = k == len(steps) - 1
        var before = tr.current
        try:
            # The comment and the resolution go with the last step only;
            # --set goes with each, since any step may require those fields.
            run_transition(
                client,
                tr,
                i,
                comment if last else "",
                fields,
                res if last else none,
                dry_run,
            )
        except e:
            if len(steps) == 1:
                raise e^
            raise Error(
                "stopped in "
                + before
                + " after "
                + String(k)
                + " of "
                + String(len(steps))
                + " steps, moving to "
                + tr.to_names[i]
                + ": "
                + String(e)
            )
        var note = String()
        if not dry_run and last and res.id != "":
            keep_resolution(client, code, tr.task_id, res)
            note = ", resolution " + res.code + " (" + res.name + ")"
        if not dry_run:
            print(
                "moved "
                + ui.bold(code)
                + ": "
                + before
                + " → "
                + ui.status(tr.to_names[i])
                + note
            )
        tr.current = tr.to_names[i]
        tr.current_id = tr.to_ids[i]


def task_path(client: Client, args: Args, ui: Out) raises:
    args.check_known(["verbose", "v"])
    var code = args.need(2, "task code")
    var target = args.need(3, "status code or name")
    var tr = transitions_for(client, code)
    var want = String(target.strip()).lower()
    if want == tr.current.lower() or (
        tr.current_code != "" and want == tr.current_code.lower()
    ):
        print(tr.current + " (0 steps; already there)")
        return
    var steps = tr.path_to(target)
    if len(steps) == 0:
        raise Error(
            code
            + " is in "
            + tr.current
            + " and the workflow has no path to "
            + target
        )
    print(
        path_text(tr, steps)
        + ui.dim(
            "  ("
            + String(len(steps))
            + (" step)" if len(steps) == 1 else " steps)")
        )
    )
    for i in steps:
        if tr.limits[i] == "conditional":
            print(
                ui.dim(
                    "the move to "
                    + tr.to_names[i]
                    + " has a condition the server checks, often a role"
                )
            )
    print(
        ui.dim(
            "run it: eva task move "
            + code
            + " "
            + shell_word(target)
            + " --path"
        )
    )


def task_statuses(client: Client, args: Args, ui: Out) raises:
    args.check_known(["verbose", "v"])
    var code = args.need(2, "task code")
    var tr = transitions_for(client, code)
    print(
        ui.bold(code) + " is in " + ui.status(tr.current) + "; it can move to:"
    )
    var here = tr.from_here()
    for i in here:
        var line = (
            "  " + ui.accent(pad(tr.to_codes[i], 26)) + " " + tr.to_names[i]
        )
        if tr.froms[i] == FROM_ANY:
            line += ui.dim("  (from any status)")
        if tr.limits[i] == "conditional":
            line += ui.dim(
                "  (conditional: the server may refuse it for your role)"
            )
        print(line)
    if len(here) == 0:
        print(ui.dim("  nothing"))
    var automatic = 0
    for i in range(len(tr.trans_ids)):
        if tr.limits[i] == "automatic" and tr.starts_from(i, tr.current_id):
            automatic += 1
    if automatic > 0:
        print(ui.dim("  +" + String(automatic) + " automatic, not run by hand"))
    print(ui.dim("further statuses: eva task path " + code + " STATUS"))


def task_move(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        [
            "dry-run",
            "comment",
            "m",
            "set",
            "resolution",
            "r",
            "path",
            "verbose",
            "v",
        ]
    )
    var code = args.need(2, "task code")
    var target = args.need(
        3, "status code or name; see eva task statuses " + code
    )
    move_task(
        client,
        code,
        target,
        args.get("comment", "m"),
        args.get("set"),
        args.get("resolution", "r"),
        ui,
        args.has("path"),
        args.has("dry-run"),
    )


def resolution_list(client: Client, args: Args, ui: Out) raises:
    args.check_known(["json", "format", "verbose", "v"])
    var r = client.call(
        "CmfResolution.list", '{"fields":["code","name"],"slice":[0,500]}'
    )
    if want_json(args):
        print_json(r)
        return
    for i in range(r.doc.len(r.result)):
        var x = r.doc.at(r.result, i)
        print(
            ui.accent(pad(r.doc.text_at(x, "code"), 18))
            + " "
            + r.doc.text_at(x, "name")
        )
