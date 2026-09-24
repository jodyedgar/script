// Semantic element finder: resolve a plain-language intent ("the hamburger
// menu button in the header") to ONE element on the page with Jev, TypeSafe's
// System One model.
//
// This is the "semantic find" recipe: enumerate the visible, actionable
// elements as a numbered list, ask one Choice question (which one is it?) and
// one Noul (is it here at all?) in a single request. Jev reads text only, so a
// candidate is described by what a person could read about it: its text,
// aria-label, title, placeholder, alt, href path and the region it sits in.
// ~130ms per lookup; well inside a live 30fps recording.
//
// Why: the scenario author in bucky-qa never opens the page, so every CSS
// selector it emits is a guess, and one miss kills the segment. Here the
// recorder looks at the real page at the moment of the step.
//
// Guards that live in CODE, not the model: visibility (kills the hidden
// "Add section" picker trap in the theme editor), the 255-option Choice cap
// (lexical pre-filter), and a confidence floor before anything is clicked.
const {getTypesafeKey} = require("./lib");

const ENDPOINT = "https://api.typesafe.ai/v1/systemone";
const MODEL = "jev-latest";
const MAX_OPTIONS = 200; // Choice caps at 255; keep headroom
const TIMEOUT_MS = 8000;
const ATTR = "data-jr-cand";

/**
 * Decision policy. The Choice always crowns something, so `exists` guards
 * against "closest irrelevant element". But `exists` is read literally
 * ("the cart icon" scored 0.35 against a text link reading CART that the
 * Choice picked at p=1.00), so a decisive Choice is trusted with a lower
 * existence bar.
 */
const THRESHOLDS = {exists: 0.5, pick: 0.35, decisivePick: 0.9, decisiveExists: 0.25};
const accept = (p, exists) => (exists >= THRESHOLDS.exists && p >= THRESHOLDS.pick) ||
  (p >= THRESHOLDS.decisivePick && exists >= THRESHOLDS.decisiveExists);

const ACTIONABLE = [
  "a[href]", "button", "[role=button]", "[role=link]", "[role=menuitem]", "[role=tab]",
  "[role=switch]", "[role=checkbox]", "[role=radio]", "[role=option]", "[role=treeitem]",
  "input:not([type=hidden])", "select", "textarea", "label", "summary", "[onclick]",
  "[tabindex]:not([tabindex='-1'])", "li[id*='__']", // theme-editor sidebar rows
].join(",");

// Runs INSIDE a frame. Tags each candidate with a data attribute so the caller
// can retrieve it by number after Jev picks.
function collectInFrame(attr, selector, maxText) {
  const seen = new Set();
  const out = [];
  const clean = (s) => (s || "").replace(/\s+/g, " ").trim().slice(0, maxText);
  const regionOf = (el) => {
    const r = el.closest("[aria-label], header, nav, main, footer, aside, dialog, [role=dialog], form, section[id], [id]");
    if (!r) return "";
    return clean(r.getAttribute("aria-label") || r.tagName.toLowerCase() + (r.id ? "#" + r.id : ""));
  };
  document.querySelectorAll(`[${attr}]`).forEach((el) => el.removeAttribute(attr));
  let n = 0;
  for (const el of document.querySelectorAll(selector)) {
    if (seen.has(el)) continue;
    seen.add(el);
    const cs = getComputedStyle(el);
    if (cs.display === "none" || cs.visibility === "hidden" || Number(cs.opacity) === 0) continue;
    const r = el.getBoundingClientRect();
    if (r.width < 2 || r.height < 2) continue;
    // Skip anything an ancestor hides (display:none is inherited via rect=0, but
    // visibility:hidden on a parent is not always reflected on the child rect).
    if (el.closest("[aria-hidden='true'], [hidden], template")) continue;
    const inViewport = r.bottom > 0 && r.right > 0 && r.top < innerHeight && r.left < innerWidth;
    let covered = false;
    if (inViewport) {
      const cx = Math.min(innerWidth - 1, Math.max(0, r.left + r.width / 2));
      const cy = Math.min(innerHeight - 1, Math.max(0, r.top + r.height / 2));
      const top = document.elementFromPoint(cx, cy);
      covered = !!top && top !== el && !el.contains(top) && !top.contains(el);
    }
    const img = el.querySelector("img[alt], svg[aria-label], svg title, use");
    const text = clean(el.innerText || el.textContent);
    const label = clean(el.getAttribute("aria-label") || el.getAttribute("title") || el.getAttribute("placeholder") ||
      (img && (img.getAttribute("alt") || img.getAttribute("aria-label") || img.textContent)) || el.getAttribute("name") || el.value);
    if (!text && !label && !el.id) continue; // nothing a person could identify it by
    el.setAttribute(attr, String(n));
    out.push({
      n: n++,
      tag: el.tagName.toLowerCase(),
      role: el.getAttribute("role") || (el.tagName === "INPUT" ? el.type : ""),
      text: text.slice(0, 80),
      label: label.slice(0, 80),
      href: el.getAttribute("href") ? clean(el.getAttribute("href")).slice(0, 60) : "",
      id: el.id ? el.id.slice(0, 40) : "",
      region: regionOf(el.parentElement || el),
      in_viewport: inViewport && !covered,
      y: Math.round(r.top + scrollY),
    });
  }
  return out;
}

