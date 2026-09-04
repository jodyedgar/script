// jobreport record <scenario.json> <outDir>
//
// Records a smooth walkthrough video via Browserless cloud session recording
// (paid plan feature: connect with record=true, Browserless.start/stopRecording).
//
// A scenario is a list of SEGMENTS; each segment is its own cloud session and
// produces one WebM. Segments with "auth": true replay the Shopify admin
// cookies saved by `jobreport.sh auth <store>`. All segments are then
// concatenated with ffmpeg into one 30fps MP4, plus a small looping GIF
// thumbnail cut from the final video.
//
// Scenario shape:
// {
//   "store": "mystore",                        // admin handle, needed by auth segments
//   "storefrontPassword": "secret",            // optional: pre-launch storefront password
//   "viewport": {"width": 1440, "height": 900},
//   "thumbnail": {"start": 0, "duration": 8},  // optional, defaults shown
//   "segments": [
//     {"name": "admin", "auth": true, "steps": [
//       {"goto": "https://admin.shopify.com/store/mystore/themes"},
//       {"pause": 3},
//       {"smoothScroll": {"to": 600, "duration": 4}}
//     ]},
//     {"name": "storefront-mobile", "viewport": {"width": 390, "height": 844}, "steps": [  // per-segment viewport is optional
//     {"name": "storefront", "steps": [
//       {"goto": "https://mystore.com/collections/all"},
//       {"hide": "#cookie-banner"},
//       {"smoothScroll": {"to": "bottom", "duration": 10}}
//     ]}
//   ]
// }
//
// Steps: goto | pause | smoothScroll | click | waitFor | hide | type
const fs = require("fs");
const path = require("path");
const {execFileSync} = require("child_process");
const puppeteer = require("puppeteer-core");
const {getBrowserlessToken, browserlessWsUrl, cookieFile} = require("./lib");

const NAV_TIMEOUT_MS = 45000;

function fail(msg) { console.error(`record failed: ${msg}`); process.exit(1); }

function loadCookies(store) {
  const file = cookieFile(store);
  if (!fs.existsSync(file)) {
    fail(`no saved admin session for "${store}" — run: jobreport.sh auth ${store}`);
  }
  const jar = JSON.parse(fs.readFileSync(file, "utf8"));
  const ageDays = (Date.now() - Date.parse(jar.savedAt)) / 86400000;
  if (ageDays > 14) {
    console.warn(`warning: admin cookies for "${store}" are ${ageDays.toFixed(0)} days old — if the admin shows a login page, re-run: jobreport.sh auth ${store}`);
  }
  return jar.cookies;
}

// Browserless's Chrome lays text out before webfonts land and then never
// repaints it — backgrounds render, every glyph stays invisible (seen live
// with sunbowl.ca's Montserrat: DOM/CSS fully visible, zero painted text).
// Waiting for document.fonts.ready and forcing a harmless global style
// invalidation makes it repaint correctly, in the site's real fonts.
async function ensureTextPaints(page) {
  try {
    await page.evaluate(() => Promise.race([
      document.fonts.ready.then(() => undefined),
      new Promise((r) => setTimeout(r, 5000)),
    ]));
    await page.addStyleTag({content: "* { text-rendering: optimizeLegibility !important; }"});
    await new Promise((r) => setTimeout(r, 300));
  } catch { /* non-fatal — worst case the page records as-is */ }
}

// "text=Collections" (Playwright-style, which the QA agent tends to emit) is not
// a puppeteer selector; map it to puppeteer's ::-p-text() so it matches by
// visible text instead of failing as a bogus CSS selector.
function normalizeSelector(sel) {
  const m = /^text=(.+)$/.exec(String(sel).trim());
  return m ? `::-p-text(${m[1].replace(/^["']|["']$/g, "")})` : sel;
}

