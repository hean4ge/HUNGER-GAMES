"""Compare the draft files with the same files in a tree the diff was applied to (byte for byte).
Usage: python -I compare_tree.py <applied_root> <voice_mode_root>"""
import os
import sys


def long_path(p: str) -> str:
    p = os.path.abspath(p)
    prefix = "\\\\?\\"
    return prefix + p if os.name == "nt" and not p.startswith(prefix) else p


def main() -> None:
    applied, drafts = long_path(os.path.join(sys.argv[1], "src")), long_path(os.path.join(sys.argv[2], "src"))
    same, different, crlf = 0, [], []
    for root, _, files in os.walk(drafts):
        for name in files:
            if not name.endswith(".lua") or name.endswith(".snippet.lua"):
                continue
            mine = os.path.join(root, name)
            rel = os.path.relpath(mine, drafts)
            theirs = os.path.join(applied, rel)
            a = open(mine, "rb").read()
            b = open(theirs, "rb").read()
            if b"\r\n" in b:
                crlf.append(rel)
            if a == b:
                same += 1
            else:
                different.append(rel)
    print(f"{same} draft files byte-identical to the applied diff; {len(different)} different; {len(crlf)} with CRLF")
    for rel in different + crlf:
        print("  ", rel)


if __name__ == "__main__":
    main()
