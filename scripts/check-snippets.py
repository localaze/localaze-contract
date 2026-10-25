#!/usr/bin/env python3
"""Checks that the code in a README is code the build compiles.

A README code block preceded by

    <!-- snippet: path/to/File.swift#name -->

must equal, after removing common indentation, the lines between

    // #region name
    // #endregion name

in that file, relative to the README. The file is part of a target CI already
builds, so a README example that stops compiling stops the build too: it can
only change by changing the file, and the file has to compile.

A block that cannot be compiled — a dependency line naming a published
version, say — is preceded by `<!-- uncompiled -->` instead, and counted, so
the exception is visible rather than silent.

Usage: check-snippets.py README.md [OTHER.md ...]
"""
import pathlib
import re
import sys
import textwrap

MARKER = re.compile(r"<!--\s*snippet:\s*(?P<file>[^#\s]+)#(?P<name>[\w-]+)\s*-->\s*\n```[\w-]*\n(?P<body>.*?)\n```", re.S)


def region(path: pathlib.Path, name: str) -> str | None:
    lines = path.read_text(encoding="utf-8").splitlines()
    start = end = None
    for index, line in enumerate(lines):
        stripped = line.strip()
        if re.fullmatch(rf"(//|#)\s*#region {re.escape(name)}", stripped):
            start = index + 1
        elif re.fullmatch(rf"(//|#)\s*#endregion {re.escape(name)}", stripped) and start is not None:
            end = index
            break
    if start is None or end is None:
        return None
    return textwrap.dedent("\n".join(lines[start:end])).strip("\n")


def check(readme: pathlib.Path) -> list[str]:
    problems = []
    text = readme.read_text(encoding="utf-8")
    found = list(MARKER.finditer(text))
    for match in found:
        source = (readme.parent / match["file"]).resolve()
        label = f"{readme}: snippet {match['file']}#{match['name']}"
        if not source.exists():
            problems.append(f"{label} names a file that does not exist")
            continue
        expected = region(source, match["name"])
        if expected is None:
            problems.append(f"{label} has no '#region {match['name']}' … '#endregion {match['name']}' in the file")
        elif match["body"].strip("\n") != expected:
            problems.append(f"{label} differs from the code in the file. Copy the region into the README.")
    uncompiled = len(re.findall(r"<!--\s*uncompiled\s*-->\s*\n```(dart|swift|kotlin|kts)\n", text))
    unmarked = len(re.findall(r"```(dart|swift|kotlin|kts)\n", text)) - len(found) - uncompiled
    if unmarked > 0:
        problems.append(f"{readme}: {unmarked} code block(s) in dart, swift or kotlin have no snippet marker, so nothing compiles them")
    print(f"{readme}: {len(found)} snippets checked, {uncompiled} marked uncompiled")
    return problems


def main() -> None:
    problems = [p for name in sys.argv[1:] for p in check(pathlib.Path(name))]
    if problems:
        print("\n".join(problems))
        sys.exit(1)


if __name__ == "__main__":
    main()
