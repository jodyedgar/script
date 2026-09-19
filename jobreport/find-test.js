#!/usr/bin/env node
// Try the semantic finder on a live page WITHOUT recording:
//   node find-test.js <url> "<intent>" ["<intent>" ...] [--viewport 390x844] [--password x]
// Prints Jev's pick, the runner-up candidates, and timing. Costs one short
// Browserless session and a fraction of a cent of Jev.
const puppeteer = require("puppeteer-core");
const {getBrowserlessToken, browserlessWsUrl} = require("./lib");
const {findByIntent} = require("./finder");

(async () => {
  const args = process.argv.slice(2);
  const opt = (n) => { const i = args.indexOf(n); return i >= 0 ? args.splice(i, 2)[1] : null; };
  const vpArg = opt("--viewport"); const password = opt("--password");
  const [url, ...intents] = args;
  if (!url || !intents.length) { console.error("usage: node find-test.js <url> \"<intent>\" [...] [--viewport WxH] [--password x]"); process.exit(2); }
  const [w, h] = (vpArg || "1440x900").split("x").map(Number);
  const browser = await puppeteer.connect({browserWSEndpoint: browserlessWsUrl(getBrowserlessToken(), {record: false})});
  try {
    const page = await browser.newPage();
    await page.setViewport({width: w, height: h, isMobile: w < 768, hasTouch: w < 768});
    if (password) {
      const origin = new URL(url).origin;
      await page.goto(`${origin}/password`, {waitUntil: "domcontentloaded", timeout: 30000});
      await page.evaluate(async (pw) => {
        const fd = new URLSearchParams({form_type: "storefront_password", utf8: "✓", password: pw});
        await fetch("/password", {method: "POST", body: fd, redirect: "manual", headers: {"content-type": "application/x-www-form-urlencoded"}});
      }, password);
    }
    await page.goto(url, {waitUntil: "networkidle2", timeout: 45000}).catch(() => {});
    await new Promise((r) => setTimeout(r, 1500));
    for (const intent of intents) {
      const r = await findByIntent(page, intent);
      const show = (c) => `${c.tag}${c.role ? "/" + c.role : ""} ${JSON.stringify(c.text || c.label || c.domId || "")}${c.region ? " @" + c.region : ""} p=${c.p}`;
      console.log(`    runners-up: ${(r.top || []).slice(1).map(show).join(" | ") || "-"}`);
    }
  } finally {
    await browser.close().catch(() => {});
  }
})().catch((e) => { console.error(e.message); process.exit(1); });