// Find a selector in the main frame OR any child frame (Shopify's theme editor
// renders its whole UI inside an online-store-web iframe that attaches a few
// seconds after the top document settles). Polls the LIVE frame list until the
// deadline, so late-attaching frames are searched too.
async function findInFrames(page, sel, {visible = false, timeout = 15000} = {}) {
  const deadline = Date.now() + timeout;
  let frameCount = 0;
  while (Date.now() < deadline) {
    const frames = page.frames();
    frameCount = frames.length;
    for (const f of frames) {
      let h = null;
      try { h = await f.$(sel); } catch { continue; } // detached frame / mid-navigation
      if (!h) continue;
      if (!visible) return h;
      const ok = await h.evaluate((e) => {
        const r = e.getBoundingClientRect(), cs = getComputedStyle(e);
        return r.width > 0 && r.height > 0 && cs.visibility !== "hidden" && cs.display !== "none";
      }).catch(() => false);
      if (ok) return h;
    }
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error(`Waiting for selector \`${sel}\` failed (${frameCount} frame(s), ${timeout}ms)`);
}

async function runStep(page, step) {
  if (step.goto) {
    try {
      await page.goto(step.goto, {waitUntil: step.waitUntil || "networkidle2", timeout: NAV_TIMEOUT_MS});
    } catch (err) {
      if (String(err.message).includes("timeout")) {
        console.warn(`  goto ${step.goto}: network never settled, continuing`);
      } else throw err;
    }
    await ensureTextPaints(page);
    return;
  }
  if (step.pause != null) {
    return new Promise((r) => setTimeout(r, step.pause * 1000));
  }
  if (step.smoothScroll) {
    const {to = "bottom", duration = 8} = step.smoothScroll;
    return page.evaluate(async (to, durMs) => {
      // Some themes lock html/body (overflow:hidden, 100dvh) and scroll an inner
      // wrapper instead (e.g. Horizon's .page-wrapper on desktop). window.scrollTo
      // is a silent no-op there, so scroll whichever element actually scrolls.
      const docEl = document.scrollingElement || document.documentElement;
      let box = null; // null = window
      if (getComputedStyle(document.documentElement).overflowY === "hidden" || docEl.scrollHeight <= innerHeight + 1) {
        for (const el of document.querySelectorAll("body, body *")) {
          const cs = getComputedStyle(el);
          if (/(auto|scroll)/.test(cs.overflowY) && el.scrollHeight > el.clientHeight + 50 && el.clientHeight >= innerHeight * 0.5 &&
              (!box || el.scrollHeight > box.scrollHeight)) box = el;
        }
      }
      const pos = () => (box ? box.scrollTop : scrollY);
      const setPos = (y) => { if (box) box.scrollTop = y; else scrollTo(0, y); };
      const maxScroll = box ? box.scrollHeight - box.clientHeight : docEl.scrollHeight - innerHeight;
      let target;
      if (to === "bottom") {
        target = maxScroll;
      } else if (typeof to === "number") {
        target = to;
      } else {
        const el = document.querySelector(to);
        if (!el) return;
        target = el.getBoundingClientRect().top + pos() - innerHeight / 3;
      }
      target = Math.max(0, Math.min(target, maxScroll));
      const from = pos();
      const start = performance.now();
      await new Promise((resolve) => {
        (function frame(now) {
          const t = Math.min((now - start) / durMs, 1);
          // ease-in-out
          const e = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
          setPos(from + (target - from) * e);
          t < 1 ? requestAnimationFrame(frame) : resolve();
        })(performance.now());
      });
    }, to, duration * 1000);
  }
  if (step.click) {
    const sel = normalizeSelector(step.click);
    const el = await findInFrames(page, sel, {visible: true});
    return el.click();
  }
  if (step.clickIf) {
    // Click only when present — for optional UI (e.g. an AI follow-up step
    // that may or may not appear). Never fails the recording.
    const el = await page.$(step.clickIf);
    if (el) {
      const visible = await el.isIntersectingViewport().catch(() => true);
      if (visible) await el.click().catch(() => {});
    }
    return;
  }
  if (step.waitFor) {
    return findInFrames(page, normalizeSelector(step.waitFor), {timeout: (step.timeout || 15) * 1000});
  }
  if (step.hide) {
    return page.evaluate((sel) => {
      document.querySelectorAll(sel).forEach((el) => el.style.setProperty("display", "none", "important"));
    }, step.hide);
  }
  if (step.type) {
    const {selector, text, delay = 40} = step.type;
    const el = await findInFrames(page, normalizeSelector(selector), {visible: true});
    return el.type(text, {delay});
  }
  throw new Error(`unknown step: ${JSON.stringify(step)}`);
}

async function recordSegment(scenario, segment, token, outFile) {
  const browser = await puppeteer.connect({browserWSEndpoint: browserlessWsUrl(token)});
  try {
    const page = await browser.newPage();
    // A segment may carry its own viewport (e.g. a 390x844 mobile pass after
    // the desktop pass); fall back to the scenario-wide one.
    const vp = segment.viewport || scenario.viewport || {width: 1440, height: 900};
    const mobile = vp.width < 768;
    await page.setViewport({...vp, isMobile: mobile, hasTouch: mobile});

    if (segment.auth) {
      if (!scenario.store) fail(`segment "${segment.name}" has auth:true but scenario has no "store"`);
      const cookies = loadCookies(scenario.store);
      // puppeteer accepts CDP-shaped cookies; sameSite "unspecified" must be dropped
      await page.setCookie(...cookies.map(({sameSite, ...c}) =>
        sameSite && sameSite !== "unspecified" ? {sameSite, ...c} : c));
    }

    // Pre-launch stores: submit the storefront password first (scenario
    // "storefrontPassword"), so the recording never opens on the /password page.
    if (scenario.storefrontPassword && !segment.auth) {
      const first = segment.steps.find((s) => s.goto);
      if (first) {
        const origin = new URL(first.goto).origin;
        try {
          await page.goto(`${origin}/password`, {waitUntil: "domcontentloaded", timeout: 30000});
          if (/\/password/.test(page.url())) {
            // The form POST is the reliable path (Enter/Submit clicks don't submit on every theme).
            await page.evaluate(async (pw) => {
              const fd = new URLSearchParams({form_type: "storefront_password", utf8: "✓", password: pw});
              await fetch("/password", {method: "POST", body: fd, redirect: "manual", headers: {"content-type": "application/x-www-form-urlencoded"}});
            }, scenario.storefrontPassword);
            await page.goto(new URL(page.url()).origin + "/", {waitUntil: "domcontentloaded", timeout: 30000});
          }
          console.log(`  [${segment.name}] storefront password ${/\/password/.test(page.url()) ? "NOT accepted" : "accepted"}`);
        } catch (err) {
          console.warn(`  [${segment.name}] storefront password step failed: ${err.message}`);
        }
      }
    }

    // Run the segment's leading goto BEFORE recording starts so the video
    // opens on a painted page instead of white nothing.
    const steps = [...segment.steps];
    if (steps[0] && steps[0].goto) {
      console.log(`  [${segment.name}] goto (pre-roll)`);
      await runStep(page, steps.shift());
      await new Promise((r) => setTimeout(r, 500));
    }

    const cdp = await page.createCDPSession();
    const started = await cdp.send("Browserless.startRecording");
    if (started && started.error) {
      fail(`Browserless says: "${started.error}" — session recording needs a paid plan (Prototyping or up)`);
    }

    for (const step of steps) {
      console.log(`  [${segment.name}] ${Object.keys(step)[0]}`);
      await runStep(page, step);
    }
    // Small tail so the last motion isn't clipped by the encoder.
    await new Promise((r) => setTimeout(r, 1000));

    const resp = await cdp.send("Browserless.stopRecording", {encoding: "base64"});
    if (!resp || !resp.value) {
      fail(`stopRecording returned no data${resp && resp.error ? `: ${resp.error}` : ""}`);
    }
    fs.writeFileSync(outFile, Buffer.from(resp.value, "base64"));
    console.log(`  [${segment.name}] saved ${outFile} (${fs.statSync(outFile).size} bytes)`);
  } finally {
    await browser.close().catch(() => {});
  }
}

function ffmpeg(args) {
  execFileSync("ffmpeg", ["-hide_banner", "-loglevel", "error", "-y", ...args], {stdio: ["ignore", "inherit", "inherit"]});
}

async function main() {
  const [scenarioPath, outDir] = process.argv.slice(2);
  if (!scenarioPath || !outDir) {
    console.error("Usage: node record.js <scenario.json> <outDir>");
    process.exit(2);
  }
  const scenario = JSON.parse(fs.readFileSync(scenarioPath, "utf8"));
  if (!Array.isArray(scenario.segments) || !scenario.segments.length) {
    fail("scenario has no segments");
  }
  fs.mkdirSync(outDir, {recursive: true});
  const token = getBrowserlessToken();

  const segFiles = [];
  for (let i = 0; i < scenario.segments.length; i++) {
    const segment = scenario.segments[i];
    const file = path.join(outDir, `seg-${String(i).padStart(2, "0")}-${segment.name || "segment"}.webm`);
    console.log(`Recording segment ${i + 1}/${scenario.segments.length}: ${segment.name || "(unnamed)"}`);
    await recordSegment(scenario, segment, token, file);
    segFiles.push(file);
  }

  // Concat + normalize to a browser-friendly MP4 (30fps h264 yuv420p faststart).
  const videoPath = path.join(outDir, "walkthrough.mp4");
  const inputs = segFiles.flatMap((f) => ["-i", f]);
  const n = segFiles.length;
  // Segments can differ in size (desktop + mobile viewports); concat needs one
  // frame size, so letterbox every segment onto the scenario-wide canvas.
  const canvas = scenario.viewport || {width: 1440, height: 900};
  const W = Math.trunc(canvas.width / 2) * 2, H = Math.trunc(canvas.height / 2) * 2;
  const filter = segFiles.map((_, i) =>
    `[${i}:v]fps=30,scale=${W}:${H}:force_original_aspect_ratio=decrease,pad=${W}:${H}:(ow-iw)/2:(oh-ih)/2:color=white,setsar=1[v${i}]`).join(";") +
    `;${segFiles.map((_, i) => `[v${i}]`).join("")}concat=n=${n}:v=1:a=0[v]`;
  ffmpeg([...inputs, "-filter_complex", filter, "-map", "[v]",
    "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p",
    "-movflags", "+faststart", videoPath]);

  // Looping GIF thumbnail from the final video.
  const {start = 0, duration = 8} = scenario.thumbnail || {};
  const thumbPath = path.join(outDir, "thumb.gif");
  ffmpeg(["-ss", String(start), "-t", String(duration), "-i", videoPath,
    "-vf", "fps=10,scale=480:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse",
    "-loop", "0", thumbPath]);

  console.log(JSON.stringify({video: videoPath, thumbnail: thumbPath, segments: segFiles}));
}

main().catch((err) => fail(err.stack || err.message));
