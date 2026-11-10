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

  // A renamed store keeps its permanent myshopify handle, but the admin now
  // lives under the new one: /store/figmate-internal-store redirects to
  // /store/internal-sales-fieldmarketing. So accept the requested handle OR a
  // handle the requested admin URL resolves to while logged in.
  const deadline = Date.now() + LOGIN_WAIT_MS;
  let adminHandle = null;
  while (Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, 2000));
    try {
      const landed = adminStoreHandle(page.url());
      if (!landed || !await page.$("#AppFrameNav, nav")) continue;
      if (landed === handle.toLowerCase()) { adminHandle = handle; break; }
      // Different store in the URL: confirm it IS this store by re-opening the
      // requested admin URL. Shopify only lands there again if it is a redirect.
      await page.goto(adminUrl, {waitUntil: "domcontentloaded"});
      await new Promise((r) => setTimeout(r, 2500));
      if (adminStoreHandle(page.url()) === landed) {
        console.log(`"${handle}" resolves to the renamed admin store "${landed}" (same store).`);
        adminHandle = landed;
        break;
      }
    } catch { /* page navigating; retry */ }
  }
  if (!adminHandle) {
    console.error("Timed out waiting for an authenticated admin session.");
    await browser.close();
    process.exit(1);
  }

  // Grab ALL cookies in the profile via CDP, filter to Shopify domains.
  const cdp = await page.createCDPSession();
  const {cookies} = await cdp.send("Storage.getCookies");
  const wanted = cookies.filter((c) =>
    COOKIE_DOMAINS.some((d) => c.domain === d || c.domain.endsWith(d)));

  // Save under the requested handle (what Bucky tickets and Cody's preflight
  // look up) and, for a renamed store, under the admin handle too.
  const handles = adminHandle === handle ? [handle] : [handle, adminHandle];
  const outs = handles.map((h) => {
    const out = cookieFile(h);
    fs.writeFileSync(out, JSON.stringify({
      store: h,
      adminHandle,
      savedAt: new Date().toISOString(),
      cookies: wanted,
    }, null, 2), {mode: 0o600});
    console.log(`Saved ${wanted.length} Shopify cookies -> ${out}`);
    return out;
  });
  await browser.close();
  outs.forEach(pushJarToCody);
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
      adminHandle: {stringValue: adminHandle},
    }}}}});
    const res = await fetch(doc, {method: "PATCH", headers: {Authorization: `Bearer ${token}`, "Content-Type": "application/json"}, body});
    console.log(res.ok ? `Recorded jobReportAuth.savedAt on shops/${handle}.myshopify.com` : `(marker write skipped: HTTP ${res.status})`);
  } catch (e) { console.log(`(marker write skipped: ${e.message.split("\n")[0]})`); }
}

// cody-macbook runs Cody's cycle preflight, which live-probes the admin with
// this jar before the coder starts (Bucky coordination/preflight/CONTRACT.md
// §3.1, §7). The login needs a passkey + visible Chrome, so it happens here and
// the jar is copied over Tailscale. Best effort: a failed copy never fails auth.
// JOBREPORT_CODY_PUSH=0 disables; JOBREPORT_CODY_HOST overrides the target.
function pushJarToCody(file) {
  if (process.env.JOBREPORT_CODY_PUSH === "0") return;
  const {execFileSync} = require("child_process");
  const path = require("path");
  const host = process.env.JOBREPORT_CODY_HOST || "jodyedgar@100.67.215.41";
  const dir = "~/.config/jobreport/cookies";
  const ssh = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10"];
  try {
    execFileSync("ssh", [...ssh, host, `mkdir -p ${dir} && chmod 700 ${dir}`], {stdio: "pipe"});
    execFileSync("scp", ["-q", "-p", ...ssh, file, `${host}:${dir}/`], {stdio: "pipe"});
    execFileSync("ssh", [...ssh, host, `chmod 600 ${dir}/${path.basename(file)}`], {stdio: "pipe"});
    console.log(`Pushed ${path.basename(file)} -> cody (${host}) for preflight`);
  } catch (e) {
    const why = String(e.stderr || e.message).trim().split("\n")[0];
    console.log(`!! Could NOT push ${path.basename(file)} to cody (${host}): ${why}`);
    console.log(`   Cody's preflight will keep holding this store. Retry: scp -p ${file} ${host}:${dir}/`);
  }
}

// "https://admin.shopify.com/store/<handle>/..." -> "<handle>", else null.
function adminStoreHandle(url) {
  const m = /^https:\/\/admin\.shopify\.com\/store\/([a-z0-9][a-z0-9-]*)(?:[/?#]|$)/i.exec(url);
  return m ? m[1].toLowerCase() : null;
}

main().catch((err) => { console.error("auth failed:", err.message); process.exit(1); });
