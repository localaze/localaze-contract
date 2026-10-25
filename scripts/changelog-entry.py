#!/usr/bin/env python3
"""Prints one version's entry from one or more changelogs, for release notes.

    changelog-entry.py 0.2.0 CHANGELOG.md android/CHANGELOG.md

Each changelog has a heading `## <version> — <date>` once released, which the
release command writes in place of `## Unreleased`. A changelog without an
entry for the version is an error: a release with no notes is a release
nobody can read.
"""
import pathlib
import re
import sys


def entry(path: pathlib.Path, version: str) -> str:
    text = path.read_text(encoding="utf-8")
    match = re.search(rf"^## {re.escape(version)}\b.*?$\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not match:
        sys.exit(f"{path} has no entry for {version}")
    return match.group(1).strip()


def main() -> None:
    version, *files = sys.argv[1:]
    paths = [pathlib.Path(name) for name in files]
    if len(paths) == 1:
        print(entry(paths[0], version))
        return
    for path in paths:
        title = path.parent.name if path.parent.name not in ("", ".") else "core"
        print(f"### {title}\n\n{entry(path, version)}\n")


if __name__ == "__main__":
    main()
