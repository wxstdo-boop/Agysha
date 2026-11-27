#!/usr/bin/env python3
"""Turn `git log --pretty=format:'%s%x1f%b%x1e'` output into note lines.

One record per commit: subject becomes a bullet, the prose of the body
becomes its detail. Markdown noise (headings, tables, fences, rules) and
empty lines are dropped — tool/release_notes.sh does the rest of the
humanising. Kept as a file rather than an inline heredoc so ship.yml stays
valid YAML.
"""

import sys


def main() -> int:
    raw = sys.stdin.read()
    for record in raw.split("\x1e"):
        record = record.strip("\n")
        if not record.strip():
            continue
        subject, _, body = record.partition("\x1f")
        subject = subject.strip()
        if not subject:
            continue
        print("- " + subject)
        # Только первый абзац тела: остальные — обычно разбор по пунктам,
        # и в заметке они превращаются в простыню на четыреста слов.
        first = body.split("\n\n", 1)[0]
        prose = []
        for line in first.splitlines():
            line = line.strip()
            if not line or line.startswith(("#", "|", "```", "---")):
                continue
            prose.append(line)
        text = " ".join(prose).strip()
        if text:
            print("  " + text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
