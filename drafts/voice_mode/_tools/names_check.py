"""Rough check: names called or indexed in a Luau file that are never declared in it (locals, params, loop vars).
Not scope-aware; it only flags names that appear nowhere as a declaration. Usage: python -I names_check.py <files>"""
import os
import re
import sys

BUILTINS = set("""assert error getmetatable ipairs next pairs pcall print rawequal rawget rawset require select
setmetatable tonumber tostring type typeof unpack xpcall warn game workspace script Enum Instance Vector3 Vector2 CFrame
UDim UDim2 Color3 NumberRange NumberSequence NumberSequenceKeypoint RaycastParams TweenInfo Font Random task table string
math utf8 os debug coroutine bit32 buffer if else elseif while for function return and or not then do end local in repeat
until nil true false""".split())

LONG_COMMENT = re.compile(r"--\[(=*)\[.*?\]\1\]", re.S)
LINE_COMMENT = re.compile(r"--[^\n]*")
DQ = re.compile(r'"(?:\\.|[^"\\\n])*"')
SQ = re.compile(r"'(?:\\.|[^'\\\n])*'")


def strip(src: str) -> str:
    s = LONG_COMMENT.sub("", src)
    s = DQ.sub('""', s)
    s = SQ.sub("''", s)
    s = LINE_COMMENT.sub("", s)
    return s


def main() -> None:
    for path in sys.argv[1:]:
        with open(path, encoding="utf-8") as f:
            s = strip(f.read())
        declared = set(re.findall(r"\blocal\s+function\s+([A-Za-z_]\w*)", s))
        for m in re.finditer(r"\blocal\s+([^=\n]+)", s):
            head = re.sub(r":[^,]*", "", m.group(1))  # drop type annotations
            declared.update(re.findall(r"[A-Za-z_]\w*", head))
        for m in re.finditer(r"\bfunction\b[^(\n]*\(([^)]*)\)", s):
            params = re.sub(r":[^,]*", "", m.group(1))
            declared.update(re.findall(r"[A-Za-z_]\w*", params))
        for m in re.finditer(r"\bfor\s+([\w\s,]+?)\s+(?:in|=)", s):
            declared.update(re.findall(r"[A-Za-z_]\w*", m.group(1)))
        used = set(re.findall(r"(?<![.:\w])([A-Za-z_]\w*)\s*\(", s))
        used.update(re.findall(r"(?<![.:\w])([A-Za-z_]\w*)\s*[.:][A-Za-z_]", s))
        missing = sorted(n for n in used if n not in declared and n not in BUILTINS)
        print(os.path.basename(os.path.dirname(path)) + "/" + os.path.basename(path), "->", missing or "all defined")


if __name__ == "__main__":
    main()
