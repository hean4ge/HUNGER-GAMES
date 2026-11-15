"""Make patches/voice_mode.diff from the drafts in voice_mode/src (the source of truth) against the repo's src.

It runs `git diff --no-index --full-index` on two scratch trees, so the patch carries each original file's full blob id:
`git apply --3way` can then merge it into a src/ that the testers changed during release QA (the base blobs are in the
repo's history). LF line endings are kept. The repo itself is only read.
Usage: python -I make_diff.py <repo_root> <voice_mode_root>
"""
import os
import shutil
import subprocess
import sys


def long_path(p: str) -> str:
    p = os.path.abspath(p)
    prefix = "\\\\?\\"
    return prefix + p if os.name == "nt" and not p.startswith(prefix) else p


def draft_files(drafts_src: str):
    for root, _, files in os.walk(long_path(drafts_src)):
        for name in files:
            if name.endswith(".lua") and not name.endswith(".snippet.lua"):
                full = os.path.join(root, name)
                yield os.path.relpath(full, long_path(drafts_src)).replace("\\", "/")


def main() -> None:
    repo, vm = sys.argv[1], sys.argv[2]
    work = os.path.join(vm, "_build", "diff")
    if os.path.isdir(long_path(work)):
        shutil.rmtree(long_path(work))
    base, new = os.path.join(work, "base"), os.path.join(work, "new")
    rels = sorted(draft_files(os.path.join(vm, "src")))
    for rel in rels:
        parts = rel.split("/")
        src_repo = os.path.join(repo, "src", *parts)
        src_draft = os.path.join(vm, "src", *parts)
        dst_new = os.path.join(new, "src", *parts)
        os.makedirs(long_path(os.path.dirname(dst_new)), exist_ok=True)
        shutil.copyfile(long_path(src_draft), long_path(dst_new))
        if os.path.isfile(long_path(src_repo)):
            dst_base = os.path.join(base, "src", *parts)
            os.makedirs(long_path(os.path.dirname(dst_base)), exist_ok=True)
            shutil.copyfile(long_path(src_repo), long_path(dst_base))
    os.makedirs(long_path(os.path.join(base, "src")), exist_ok=True)
    cmd = ["git", "-c", "core.autocrlf=false", "-c", "core.safecrlf=false", "diff", "--no-index", "--full-index",
           "--no-color", "--no-renames", "base", "new"]
    result = subprocess.run(cmd, cwd=work, capture_output=True)
    if result.returncode not in (0, 1):
        raise SystemExit(result.stderr.decode("utf-8", "replace"))
    text = result.stdout.decode("utf-8")
    text = text.replace(" a/base/src/", " a/src/").replace(" b/new/src/", " b/src/")
    text = text.replace(" a/new/src/", " a/src/")  # (a new file's "diff --git" line names it on both sides)
    text = text.replace("--- a/base/src/", "--- a/src/").replace("+++ b/new/src/", "+++ b/src/")
    assert "/base/" not in text and "/new/src" not in text, "path rewrite missed a header"
    assert "\r\n" not in text, "CRLF in the patch"
    out = os.path.join(vm, "patches", "voice_mode.diff")
    with open(long_path(out), "w", encoding="utf-8", newline="") as f:
        f.write(text)
    changed = sum(1 for rel in rels if os.path.isfile(long_path(os.path.join(repo, "src", *rel.split("/")))))
    print(f"wrote {out}: {len(rels)} files ({changed} changed, {len(rels) - changed} new), {text.count(chr(10))} lines")


if __name__ == "__main__":
    main()
