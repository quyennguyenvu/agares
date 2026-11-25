#!/usr/bin/env python3
"""Keeps the source files printed in the implementation plans equal to the real files.

A plan prints a file as a line "Write `path`:" followed by a fenced block. This lists every such
block that differs from the repo, and with --apply rewrites the ones named.

    python3 scripts/sync-plans.py                    list the differences
    python3 scripts/sync-plans.py --apply KEY ...    rewrite those blocks from the repo

Five blocks in the v1 plan are meant to differ: Package.swift in Task 1 (an earlier stage) and
KeyTap.swift, StatusMenu.swift, main.swift and Info.plist, kept as the v1 versions.
"""
import difflib
import glob
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
apply = set(sys.argv[2:]) if sys.argv[1:2] == ["--apply"] else None


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
            print(f"{'REWRITTEN' if rewrite else 'DIFFERS  '} {key} ({changed} changed lines)")
            if rewrite:
                edits.append((start, end, current))
    for start, end, current in reversed(edits):
        lines[start:end] = current
    if edits:
        open(plan, "w", encoding="utf-8").write("\n".join(lines))
