// jobreport auth <store-domain-or-handle>
//
// Opens a local Chrome window (dedicated profile, NOT your daily profile),
// lets you log into the store's Shopify admin, then exports the session
// cookies to ~/.config/jobreport/cookies/<store>.json (chmod 600) so the
// Browserless cloud browser can replay the session during recording.
//
// Re-run whenever the admin session expires (recording will tell you).
const fs = require("fs");
const puppeteer = require("puppeteer-core");
const {cookieFile, ensureDirs, findLocalChrome, CHROME_PROFILE_DIR} = require("./lib");

const LOGIN_WAIT_MS = 5 * 60 * 1000; // give the human five minutes
const COOKIE_DOMAINS = [".shopify.com", "admin.shopify.com", ".myshopify.com"];

async function main() {
  const store = process.argv[2];
  if (!store) {
    console.error("Usage: node auth.js <store>  (e.g. mystore.myshopify.com or the admin store handle)");
    process.exit(2);
  }
  ensureDirs();

  // Store handle for the admin URL: "foo.myshopify.com" -> "foo".
  const handle = store.replace(/\.myshopify\.com$/, "").replace(/^https?:\/\//, "");
  const adminUrl = `https://admin.shopify.com/store/${handle}`;

  const browser = await puppeteer.launch({
    executablePath: findLocalChrome(),
    headless: false,
    userDataDir: CHROME_PROFILE_DIR,
    defaultViewport: null,
    args: ["--no-first-run", "--no-default-browser-check", `--window-size=1280,900`],
  });
  const page = (await browser.pages())[0] || await browser.newPage();
  await page.goto(adminUrl, {waitUntil: "domcontentloaded"});

  console.log(`\nLog into the Shopify admin for "${handle}" in the Chrome window that just opened.`);
  console.log("Waiting for the admin to load (up to 5 minutes)...");

  const deadline = Date.now() + LOGIN_WAIT_MS;
  let loggedIn = false;
  while (Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, 2000));
    try {
      const url = page.url();
      // Logged in == we are on admin.shopify.com/store/<handle> and not on an
      // accounts/login interstitial.
      if (url.startsWith(`https://admin.shopify.com/store/${handle}`) &&
          await page.$("#AppFrameNav, nav")) {
        loggedIn = true;
        break;
      }
    } catch { /* page navigating; retry */ }
  }
  if (!loggedIn) {
    console.error("Timed out waiting for an authenticated admin session.");
    await browser.close();
    process.exit(1);
  }

  // Grab ALL cookies in the profile via CDP, filter to Shopify domains.
  const cdp = await page.createCDPSession();
  const {cookies} = await cdp.send("Storage.getCookies");
  const wanted = cookies.filter((c) =>
    COOKIE_DOMAINS.some((d) => c.domain === d || c.domain.endsWith(d)));

  const out = cookieFile(handle);
  fs.writeFileSync(out, JSON.stringify({
    store: handle,
    savedAt: new Date().toISOString(),
    cookies: wanted,
  }, null, 2), {mode: 0o600});
  console.log(`Saved ${wanted.length} Shopify cookies -> ${out}`);
  await browser.close();
  // Marker for Bucky's Client Setup audit + bucky-qa: when was an admin session
  // last saved for this store (cookies themselves never leave this machine).
  try {
    const {execFileSync} = require("child_process");
    const os = require("os");
    const token = execFileSync("gcloud", ["auth", "print-access-token"], {encoding: "utf8"}).trim();
    const doc = `https://firestore.googleapis.com/v1/projects/bucky-app-355a3/databases/(default)/documents/shops/${handle}.myshopify.com?updateMask.fieldPaths=jobReportAuth`;
    const body = JSON.stringify({fields: {jobReportAuth: {mapValue: {fields: {
      savedAt: {timestampValue: new Date().toISOString()},
      host: {stringValue: os.hostname()},
      cookieCount: {integerValue: String(wanted.length)},
    }}}}});
    const res = await fetch(doc, {method: "PATCH", headers: {Authorization: `Bearer ${token}`, "Content-Type": "application/json"}, body});
    console.log(res.ok ? `Recorded jobReportAuth.savedAt on shops/${handle}.myshopify.com` : `(marker write skipped: HTTP ${res.status})`);
  } catch (e) { console.log(`(marker write skipped: ${e.message.split("\n")[0]})`); }
}

main().catch((err) => { console.error("auth failed:", err.message); process.exit(1); });
