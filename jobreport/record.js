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
// Steps: goto | pause | smoothScroll | click | clickIf | clickLabel | waitFor | hide | type | evaluate (JS string, Promise awaited)
//        clickIntent | typeIntent — plain-language targets resolved on the LIVE page by Jev
//        (finder.js): {"clickIntent": "the hamburger menu button in the header", "fallback": "summary.header__icon--menu"}
//        {"typeIntent": "the search box", "text": "wax", "fallback": "input[type=search]"}
//
// Pacing (cursor.js): every click glides a drawn cursor to the target, rests
// on it with a highlight ring, clicks with a ripple, rests again; navigations
// rest before the next step. The video is meant to TEACH, so a viewer must be
// able to follow where each click goes. Scenario-level "pacing": false turns
// it off; "pacing": {"moveMs": 900, "dwellBeforeMs": 600, "dwellAfterMs": 1200,
// "afterNavMs": 1500, "typeDelayMs": 60, "highlight": true} overrides defaults.
// A segment may carry its own "pacing".
const fs = require("fs");
const path = require("path");
const {execFileSync} = require("child_process");
const puppeteer = require("puppeteer-core");
const {getBrowserlessToken, browserlessWsUrl, cookieFile} = require("./lib");
const {findByIntent} = require("./finder");
const {Cursor, resolvePacing} = require("./cursor");

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
async function ensureTextPaints(page, fontsCapMs = 5000) {
  try {
    await page.evaluate((cap) => Promise.race([
      document.fonts.ready.then(() => undefined),
      new Promise((r) => setTimeout(r, cap)),
    ]), fontsCapMs);
    await page.addStyleTag({content: "* { text-rendering: optimizeLegibility !important; }"});
    await new Promise((r) => setTimeout(r, 300));
  } catch { /* non-fatal — worst case the page records as-is */ }
}

// Themes ship `html { scroll-behavior: smooth }`, which turns every per-frame
// scrollTo() of smoothScroll into a competing browser animation (the page
// visibly bounced between two positions on hillsdrygoods.com), and Chrome's
// scroll anchoring re-adjusts the position as lazy images load above the
// viewport. Both are switched off for the recording; our own easing is the
// only scroll driver. Re-applied after every navigation.
async function stabilizeScrolling(page) {
  try {
    await page.addStyleTag({content: "html, body, * { scroll-behavior: auto !important; overflow-anchor: none !important; }"});
  } catch { /* mid-navigation — the next call covers it */ }
}

// Click, then find out whether it navigated. A link click is not a goto: the
// old code moved straight on and a scroll could start on a page that was
// still laying out. Unlike a goto (which settles BEFORE recording starts)
// this settling is on camera, so the caps are short and the time spent is
// returned so the cursor's post-navigation rest can be shortened by it.
// Returns {navigated, waitedMs}: the ms spent after the click either way, so
// the cursor beat can count it against its rest (a click that merely opens
// a menu must not pay the navigation probe AND the full rest).
async function clickAndSettle(page, doClick) {
  const nav = page.waitForNavigation({waitUntil: "domcontentloaded", timeout: 10000}).then(() => true).catch(() => false);
  const t0 = Date.now();
  await doClick();
  const navigated = await Promise.race([nav, new Promise((r) => setTimeout(() => r(false), 1200))]);
  if (!navigated) return {navigated: false, waitedMs: Date.now() - t0};
  // Load event, not network idle (Shopify storefronts never go idle — analytics
  // pixels), with a short cap: the viewer is watching the page load either way.
  await page.waitForFunction(() => document.readyState === "complete", {timeout: 3000}).catch(() => {});
  await ensureTextPaints(page, 1500);
  await stabilizeScrolling(page);
  return {navigated: true, waitedMs: Date.now() - t0};
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
  const urls = page.frames().map((f) => f.url().slice(0, 80)).join(" | ");
  throw new Error(`Waiting for selector \`${sel}\` failed (${frameCount} frame(s), ${timeout}ms) — frames: ${urls} — page: ${page.url().slice(0, 100)}`);
}

