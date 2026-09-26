"""PROTOTYPE tool: turns the JSON that capture.luau returns into PartLibrary.luau.

    python prototypes/pet-genetics/write_library.py <lib.json>
"""
import json
import os
import sys

LOCI = ["body", "face", "ears", "tail", "legs", "back"]


def num(x):
    return ("%g" % x) if isinstance(x, float) else str(x)


def arr(a):
    return "{ " + ", ".join(num(x) for x in a) + " }"


def main(path):
    lib = json.load(open(path, encoding="utf-8"))
    out = [
        "--[[",
        "\tPROTOTYPE part library, written by write_library.py from capture.luau (do not edit by hand).",
        "\tPer species: `turn` (yaw that faces the pet to -Z), `body` (its body box over its largest",
        "\tdimension) and per locus the generated part: mesh + texture ids, `offset` from the body centre",
        "\tin body half-sizes, `scale` (size in the part's own axes over the body's largest dimension).",
        "\t`face` pieces ride on their own body (Assembler). All made with Roblox's generate_mesh",
        "\t(explicit segmentation), 2026-09-25; the prompts are in README.md.",
        "]]",
        "",
        "return {",
    ]
    for sp in sorted(lib):
        e = lib[sp]
        out += [f"\t{sp} = {{", f"\t\tturn = {num(e['turn'])},", f"\t\tbody = {arr(e['body'])},", "\t\tparts = {"]
        for locus in LOCI:
            p = e["parts"].get(locus)
            if p:
                out += [
                    f"\t\t\t{locus} = {{",
                    f"\t\t\t\tmesh = \"{p['mesh']}\",",
                    f"\t\t\t\ttexture = \"{p['texture']}\",",
                    f"\t\t\t\toffset = {arr(p['offset'])},",
                    f"\t\t\t\tscale = {arr(p['scale'])},",
                    "\t\t\t},",
                ]
        out += ["\t\t},", "\t},"]
    out.append("}")
    target = os.path.join(os.path.dirname(os.path.abspath(__file__)), "PartLibrary.luau")
    with open(target, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")
    print(f"wrote {target}: {len(lib)} species")


if __name__ == "__main__":
    main(sys.argv[1])
