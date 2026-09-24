// Shared helpers for the jobreport capture tool.
const fs = require("fs");
const os = require("os");
const path = require("path");
const {execFileSync} = require("child_process");

const CONFIG_DIR = path.join(os.homedir(), ".config", "jobreport");
const COOKIE_DIR = path.join(CONFIG_DIR, "cookies");
const CHROME_PROFILE_DIR = path.join(CONFIG_DIR, "chrome-profile");

const BROWSERLESS_HOST = "production-sfo.browserless.io";
// Prototyping plan allows 15-minute sessions; leave margin under the cap.
const SESSION_TIMEOUT_MS = 840000;

function getBrowserlessToken() {
  if (process.env.BROWSERLESS_API_KEY) return process.env.BROWSERLESS_API_KEY.trim();
  const out = execFileSync("gcloud", [
    "secrets", "versions", "access", "latest",
    "--secret=BROWSERLESS_API_KEY", "--project", "bucky-app-355a3",
  ], {encoding: "utf8"});
  const token = out.trim();
  if (!token) throw new Error("BROWSERLESS_API_KEY empty (set env var or check gcloud auth)");
  return token;
}

function browserlessWsUrl(token, {record = true} = {}) {
  // NO stealth=true: the docs claim recording needs the stealth route, but
  // stealth sessions never paint webfont text (whole pages record with
  // invisible glyphs — verified live). Recording works fine without it.
  // Site isolation OFF: Shopify's theme editor UI is a cross-origin
  // online-store-web iframe. As an out-of-process frame, puppeteer's target
  // for it detaches and re-attaches about once a second over this connection
  // (the editor itself loads once), so every query hit "Session closed" and no
  // admin segment could find a sidebar row (TICK-4082, 2026-09-24). In-process,
  // it is an ordinary child frame and page.frames() works.
  const launch = {args: ["--disable-features=IsolateOrigins,site-per-process", "--disable-site-isolation-trials"]};
  return `wss://${BROWSERLESS_HOST}/?token=${encodeURIComponent(token)}` +
    `&headless=false&record=${record ? "true" : "false"}&timeout=${SESSION_TIMEOUT_MS}` +
    `&launch=${encodeURIComponent(JSON.stringify(launch))}`;
}

// TypeSafe (Jev) key for the semantic element finder (finder.js). Env first,
// then ~/.config/jobreport/typesafe_api_key (so the bucky-qa launchd service
// needs no env change), then Secret Manager. Never printed.
function getTypesafeKey() {
  if (process.env.TYPESAFE_API_KEY) return process.env.TYPESAFE_API_KEY.trim();
  const file = path.join(CONFIG_DIR, "typesafe_api_key");
  if (fs.existsSync(file)) {
    const k = fs.readFileSync(file, "utf8").trim();
    if (k) return k;
  }
  try {
    const out = execFileSync("gcloud", [
      "secrets", "versions", "access", "latest",
      "--secret=TYPESAFE_API_KEY", "--project", "bucky-app-355a3",
    ], {encoding: "utf8", stdio: ["ignore", "pipe", "ignore"]});
    if (out.trim()) return out.trim();
  } catch { /* fall through */ }
  throw new Error("TYPESAFE_API_KEY not found (env, ~/.config/jobreport/typesafe_api_key, or Secret Manager)");
}

function cookieFile(store) {
  return path.join(COOKIE_DIR, `${store.replace(/[^a-zA-Z0-9.-]/g, "_")}.json`);
}

function ensureDirs() {
  fs.mkdirSync(COOKIE_DIR, {recursive: true, mode: 0o700});
  fs.mkdirSync(CHROME_PROFILE_DIR, {recursive: true, mode: 0o700});
}

function findLocalChrome() {
  const candidates = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
  ];
  for (const c of candidates) if (fs.existsSync(c)) return c;
  throw new Error("No local Chrome found (looked for Google Chrome / Chromium in /Applications)");
}

module.exports = {
  CONFIG_DIR, COOKIE_DIR, CHROME_PROFILE_DIR, SESSION_TIMEOUT_MS,
  getBrowserlessToken, browserlessWsUrl, cookieFile, ensureDirs, findLocalChrome, getTypesafeKey,
};