// Click the control behind a form <label> whose text contains `text` — used for
// theme-editor switches/checkboxes. Fires a DOM click on the associated control
// (no coordinates: text matches can resolve to large ancestors whose centre is
// somewhere else on the page entirely, e.g. inside the preview iframe).
async function findLabelControl(page, text, timeout = 15000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    for (const f of page.frames()) {
      let h = null;
      try {
        h = await f.evaluateHandle((t) => {
          const lab = [...document.querySelectorAll("label")].find((l) => (l.textContent || "").replace(/\s+/g, " ").trim().includes(t));
          if (!lab) return null;
          const ctrl = lab.control || (lab.getAttribute("for") && document.getElementById(lab.getAttribute("for"))) || lab.querySelector("input, button");
          return ctrl || lab;
        }, text);
      } catch { continue; }
      const el = h && h.asElement();
      if (el) return el;
    }
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error(`clickLabel: no <label> containing "${text}" in any frame (${timeout}ms)`);
}

// Resolve an intent step: Jev on the live page (polled while the page may
// still be settling), then the author's CSS fallback, then a clear failure
// naming what Jev could see.
async function resolveIntent(page, intent, {fallback, timeout = 15000} = {}) {
  const deadline = Date.now() + timeout;
  let last = null;
  while (Date.now() < deadline) {
    last = await findByIntent(page, intent);
    if (last.handle) return last.handle;
    await new Promise((r) => setTimeout(r, 1500));
  }
  if (fallback) {
    console.warn(`  [find] falling back to selector ${fallback}`);
    return findInFrames(page, normalizeSelector(fallback), {visible: true, timeout: 5000});
  }
  const seen = (last && last.top || []).map((c) => `${c.tag} ${JSON.stringify(c.text || c.label || c.domId || "")} p=${c.p}`).join("; ");
  throw new Error(`clickIntent: nothing on the page matches "${intent}" (exists=${last ? last.exists.toFixed(2) : "?"}; closest: ${seen || "none"}) — page: ${page.url().slice(0, 100)}`);
}

