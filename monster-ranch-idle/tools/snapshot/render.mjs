// Snapshot, step 2 of 2: renders scene.json (from scene.luau) to a PNG in headless Chromium.
//
//   lune run tools/snapshot/scene tools/snapshot/scene.json
//   (cd tools/snapshot && npm install && node render.mjs scene.json snapshot.png [toHub,side,up,look])
//
// Uses the Chromium at $CHROMIUM_PATH (default /opt/pw-browsers/chromium). Fonts (Fredoka,
// Montserrat, Source Sans 3) are fetched once with curl into fonts/, falling back to system fonts.
import { chromium } from "playwright-core";
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const scenePath = path.resolve(process.argv[2] || path.join(here, "scene.json"));
const outPath = path.resolve(process.argv[3] || path.join(here, "snapshot.png"));
// 4th argument: "toHub,side,up,look" (plot framing) or a raw query such as "eye=x,y,z&at=x,y,z&fov=40&noui=1".
const arg = process.argv[4];
const cam = !arg ? "" : arg.includes("=") ? `?${arg}` : `?cam=${encodeURIComponent(arg)}`;

function ensureFonts() {
  const dir = path.join(here, "fonts");
  const cssPath = path.join(dir, "fonts.css");
  if (fs.existsSync(cssPath)) return;
  fs.mkdirSync(dir, { recursive: true });
  try {
    const url = "https://fonts.googleapis.com/css2?family=Fredoka:wght@600&family=Montserrat:wght@700&family=Source+Sans+3:wght@700&display=block";
    let css = execFileSync("curl", ["-sSL", "-A", "Mozilla/5.0 (X11; Linux x86_64) Chrome/120", url], { encoding: "utf8" });
    let n = 0;
    css = css.replace(/url\((https:[^)]+\.woff2)\)/g, (_, src) => {
      const file = `f${n++}.woff2`;
      execFileSync("curl", ["-sSL", "-o", path.join(dir, file), src]);
      return `url(${file})`;
    });
    fs.writeFileSync(cssPath, css);
  } catch (err) {
    console.warn("fonts unavailable, using system fonts:", err.message);
    fs.writeFileSync(cssPath, "/* system fonts */");
  }
}

const TYPES = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".css": "text/css", ".woff2": "font/woff2" };
function serve() {
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, "http://x");
    const file = url.pathname === "/scene.json" ? scenePath : path.join(here, decodeURIComponent(url.pathname));
    if (!file.startsWith(here) && file !== scenePath) return res.writeHead(403).end();
    fs.readFile(file, (err, data) => {
      if (err) return res.writeHead(404).end();
      res.writeHead(200, { "content-type": TYPES[path.extname(file)] || "application/octet-stream" }).end(data);
    });
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server)));
}

ensureFonts();
const server = await serve();
const { port } = server.address();
const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH || "/opt/pw-browsers/chromium",
  args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"],
});
const page = await browser.newPage({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 1.5 });
page.on("pageerror", (err) => console.error("page error:", err.message));
page.on("console", (msg) => msg.type() === "error" && console.error("console:", msg.text()));
await page.goto(`http://127.0.0.1:${port}/viewer.html${cam}`);
await page.waitForFunction(() => window.__done === true, null, { timeout: 120000 });
await page.locator("#stage").screenshot({ path: outPath });
await browser.close();
server.close();
console.log("wrote", outPath);
