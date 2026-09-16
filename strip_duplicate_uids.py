#!/usr/bin/env python3
"""
Strip duplicate gd_scene self-UIDs from a fixed list of .tscn files.

WHAT THIS DOES (and only this):
  - For each path listed in strip_list.txt, opens the file
  - Confirms line 1 starts with "[gd_scene" and contains a uid="uid://..." attribute
  - Removes ONLY that ` uid="uid://xxxxxxxxxxxxx"` chunk from line 1
  - Leaves every other line, every other attribute, and file encoding untouched
  - Writes a .bak copy of the original file next to it before changing anything

WHAT THIS DOES NOT DO:
  - Does not touch any file not explicitly listed in strip_list.txt
  - Does not invent, guess, or assign a new UID - that only happens when
    YOU open the file in the Godot editor and save it afterward
  - Does not touch the 48 "KEEP" files - those are correct as-is

USAGE:
  1. Put this script and strip_list.txt in your project root
     (C:/Users/White/Documents/Top_Gun_Pinball/)
  2. Dry run first (default - makes no changes, just shows what would happen):
       python strip_duplicate_uids.py
  3. Review the output. If it looks right, apply for real:
       python strip_duplicate_uids.py --apply
  4. Then open each changed file in the Godot editor and save it (Ctrl+S)
     to let Godot assign each one a fresh, unique UID.
"""

import re
import sys
import os

LIST_FILE = "strip_list.txt"
UID_PATTERN = re.compile(r'\s*uid="uid://[a-z0-9]+"')


def process_file(path, apply_changes):
    if not os.path.isfile(path):
        print(f"  SKIP (not found): {path}")
        return False

    with open(path, "rb") as f:
        raw = f.read()

    # Preserve original line ending style
    newline = b"\r\n" if b"\r\n" in raw[:200] else b"\n"
    lines = raw.split(newline)

    if not lines:
        print(f"  SKIP (empty file): {path}")
        return False

    first_line = lines[0].decode("utf-8", errors="strict")

    if not first_line.startswith("[gd_scene"):
        print(f"  SKIP (line 1 isn't a gd_scene header, file may already be fixed or list is stale): {path}")
        return False

    if 'uid="uid://' not in first_line:
        print(f"  SKIP (no uid attribute present, already stripped?): {path}")
        return False

    new_first_line, n = UID_PATTERN.subn("", first_line)
    if n != 1:
        print(f"  SKIP (expected exactly 1 uid attribute, found {n}, leaving untouched for manual review): {path}")
        return False

    print(f"  {'WOULD EDIT' if not apply_changes else 'EDITING'}: {path}")
    print(f"    before: {first_line}")
    print(f"    after:  {new_first_line}")

    if apply_changes:
        backup_path = path + ".bak"
        if not os.path.exists(backup_path):
            with open(backup_path, "wb") as bf:
                bf.write(raw)
        lines[0] = new_first_line.encode("utf-8")
        with open(path, "wb") as f:
            f.write(newline.join(lines))

    return True


def main():
    apply_changes = "--apply" in sys.argv

    if not os.path.isfile(LIST_FILE):
        print(f"ERROR: {LIST_FILE} not found next to this script.")
        sys.exit(1)

    with open(LIST_FILE, "r", encoding="utf-8") as f:
        paths = [line.strip() for line in f if line.strip()]

    print(f"Mode: {'APPLY (writing changes + .bak backups)' if apply_changes else 'DRY RUN (no changes will be written)'}")
    print(f"Files listed: {len(paths)}")
    print()

    changed = 0
    skipped = 0
    for path in paths:
        ok = process_file(path, apply_changes)
        if ok:
            changed += 1
        else:
            skipped += 1

    print()
    print(f"Done. {changed} file(s) {'edited' if apply_changes else 'would be edited'}, {skipped} skipped.")
    if not apply_changes:
        print("This was a dry run - no files were changed. Re-run with --apply to actually write changes.")


if __name__ == "__main__":
    main()
