"""Writes the settings for the 3.3 art A/B test (2026-09-25): one monster (Petalpaw), three concept
models, then several image-to-3d settings from ONE concept so only the 3D settings differ.

The style block is the pilot's (tools/meshy/pilot/make_concepts.py), so the result can sit next to
Cindlet, Kindlefox and Blazefang. Sprout colours are Config.Elements.sprout.
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
SUBJECT = (
    "Petalpaw, a tiny baby flower fox kit, standing on all fours: a round chubby body, an oversized "
    "head, stubby legs, small rounded ears shaped like flower petals, a short fluffy tail that ends in "
    "a pink blossom, a little two-leaf sprout on top of the head. Leaf green fur (#62BF55), a pale "
    "mint belly and muzzle (#E0F6CF), bright spring green accents (#8EE07A), soft pink petal details. "
)

for model in ("nano-banana", "nano-banana-2", "nano-banana-pro"):
    settings = {"ai_model": model, "prompt": SUBJECT + CREATURE + STYLE, "aspect_ratio": "1:1", "remove_background": True}
    (HERE / f"concept-{model}.json").write_text(json.dumps(settings, indent=2), encoding="utf-8")

BASE = {"should_texture": True, "texture_resolution": "4k", "enable_pbr": True, "image_enhancement": False, "target_formats": ["glb", "fbx"]}
VARIANTS = {
    # The pilot's model at 4k (same price as 2k) with PBR maps (free), keeping the pre-remesh mesh.
    "m71": {"ai_model": "meshy-7.1", "should_remesh": True, "topology": "triangle", "target_polycount": 6000, "pose_mode": "", "save_pre_remeshed_model": True},
    # meshy-6 is the only model that honours remove_lighting (the pilot's setting was ignored by 7.1).
    "m6": {"ai_model": "meshy-6", "should_remesh": True, "topology": "triangle", "target_polycount": 6000, "pose_mode": "", "remove_lighting": True},
    # Smart Topology: half the price (15 textured), generated straight at the face count.
    "t2": {"model_type": "smart-topology", "ai_model": "meshy-t2", "target_polycount": 6000},
}
for name, extra in VARIANTS.items():
    settings = {**BASE, **extra}
    if name == "t2":
        settings.pop("image_enhancement")  # only meshy-6 / 7.1
    (HERE / f"model-{name}.json").write_text(json.dumps(settings, indent=2), encoding="utf-8")
print(sorted(p.name for p in HERE.glob("*.json")))
