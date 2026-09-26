"""Writes the pilot's text-to-image settings (one JSON per asset) next to this file.

The style block is shared so every asset reads as one game. Colours are the game's own:
Config.Elements ember (#F57A45 / #FFD2AE / #FFB547) and Build.luau's barn (#C8473C / #6B3A2A).
"""

import json
from pathlib import Path

HERE = Path(__file__).parent

STYLE = (
    "Stylized 3D render for a cozy monster-collecting game. Chunky, rounded, toy-like shapes, "
    "smooth matte surfaces, bright saturated colours, a simple readable silhouette. "
    "Full body, three-quarter front view, centred, plain white background, soft even lighting, "
    "no text, no ground shadow."
)
CREATURE = "Big glossy black eyes with a white highlight, a small happy mouth. "
EMBER = "Coral orange fur (#F57A45), a cream belly and muzzle (#FFD2AE), golden flame accents (#FFB547). "

ASSETS = {
    "cindlet-concept": "Cindlet, a tiny baby fire fox kit, standing on all fours: a round chubby body, "
    "an oversized head, stubby legs, small pointed ears with glowing yellow tips, a short fluffy tail "
    "with a tiny flame at the tip. " + EMBER + CREATURE,
    "kindlefox-concept": "Kindlefox, a young fire fox, standing on all fours: slimmer and taller than a kit, "
    "longer legs, big pointed ears, a bushy tail that ends in a flickering flame, a fluffy flame-shaped "
    "tuft on the chest. " + EMBER + CREATURE,
    "blazefang-concept": "Blazefang, a proud adult fire fox, standing on all fours in a confident stance: "
    "a strong body, two small fangs peeking out, a mane of stylized flames around the neck, three "
    "flame-tipped tails, golden markings on the legs. Deep coral orange and ember red fur (#F57A45, "
    "#E0482F), a cream belly (#FFD2AE), golden flame accents (#FFB547). Big glossy black eyes with a "
    "white highlight, a determined smile. ",
    "barn-concept": "A cozy cartoon ranch barn building for monsters: red plank walls (#C8473C) with "
    "white trim, a big X-braced double door at the front, a dark brown gabled roof (#6B3A2A), a small "
    "round hay-loft window above the door, a stone base. Wider than it is tall. ",
}

for name, subject in ASSETS.items():
    settings = {
        "ai_model": "nano-banana",
        "prompt": subject + STYLE,
        "aspect_ratio": "1:1",
        "remove_background": True,
    }
    (HERE / (name + ".json")).write_text(json.dumps(settings, indent=2), encoding="utf-8")
    print(name, len(settings["prompt"]), "chars")