async function runStep(page, step, ctx = {}) {
  const cursor = ctx.cursor;
  // Every click goes through clickAndSettle so a navigating click waits for
  // the new page (and the cursor beat rests after it) before the next step.
  const beat = (handle, doClick) => {
    const settled = () => clickAndSettle(page, doClick);
    return cursor ? cursor.clickBeat(handle, settled, {nextIsPause: ctx.nextIsPause}) : settled().then(() => undefined);
  };
  if (step.goto) {
    try {
      await page.goto(step.goto, {waitUntil: step.waitUntil || "networkidle2", timeout: NAV_TIMEOUT_MS});
    } catch (err) {
      if (String(err.message).includes("timeout")) {
        console.warn(`  goto ${step.goto}: network never settled, continuing`);
      } else throw err;
    }
    await ensureTextPaints(page);
    await stabilizeScrolling(page);
    if (cursor && !ctx.preroll) await cursor.afterNavigation();
    return;
  }
  if (step.pause != null) {
    return new Promise((r) => setTimeout(r, step.pause * 1000));
  }
  if (step.smoothScroll) {
    const {to = "bottom", duration = 8} = step.smoothScroll;
    await stabilizeScrolling(page);
    // (Tried and removed: forcing the lazy images in the scroll range to load
    // first. It queued hundreds of decodes, starved the renderer and turned a
    // 4s scroll into 25s. With scroll anchoring off, images popping in no
    // longer move the page, which was the actual complaint.)
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
      const setPos = (y) => { if (box) box.scrollTop = y; else scrollTo({top: y, left: 0, behavior: "instant"}); };
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
      // Timer-driven, not requestAnimationFrame: a busy renderer (image
      // decodes, third-party scripts) can starve rAF in a cloud browser and
      // stall the scroll for seconds; a 16ms timer keeps the easing on the clock.
      await new Promise((resolve) => {
        (function frame() {
          const t = Math.min((performance.now() - start) / durMs, 1);
          // ease-in-out
          const e = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
          setPos(from + (target - from) * e);
          t < 1 ? setTimeout(frame, 16) : resolve();
        })();
      });
    }, to, duration * 1000);
  }
  if (step.click) {
    const sel = normalizeSelector(step.click);
    const el = await findInFrames(page, sel, {visible: true});
    return beat(el, () => el.click());
  }
  if (step.clickIntent) {
    const el = await resolveIntent(page, step.clickIntent, {fallback: step.fallback, timeout: (step.timeout || 15) * 1000});
    return beat(el, () => el.click());
  }
  if (step.clickLabel) {
    const el = await findLabelControl(page, step.clickLabel);
    // DOM click, not coordinates: label controls can be visually hidden switches.
    return beat(el, () => el.evaluate((e) => e.click()));
  }
  if (step.clickIf) {
    // Click only when present — for optional UI (e.g. an AI follow-up step
    // that may or may not appear). Never fails the recording.
    const el = await page.$(step.clickIf);
    if (el) {
      const visible = await el.isIntersectingViewport().catch(() => true);
      if (visible) await beat(el, () => el.click().catch(() => {}));
    }
    return;
  }
  if (step.waitFor) {
    return findInFrames(page, normalizeSelector(step.waitFor), {timeout: (step.timeout || 15) * 1000});
  }
  if (step.evaluate) {
    // Run page JS (string expression; a returned Promise is awaited). Use for
    // storefront APIs a click cannot reach, e.g. window.privacyBanner.showBanner()
    // when the Shopify consent banner is region-gated and the recorder's egress
    // IP is outside the banner regions.
    return page.evaluate(step.evaluate);
  }
  if (step.hide) {
    return page.evaluate((sel) => {
      document.querySelectorAll(sel).forEach((el) => el.style.setProperty("display", "none", "important"));
    }, step.hide);
  }
  if (step.type) {
    const {selector, text, delay} = step.type;
    const el = await findInFrames(page, normalizeSelector(selector), {visible: true});
    await beat(el, () => el.click());
    return el.type(text, {delay: delay ?? (cursor ? cursor.p.typeDelayMs : 40)});
  }
  if (step.typeIntent) {
    const el = await resolveIntent(page, step.typeIntent, {fallback: step.fallback, timeout: (step.timeout || 15) * 1000});
    await beat(el, () => el.click());
    return el.type(String(step.text ?? ""), {delay: step.delay ?? (cursor ? cursor.p.typeDelayMs : 40)});
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
      // puppeteer accepts CDP-shaped cookies; sameSite "unspecified" must be
      // dropped, and so must partitionKey (CHIPS cookies exported by a newer
      // local Chrome) — Browserless's Chrome rejects it on Network.deleteCookies
      // with "partitionKey.topLevelSite mandatory field missing".
      await page.setCookie(...cookies.map(({sameSite, partitionKey, partitionKeyOpaque, ...c}) =>
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

    // Pacing + drawn cursor (cursor.js). Segment overrides scenario.
    const pacing = resolvePacing(segment.pacing !== undefined ? segment.pacing : scenario.pacing);
    const cursor = pacing.enabled ? new Cursor(page, pacing) : null;

    // Run the segment's leading goto BEFORE recording starts so the video
    // opens on a painted page instead of white nothing.
    const steps = [...segment.steps];
    if (steps[0] && steps[0].goto) {
      console.log(`  [${segment.name}] goto (pre-roll)`);
      await runStep(page, steps.shift(), {cursor, preroll: true});
      await new Promise((r) => setTimeout(r, 500));
      if (segment.auth && /accounts\.shopify\.com\/|\/challenges\/|\/admin\/auth\/login|\/login\?/.test(page.url())) {
        // The replayed admin session was rejected (expired, or Shopify's periodic
        // passkey re-verification). Tag it so callers can ask a human to re-auth
        // instead of treating it as a broken recording.
        fail(`ADMIN_SESSION_EXPIRED: admin segment "${segment.name}" landed on ${page.url().slice(0, 90)} — re-run: jobreport.sh auth ${scenario.store}`);
      }
    }

    const cdp = await page.createCDPSession();
    const started = await cdp.send("Browserless.startRecording");
    if (started && started.error) {
      fail(`Browserless says: "${started.error}" — session recording needs a paid plan (Prototyping or up)`);
    }

    if (cursor) await cursor.ensure(); // visible from the first recorded frame
    const recStart = Date.now();
    for (let i = 0; i < steps.length; i++) {
      const step = steps[i];
      const next = steps[i + 1];
      const at = ((Date.now() - recStart) / 1000).toFixed(1);
      console.log(`  [${segment.name}] +${at}s ${Object.keys(step)[0]}${step.clickIntent || step.typeIntent ? ` "${step.clickIntent || step.typeIntent}"` : ""}`);
      await runStep(page, step, {cursor, nextIsPause: !!(next && next.pause != null)});
    }
    console.log(`  [${segment.name}] +${((Date.now() - recStart) / 1000).toFixed(1)}s end`);
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
