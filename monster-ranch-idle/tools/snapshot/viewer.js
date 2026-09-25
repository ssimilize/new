// Draws scene.json (tools/snapshot/scene.luau) the way Roblox would, closely enough for a
// progress snapshot: parts with three.js, the PlayerGui tree with HTML and CSS layout.
import * as THREE from "three";

const params = new URLSearchParams(location.search);
const scene = await (await fetch(params.get("scene") || "/scene.json")).json();
const [W, H] = scene.viewport;

// ── 3D ────────────────────────────────────────────────────────────────────────────────
const renderer = new THREE.WebGLRenderer({ canvas: document.getElementById("gl"), antialias: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(window.devicePixelRatio);
renderer.setSize(W, H, false);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;

const world = new THREE.Scene();
world.background = new THREE.Color().setRGB(0.66, 0.84, 1.0, THREE.SRGBColorSpace);
world.fog = new THREE.Fog(world.background, 260, 900);
world.add(new THREE.HemisphereLight(0xd8ecff, 0x7f9f5c, 1.35));
const sun = new THREE.DirectionalLight(0xfff2dc, 2.4);
sun.castShadow = true;
sun.shadow.mapSize.set(4096, 4096);
sun.shadow.bias = -0.0004;
sun.shadow.normalBias = 0.3;
Object.assign(sun.shadow.camera, { left: -220, right: 220, top: 220, bottom: -220, near: 1, far: 900 });
world.add(sun, sun.target);

const srgb = (c) => new THREE.Color().setRGB(c[0] / 255, c[1] / 255, c[2] / 255, THREE.SRGBColorSpace);

function wedgeGeometry() {
  // Roblox WedgePart: full bottom and back (+Z) faces, slope from top-back to bottom-front.
  const A = [-0.5, -0.5, -0.5], B = [0.5, -0.5, -0.5], C = [0.5, -0.5, 0.5], D = [-0.5, -0.5, 0.5];
  const E = [-0.5, 0.5, 0.5], F = [0.5, 0.5, 0.5];
  const tris = [A, C, B, A, D, C, D, E, F, D, F, C, A, B, F, A, F, E, A, E, D, B, C, F];
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(tris.flat(), 3));
  g.computeVertexNormals();
  return g;
}
const GEO = {
  box: new THREE.BoxGeometry(1, 1, 1),
  sphere: new THREE.SphereGeometry(0.5, 28, 18),
  cylinder: new THREE.CylinderGeometry(0.5, 0.5, 1, 28).rotateZ(Math.PI / 2),
  wedge: wedgeGeometry(),
};

function material(p) {
  const color = srgb(p.c);
  const opts = { color, roughness: 0.75, metalness: 0 };
  if (p.mat === "Neon") Object.assign(opts, { emissive: color, emissiveIntensity: 0.55, roughness: 0.4 });
  if (p.mat === "Glass") Object.assign(opts, { roughness: 0.08, transparent: true, opacity: 0.45 });
  // No environment map to reflect, so metal stays mostly diffuse (Roblox shades it brightly).
  if (p.mat === "Metal") Object.assign(opts, { roughness: 0.3, metalness: 0.25 });
  if (["Grass", "Ground", "Slate", "Pebble", "Wood", "WoodPlanks", "Sand"].includes(p.mat)) opts.roughness = 0.95;
  if (p.t > 0) Object.assign(opts, { transparent: true, opacity: Math.max(0.05, 1 - p.t) });
  return new THREE.MeshStandardMaterial(opts);
}

for (const p of scene.parts) {
  let geo = GEO.box;
  let size = new THREE.Vector3(...p.z);
  if (p.m === "Sphere") geo = GEO.sphere;
  else if (p.k === "WedgePart") geo = GEO.wedge;
  else if (p.s === "Ball") { geo = GEO.sphere; const d = Math.min(...p.z); size.set(d, d, d); }
  else if (p.s === "Cylinder") { geo = GEO.cylinder; const d = Math.min(p.z[1], p.z[2]); size.set(p.z[0], d, d); }
  const mesh = new THREE.Mesh(geo, material(p));
  const [x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22] = p.cf;
  const m = new THREE.Matrix4().set(r00, r01, r02, x, r10, r11, r12, y, r20, r21, r22, z, 0, 0, 0, 1);
  m.multiply(new THREE.Matrix4().makeScale(size.x, size.y, size.z));
  mesh.matrixAutoUpdate = false;
  mesh.matrix.copy(m);
  mesh.castShadow = p.t < 0.5 && p.mat !== "Neon";
  mesh.receiveShadow = true;
  world.add(mesh);
}

// A blocky avatar on the path in front of the ranch.
const [cx, , cz] = scene.plot.center;
const toHub = new THREE.Vector3(-cx, 0, -cz).normalize();
const side = new THREE.Vector3(toHub.z, 0, -toHub.x);
const avatarAt = new THREE.Vector3(cx, 0, cz).addScaledVector(toHub, 58).addScaledVector(side, -6);
{
  const g = new THREE.Group();
  const part = (w, h, d, color, x, y, z) => {
    const mesh = new THREE.Mesh(GEO.box, new THREE.MeshStandardMaterial({ color: srgb(color), roughness: 0.7 }));
    mesh.scale.set(w, h, d); mesh.position.set(x, y, z); mesh.castShadow = true; g.add(mesh);
  };
  part(2, 2, 1, [13, 105, 172], 0, 3, 0);          // torso
  part(1, 2, 1, [245, 205, 48], -1.5, 3, 0);       // arms
  part(1, 2, 1, [245, 205, 48], 1.5, 3, 0);
  part(1, 2, 1, [164, 189, 71], -0.5, 1, 0);       // legs
  part(1, 2, 1, [164, 189, 71], 0.5, 1, 0);
  const head = new THREE.Mesh(new THREE.CylinderGeometry(0.6, 0.6, 1.2, 20), new THREE.MeshStandardMaterial({ color: srgb([245, 205, 48]) }));
  head.position.set(0, 4.6, 0); head.castShadow = true; g.add(head);
  if (scene.avatar) {
    // The harness character's root part: the blocky body stands 3 studs below it.
    const [x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22] = scene.avatar;
    g.matrixAutoUpdate = false;
    g.matrix.set(r00, r01, r02, x, r10, r11, r12, y - 3, r20, r21, r22, z, 0, 0, 0, 1);
    g.rotation.setFromRotationMatrix(g.matrix);
  } else {
    g.position.copy(avatarAt);
    g.lookAt(new THREE.Vector3(cx, 0, cz));
  }
  world.add(g);
}

// Camera: over the player's shoulder toward their ranch, the hub behind.
const camera = new THREE.PerspectiveCamera(50, W / H, 0.5, 2000);
// ?cam=toHub,side,up,lookToHub overrides the framing (studs, relative to the plot).
const [camHub, camSide, camUp, lookHub] = (params.get("cam") || "95,40,58,4").split(",").map(Number);
const eye = new THREE.Vector3(cx, camUp, cz).addScaledVector(toHub, camHub).addScaledVector(side, camSide);
camera.position.copy(eye);
camera.lookAt(new THREE.Vector3(cx, 2, cz).addScaledVector(toHub, lookHub));
// ?eye=x,y,z&at=x,y,z places the camera in world studs instead (close-ups).
if (params.get("eye") && params.get("at")) {
  camera.position.set(...params.get("eye").split(",").map(Number));
  camera.lookAt(new THREE.Vector3(...params.get("at").split(",").map(Number)));
}
if (params.get("fov")) { camera.fov = Number(params.get("fov")); camera.updateProjectionMatrix(); }
sun.position.set(cx + 160, 260, cz + 90);
sun.target.position.set(cx, 0, cz);
renderer.render(world, camera);

// ── GUI ───────────────────────────────────────────────────────────────────────────────
const FONTS = {
  FredokaOne: "'Fredoka', 'Fredoka One', system-ui, sans-serif",
  GothamBold: "'Montserrat', system-ui, sans-serif",
  SourceSansBold: "'Source Sans 3', system-ui, sans-serif",
  Code: "monospace",
};
const WEIGHT = { FredokaOne: 600, GothamBold: 700, SourceSansBold: 700 };
const css = (u, axis) => `calc(${u[axis * 2] * 100}% + ${u[axis * 2 + 1]}px)`;
const rgba = (c, t = 0) => `rgba(${c[0]},${c[1]},${c[2]},${1 - (t ?? 0)})`;
const scaled = [];

function helper(node, kind) {
  return (node.ch || []).find((c) => c.k === kind);
}

function build(node, parent, layout) {
  if (node.v === false) return;
  const el = document.createElement("div");
  el.dataset.name = node.n;
  const flow = layout === "list" || layout === "grid" || layout === "stack";
  el.style.position = flow ? "relative" : "absolute";
  if (node.size) {
    const autoX = node.auto === "X" || node.auto === "XY";
    const autoY = node.auto === "Y" || node.auto === "XY";
    el.style.width = autoX ? "max-content" : css(node.size, 0);
    el.style.height = autoY ? "auto" : css(node.size, 1);
    if (autoX) el.style.minWidth = css(node.size, 0);
    if (autoY) el.style.minHeight = css(node.size, 1);
  }
  if (layout === "grid") { el.style.width = "100%"; el.style.height = "100%"; }
  if (!flow && node.pos) {
    el.style.left = css(node.pos, 0);
    el.style.top = css(node.pos, 1);
  }
  const t = [];
  if (!flow && node.anchor && (node.anchor[0] || node.anchor[1])) t.push(`translate(${-node.anchor[0] * 100}%, ${-node.anchor[1] * 100}%)`);
  if (node.rot) t.push(`rotate(${node.rot}deg)`);
  if (t.length) el.style.transform = t.join(" ");
  if (flow) el.style.order = String(node.lo || 0);
  if (layout === "stack") {
    el.style.gridArea = "1 / 1";
    if (node.pos) {
      el.style.marginLeft = `${node.pos[1]}px`;
      el.style.marginTop = `${node.pos[3]}px`;
    }
  }
  el.style.zIndex = String(node.z ?? 1);
  if (node.bg && node.bgt !== undefined && node.bgt < 1) el.style.background = rgba(node.bg, node.bgt);
  if (node.clip) el.style.overflow = "hidden";

  const corner = helper(node, "UICorner");
  if (corner) el.style.borderRadius = corner.r[0] >= 0.5 ? "9999px" : corner.r[0] > 0 ? `${corner.r[0] * 100}%` : `${corner.r[1]}px`;
  const gradient = helper(node, "UIGradient");
  if (gradient && gradient.g && node.bgt < 1) {
    const stops = gradient.g.map(([time, c]) => `rgb(${(c[0] * node.bg[0]) / 255},${(c[1] * node.bg[1]) / 255},${(c[2] * node.bg[2]) / 255}) ${time * 100}%`);
    el.style.background = `linear-gradient(${(gradient.grot || 0) + 90}deg, ${stops.join(",")})`;
  }
  const stroke = helper(node, "UIStroke");
  const isText = typeof node.text === "string";
  if (stroke && !(isText && stroke.mode !== "Border")) {
    el.style.boxShadow = `0 0 0 ${stroke.th}px ${rgba(stroke.sc, stroke.st)}`;
  }
  const scale = helper(node, "UIScale");
  if (scale && scale.scale !== 1) el.style.zoom = String(scale.scale);

  if (isText && node.text !== "" && (node.ttr ?? 0) < 1) {
    const box = document.createElement("div");
    box.className = "txt";
    const span = document.createElement("span");
    span.textContent = node.text;
    box.style.justifyContent = { Left: "flex-start", Right: "flex-end" }[node.tx] || "center";
    box.style.alignItems = { Top: "flex-start", Bottom: "flex-end" }[node.ty] || "center";
    box.style.textAlign = { Left: "left", Right: "right" }[node.tx] || "center";
    span.style.fontFamily = FONTS[node.font] || FONTS.GothamBold;
    span.style.fontWeight = String(WEIGHT[node.font] || 700);
    span.style.fontSize = `${node.ts || 14}px`;
    span.style.color = rgba(node.tc || [0, 0, 0], node.ttr);
    span.style.whiteSpace = node.twrap || node.tscaled ? "pre-wrap" : "pre";
    if (stroke && stroke.mode !== "Border") {
      const s = Math.max(1, stroke.th);
      const c = rgba(stroke.sc, stroke.st);
      span.style.textShadow = [[-s, 0], [s, 0], [0, -s], [0, s], [-s, -s], [s, s], [-s, s], [s, -s]].map(([x, y]) => `${x}px ${y}px 0 ${c}`).join(",");
    }
    box.appendChild(span);
    el.appendChild(box);
    if (node.tscaled) scaled.push([el, span]);
    if (node.auto === "X" || node.auto === "XY") {
      // Auto-width text sizes its label; centre it vertically inside the label's height.
      box.style.position = "relative";
      el.style.display = "flex";
      el.style.alignItems = { Top: "flex-start", Bottom: "flex-end" }[node.ty] || "center";
    }
  }

  // Children: padding makes an inner box; list/grid layouts become flex/grid.
  let inner = el;
  const pad = helper(node, "UIPadding");
  if (pad) {
    inner = document.createElement("div");
    const [pt, pr, pb, pl] = pad.p;
    Object.assign(inner.style, { position: "absolute", left: `${pl}px`, top: `${pt}px`, right: `${pr}px`, bottom: `${pb}px` });
    el.appendChild(inner);
  }
  const list = helper(node, "UIListLayout");
  const grid = helper(node, "UIGridLayout");
  let childLayout = null;
  // Zero-size wrappers with AutomaticSize (e.g. the HUD's tap holders around pills).
  const autoSized = node.auto && node.auto !== "None" && !isText && node.size && node.size.every((v) => v === 0);
  if (list) {
    const row = list.dir === "Horizontal";
    const gap = list.pad ? `${list.pad[1]}px` : "0px";
    const main = row ? { Left: "flex-start", Center: "center", Right: "flex-end" }[list.ha] : { Top: "flex-start", Center: "center", Bottom: "flex-end" }[list.va];
    const cross = row ? { Top: "flex-start", Center: "center", Bottom: "flex-end" }[list.va] : { Left: "flex-start", Center: "center", Right: "flex-end" }[list.ha];
    const box = inner === el ? el : inner;
    Object.assign(box.style, { display: "flex", flexDirection: row ? "row" : "column", gap, justifyContent: main || "flex-start", alignItems: cross || "flex-start" });
    if (node.auto) box.style.position = box.style.position || "relative";
    childLayout = "list";
  } else if (autoSized && !grid) {
    // AutomaticSize grows to fit children even when they are placed freely: stack them in
    // one grid cell so they overlap (like Roblox) and still size the container.
    Object.assign(inner.style, { display: "grid" });
    childLayout = "stack";
  } else if (grid) {
    const box = inner;
    const cw = grid.cell[1], ch = grid.cell[3];
    Object.assign(box.style, {
      display: "grid",
      gridTemplateColumns: `repeat(auto-fill, ${cw}px)`,
      gridAutoRows: `${ch}px`,
      gap: `${grid.cpad[3]}px ${grid.cpad[1]}px`,
      justifyContent: grid.ha === "Center" ? "center" : "start",
      alignContent: "start",
    });
    childLayout = "grid";
  }
  for (const child of node.ch || []) {
    if (child.k && !child.k.startsWith("UI")) build(child, inner, childLayout);
  }
  parent.appendChild(el);
}

const ui = document.getElementById("ui");
if (params.get("noui")) scene.gui = [];
for (const gui of scene.gui.sort((a, b) => (a.order || 0) - (b.order || 0))) {
  const root = document.createElement("div");
  Object.assign(root.style, { position: "absolute", inset: "0" });
  for (const child of gui.ch || []) if (!child.k.startsWith("UI")) build(child, root, null);
  ui.appendChild(root);
}
await document.fonts.ready;
for (const [el, span] of scaled) {
  let size = Math.max(8, Math.floor(el.clientHeight * 0.9));
  span.style.fontSize = `${size}px`;
  while (size > 6 && (span.offsetWidth > el.clientWidth || span.offsetHeight > el.clientHeight)) {
    size -= 1;
    span.style.fontSize = `${size}px`;
  }
}
window.__done = true;
