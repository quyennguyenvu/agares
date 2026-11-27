#!/usr/bin/env python3
"""Keeps the source files printed in the implementation plans equal to the real files.

A plan prints a file as a line "Write `path`:" followed by a fenced block. This lists every such
block that differs from the repo, and with --apply rewrites the ones named.

    python3 scripts/sync-plans.py                    list the differences, exit 1 on an unexpected one
    python3 scripts/sync-plans.py --apply KEY ...    rewrite those blocks from the repo
"""
import difflib
import glob
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
apply = set(sys.argv[2:]) if sys.argv[1:2] == ["--apply"] else None
# Meant to differ: Package.swift in the v1 plan's Task 1 is an earlier stage, and the rest are files
# a later plan replaced, kept as the plan that printed them built them.
EXPECTED = {
    f"{plan}::{path}#1"
    for plan, kept in (
        ("2026-11-24-agares-v1.md", (
            "Package.swift",
            "Sources/Agares/KeyTap.swift",
            "Sources/Agares/StatusMenu.swift",
            "Sources/Agares/Typist.swift",
            "Sources/Agares/main.swift",
            "Resources/Info.plist",
        )),
        ("2026-11-25-control-panel.md", (
            "Sources/Agares/AppModel.swift",
            "Sources/Agares/KeyTap.swift",
            "Sources/Agares/Panel.swift",
            "Sources/Agares/StatusMenu.swift",
            "Sources/Agares/UpdateCheck.swift",
        )),
    )
    for path in kept
}
drifted = False


def blocks(lines):
    i = 0
    while i < len(lines):
        if lines[i].startswith("Write `") and lines[i].endswith("`:"):
            path = lines[i][len("Write `"):-2]
            start = i + 1
            while not lines[start].startswith("```"):
                start += 1
            end = start + 1
            while not lines[end].startswith("```"):
                end += 1
            yield path, start + 1, end
            i = end
        i += 1


for plan in sorted(glob.glob(os.path.join(REPO, "docs/superpowers/plans/*.md"))):
    lines = open(plan, encoding="utf-8").read().split("\n")
    name = os.path.basename(plan)
    seen, edits = {}, []
    for path, start, end in blocks(lines):
        seen[path] = seen.get(path, 0) + 1
        key = f"{name}::{path}#{seen[path]}"
        current = open(os.path.join(REPO, path), encoding="utf-8").read().rstrip("\n").split("\n")
        if lines[start:end] != current:
            changed = sum(1 for d in difflib.ndiff(lines[start:end], current) if d[:1] in "+-")
            rewrite = apply is not None and key in apply
            label = "REWRITTEN" if rewrite else "EXPECTED " if key in EXPECTED else "DIFFERS  "
            drifted |= label == "DIFFERS  "
            print(f"{label} {key} ({changed} changed lines)")
            if rewrite:
                edits.append((start, end, current))
    for start, end, current in reversed(edits):
        lines[start:end] = current
    if edits:
        open(plan, "w", encoding="utf-8").write("\n".join(lines))

# Only the plain listing is a check; an --apply run reports what it rewrote.
sys.exit(1 if drifted and apply is None else 0)
