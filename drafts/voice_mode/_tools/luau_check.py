"""A small structural checker for Luau source (no Luau toolchain on this machine).

Checks: block keywords balance (function/if/for/while/do/repeat ... end/until, with Luau if-expressions that take no
`end`), bracket balance, unterminated strings and comments, `!=`, and a few Lua-isms that Luau rejects.
It is not a parser: it catches the usual slips (a missing `end`, a stray bracket), not type or name errors.
Usage: python -I luau_check.py <file.lua>...
"""
import os
import re
import sys

KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil", "not",
    "or", "repeat", "return", "then", "true", "until", "while", "continue",
}
# a token after which `if` starts an expression (Luau if-then-else expression), not a statement
EXPR_PREV = {
    "=", "(", ",", "{", "[", "return", "and", "or", "not", "..", "+", "-", "*", "/", "//", "%", "^", "==", "~=",
    "<", ">", "<=", ">=", "+=", "-=", "*=", "/=", "//=", "%=", "^=", "..=",
}
PUNCT = sorted(
    ["...", "..=", "//=", "..", "==", "~=", "<=", ">=", "+=", "-=", "*=", "/=", "%=", "^=", "::", "->", "//",
     "+", "-", "*", "/", "%", "^", "#", "<", ">", "=", "(", ")", "{", "}", "[", "]", ";", ":", ",", ".", "?", "|", "&"],
    key=len, reverse=True,
)


def tokens(src: str, errors: list):
    i, n, line = 0, len(src), 1
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
            continue
        if c in " \t\r":
            i += 1
            continue
        if src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                close = "]" + m.group(1) + "]"
                j = src.find(close, i + len(m.group(0)))
                if j < 0:
                    errors.append(f"line {line}: unterminated long comment")
                    return
                line += src.count("\n", i, j)
                i = j + len(close)
            else:
                j = src.find("\n", i)
                i = n if j < 0 else j
            continue
        m = re.match(r"\[(=*)\[", src[i:])
        if m:
            close = "]" + m.group(1) + "]"
            j = src.find(close, i + len(m.group(0)))
            if j < 0:
                errors.append(f"line {line}: unterminated long string")
                return
            yield ("str", "[[...]]", line)
            line += src.count("\n", i, j)
            i = j + len(close)
            continue
        if c in "\"'`":
            j = i + 1
            while j < n and src[j] != c:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == "\n" and c != "`":
                    errors.append(f"line {line}: newline inside a string")
                    break
                j += 1
            if j >= n:
                errors.append(f"line {line}: unterminated string")
                return
            yield ("str", src[i:j + 1], line)
            i = j + 1
            continue
        m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", src[i:])
        if m:
            word = m.group(0)
            yield ("kw" if word in KEYWORDS else "name", word, line)
            i += len(word)
            continue
        m = re.match(r"0[xX][0-9a-fA-F_]+|0[bB][01_]+|[0-9][0-9_]*\.?[0-9_]*(?:[eE][+-]?[0-9]+)?|\.[0-9]+", src[i:])
        if m:
            yield ("num", m.group(0), line)
            i += len(m.group(0))
            continue
        if src.startswith("!=", i):
            errors.append(f"line {line}: '!=' is not Luau (use ~=)")
            i += 2
            continue
        for p in PUNCT:
            if src.startswith(p, i):
                yield ("op", p, line)
                i += len(p)
                break
        else:
            errors.append(f"line {line}: unexpected character {c!r}")
            i += 1


def check(path: str) -> list:
    full = os.path.abspath(path)
    prefix = "\\\\?\\"  # the Windows long-path prefix, for paths past 260 characters
    if os.name == "nt" and not full.startswith(prefix):
        full = prefix + full
    with open(full, encoding="utf-8", newline="") as f:
        src = f.read()
    errors: list = []
    blocks = []  # (kind, line)
    brackets = []  # (char, line)
    pending_do = []  # bracket depths at which a for/while waits for its `do`
    prev = None
    prev_prev = None
    pairs = {")": "(", "}": "{", "]": "["}
    for kind, text, line in tokens(src, errors):
        depth = len(brackets)
        if kind == "op" and text in "({[":
            brackets.append((text, line))
        elif kind == "op" and text in ")}]":
            if not brackets or brackets[-1][0] != pairs[text]:
                errors.append(f"line {line}: '{text}' closes nothing (or the wrong bracket)")
            else:
                brackets.pop()
        elif kind == "kw":
            # a keyword used as a field name (x.end / x:end) isn't Luau
            if prev and prev[1] in (".", ":") and prev[0] == "op" and text not in ("nil",):
                errors.append(f"line {line}: keyword '{text}' used as a field name")
            if text == "function":
                blocks.append(("function", line))
            elif text == "if":
                # after `=`, `(`, `,`, `return`, an operator...: a Luau if-expression (no `end`)
                is_expr = prev is not None and prev[1] in EXPR_PREV and prev[0] in ("op", "kw")
                if not is_expr:
                    blocks.append(("if", line))
            elif text in ("for", "while"):
                blocks.append((text, line))
                pending_do.append(depth)
            elif text == "do":
                if pending_do and pending_do[-1] == depth:
                    pending_do.pop()
                else:
                    blocks.append(("do", line))
            elif text == "repeat":
                blocks.append(("repeat", line))
            elif text == "until":
                if not blocks or blocks[-1][0] != "repeat":
                    errors.append(f"line {line}: 'until' without 'repeat'")
                else:
                    blocks.pop()
            elif text == "end":
                if not blocks:
                    errors.append(f"line {line}: 'end' closes nothing")
                elif blocks[-1][0] == "repeat":
                    errors.append(f"line {line}: 'end' where 'until' was expected (repeat at line {blocks[-1][1]})")
                    blocks.pop()
                else:
                    blocks.pop()
        prev_prev = prev
        prev = (kind, text)
    for kind, line in blocks:
        errors.append(f"line {line}: '{kind}' is never closed")
    for char, line in brackets:
        errors.append(f"line {line}: '{char}' is never closed")
    if pending_do:
        errors.append("a for/while is missing its 'do'")
    if "\r\n" in src:
        errors.append("CRLF line endings (the repo keeps LF)")
    return errors


def main() -> int:
    bad = 0
    for path in sys.argv[1:]:
        errors = check(path)
        name = path.replace("\\", "/").split("/src/")[-1]
        if errors:
            bad += 1
            print(f"FAIL {name}")
            for e in errors[:20]:
                print("   ", e)
        else:
            print(f"ok   {name}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
