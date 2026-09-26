"""PROTOTYPE tool: MonsterLab.capture()'s JSON -> MonsterLibrary.luau.

    python prototypes/pet-genetics/write_monster_library.py <capture.json>
"""
import json
import os
import sys


def num(x):
    return "%g" % round(x, 4)


def main(path):
    lib = json.load(open(path, encoding="utf-8"))
    out = [
        "--[[",
        "\tPROTOTYPE monster library, written by write_monster_library.py from MonsterLab.capture()",
        "\t(do not edit by hand). The baby forms of Monster Ranch lines, made with Roblox's",
        "\tGenerateModelAsync in Pet Simulator style, split into animatable parts (monsters.py has the",
        "\tprompts and part lists), every part published as a mesh + texture asset. Per form: archetype,",
        "\thover, line, and per part its name, mesh, texture, size and CFrame relative to the body.",
        "]]",
        "",
        "return {",
    ]
    forms = sorted(lib, key=lambda f: (lib[f].get("line") or 0, f))
    for form in forms:
        e = lib[form]
        out.append(f"\t{form} = {{")
        out.append(f"\t\tarchetype = \"{e['archetype']}\",")
        out.append(f"\t\thover = {'true' if e['hover'] else 'false'},")
        out.append(f"\t\tline = {e.get('line') or 0},")
        out.append("\t\tparts = {")
        for p in sorted(e["parts"], key=lambda p: (p["name"] != "body", p["name"])):
            size = ", ".join(num(v) for v in p["size"])
            cf = ", ".join(num(v) for v in p["cframe"])
            out.append(
                f"\t\t\t{{ name = \"{p['name']}\", mesh = \"{p['mesh']}\", texture = \"{p['texture']}\", "
                f"size = {{ {size} }}, cframe = {{ {cf} }} }},"
            )
        out.append("\t\t},")
        out.append("\t},")
    out.append("}")
    target = os.path.join(os.path.dirname(os.path.abspath(__file__)), "MonsterLibrary.luau")
    with open(target, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")
    print(f"wrote {target}: {len(lib)} monsters")


if __name__ == "__main__":
    main(sys.argv[1])