const tokens = (s) => new Set(String(s || "").toLowerCase().split(/[^a-z0-9]+/).filter((w) => w.length >= 3));

function lexicalScore(intent, c) {
  const it = tokens(intent);
  const ct = tokens(`${c.text} ${c.label} ${c.href} ${c.id} ${c.region} ${c.tag} ${c.role}`);
  let hits = 0;
  for (const w of it) if (ct.has(w)) hits++;
  return hits;
}

async function askJev(apiKey, state, questions) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: {"Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json"},
      body: JSON.stringify({state, model: MODEL, questions}),
      signal: ctrl.signal,
    });
    const text = await res.text();
    if (!res.ok) throw new Error(`TypeSafe ${res.status}: ${text.slice(0, 200)}`);
    return JSON.parse(text);
  } finally {
    clearTimeout(t);
  }
}

/**
 * Collect candidates from every frame, ask Jev, return the pick.
 * @returns {Promise<{handle, frame, candidate, p, exists, ms} | {handle: null, exists, top: Array, ms}>}
 */
async function findByIntent(page, intent, {apiKey, maxText = 80, log = console.log} = {}) {
  const started = Date.now();
  apiKey = apiKey || getTypesafeKey();
  const frames = page.frames();
  const all = [];
  for (let fi = 0; fi < frames.length; fi++) {
    // Same guard as record.js findInFrames: Shopify's hidden embedded-modal-host
    // (and blank frames) can leave evaluate() unanswered for ~30s.
    let furl;
    try { furl = frames[fi].url(); } catch { continue; } // detached
    if (frames[fi] !== page.mainFrame() && /^(about:blank)?$|\/embedded-modal-host\b/.test(furl)) continue;
    let list = [];
    let timer;
    try {
      list = await Promise.race([
        frames[fi].evaluate(collectInFrame, ATTR, ACTIONABLE, maxText),
        new Promise((resolve) => { timer = setTimeout(() => resolve([]), 3000); }),
      ]);
    } catch { continue; } finally { clearTimeout(timer); }
    for (const c of list) all.push({...c, fi, id: `f${fi}e${c.n}`, domId: c.id});
  }
  if (!all.length) return {handle: null, exists: 0, top: [], ms: Date.now() - started, reason: "no actionable elements"};

  // Lexical pre-filter under the Choice cap: word overlap first, then
  // in-viewport, then document order. Unrelated-looking icon buttons survive
  // when the page is small enough; on a busy page the words have to match.
  const ranked = all
    .map((c) => ({c, s: lexicalScore(intent, c) * 10 + (c.in_viewport ? 1 : 0)}))
    .sort((a, b) => b.s - a.s || a.c.y - b.c.y)
    .slice(0, MAX_OPTIONS)
    .map((x) => x.c);

  const elements = ranked.map((c) => ({
    id: c.id, tag: c.tag, role: c.role || undefined, text: c.text || undefined, label: c.label || undefined,
    href: c.href || undefined, dom_id: c.domId || undefined, region: c.region || undefined, in_viewport: c.in_viewport,
  }));
  const state = {page: {url: page.url().slice(0, 120), title: (await page.title().catch(() => "")).slice(0, 80)}, elements};
  const criteria = {};
  for (const e of elements) criteria[e.id] = null;
  const questions = {
    target: {
      type: "choice",
      instructions: `Which entry in \`elements\` is: ${intent}? Judge by what a person would see: ` +
        "its text, label, icon name, link, and the region of the page it sits in.",
      criteria,
    },
    exists: {
      type: "noul",
      instructions: `Is there an entry in \`elements\` that a person would describe as: ${intent}? ` +
        "Wording need not match exactly: a text link reading CART is the cart link; a button labelled Open menu is the menu button.",
      criteria: {true: "One of the listed elements is what is described.", false: "None of the listed elements is what is described."},
    },
  };
  const res = await askJev(apiKey, state, questions);
  const target = res.answers.target;
  const exists = res.answers.exists.noul;
  const probs = target.probabilities || {};
  const top = Object.entries(probs).sort((a, b) => b[1] - a[1]).slice(0, 3)
    .map(([id, p]) => ({...ranked.find((c) => c.id === id), p: Number(p.toFixed(3))}));
  const ms = Date.now() - started;
  const best = top[0];
  const describe = (c) => `${c.id} <${c.tag}${c.role ? ` ${c.role}` : ""}> ${JSON.stringify(c.text || c.label || c.domId || "")}${c.region ? ` in ${c.region}` : ""}`;

  if (!best || !accept(best.p, exists)) {
    log(`  [find] "${intent}" → not found (exists=${exists.toFixed(2)}, best ${best ? `${describe(best)} p=${best.p}` : "none"}) ${ms}ms over ${elements.length} elements`);
    return {handle: null, exists, top, ms};
  }
  const handle = await frames[best.fi].$(`[${ATTR}="${best.n}"]`);
  if (!handle) return {handle: null, exists, top, ms, reason: "picked element vanished"};
  log(`  [find] "${intent}" → ${describe(best)} p=${best.p} exists=${exists.toFixed(2)} ${ms}ms over ${elements.length} elements (${res.model})`);
  return {handle, frame: frames[best.fi], candidate: best, p: best.p, exists, ms};
}

module.exports = {findByIntent, THRESHOLDS, accept, collectInFrame, lexicalScore};
