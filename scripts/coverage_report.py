"""Merge gcov line counts of several binaries into a per-file summary of src/.

    python scripts/coverage_report.py OBJ_DIR SRC_DIR OUT_DIR

Each .gcda in OBJ_DIR is turned into .gcov text by `llvm-cov gcov` (on PATH).
A line is executable if any binary reports it with a count or `#####`, and
covered if any binary ran it.
"""

import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path


def main() -> None:
    obj, src, out = (Path(a).resolve() for a in sys.argv[1:4])
    executable: dict[str, set[int]] = defaultdict(set)
    covered: dict[str, set[int]] = defaultdict(set)
    for gcda in sorted(obj.glob("*.gcda")):
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(["llvm-cov", "gcov", "-p", "-o", str(obj), str(gcda)],
                           cwd=tmp, capture_output=True, text=True)
            for gcov in Path(tmp).glob("*.gcov"):
                lines = gcov.read_text(errors="replace").splitlines()
                source = next((l.split("Source:", 1)[1] for l in lines[:3] if "Source:" in l), "")
                if not source.startswith(str(src) + "/"):
                    continue
                name = source[len(str(src)) + 1:]
                for line in lines:
                    parts = line.split(":", 2)
                    if len(parts) < 3:
                        continue
                    count, lineno = parts[0].strip(), parts[1].strip()
                    if not lineno.isdigit() or lineno == "0" or count == "-":
                        continue
                    executable[name].add(int(lineno))
                    if count not in ("#####", "====="):
                        covered[name].add(int(lineno))

    rows = []
    for name in sorted(executable):
        n, c = len(executable[name]), len(covered[name] & executable[name])
        rows.append((name, n, c))
    total_n = sum(r[1] for r in rows)
    total_c = sum(r[2] for r in rows)
    width = max([len(r[0]) for r in rows] + [5])
    report = [f"{'file':<{width}}  lines  run   cover"]
    for name, n, c in rows:
        report.append(f"{name:<{width}}  {n:5d}  {c:5d}  {100 * c / n:5.1f}%")
    report.append(f"{'TOTAL':<{width}}  {total_n:5d}  {total_c:5d}  {100 * total_c / max(total_n, 1):5.1f}%")
    out.mkdir(parents=True, exist_ok=True)
    (out / "summary.txt").write_text("\n".join(report) + "\n")
    missed = []
    for name in sorted(executable):
        gaps = sorted(executable[name] - covered[name])
        if gaps:
            missed.append(f"{name}: {', '.join(map(str, gaps))}")
    (out / "missed-lines.txt").write_text("\n".join(missed) + "\n")
    print("\n".join(report))


if __name__ == "__main__":
    main()
