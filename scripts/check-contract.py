#!/usr/bin/env python3
"""Checks the contract is well formed before any SDK is run against it.

Every .json file parses, every conformance case has a unique id, a group and
an expectation, and every fixture a case names exists. A malformed contract
would otherwise surface as three SDKs failing in three different ways.
"""
import json
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
problems = []

for path in sorted(root.rglob("*.json")):
    if ".git" in path.parts:
        continue
    try:
        json.loads(path.read_text(encoding="utf-8"))
    except ValueError as error:
        problems.append(f"{path.relative_to(root)} is not valid JSON: {error}")

cases = json.loads((root / "conformance.json").read_text(encoding="utf-8"))["cases"]
seen = set()
for case in cases:
    case_id = case.get("id")
    if not case_id:
        problems.append(f"a case has no id: {case}")
        continue
    if case_id in seen:
        problems.append(f"{case_id} appears twice")
    seen.add(case_id)
    for field in ("group", "expect"):
        if not case.get(field):
            problems.append(f"{case_id} has no {field}")
    for value in case.values():
        for named in re.findall(r"fixtures/[\w./-]*\w", value if isinstance(value, str) else ""):
            if not (root / named).exists():
                problems.append(f"{case_id} names {named}, which does not exist")

if problems:
    print("\n".join(problems))
    sys.exit(1)
print(f"{len(cases)} conformance cases, every JSON file valid")
