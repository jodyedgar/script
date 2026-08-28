// One-off probe: does our Browserless plan support session recording?
// Usage: BROWSERLESS_API_KEY=... node probe-record.js /tmp/probe.webm
const fs = require("fs");
const puppeteer = require("puppeteer-core");

(async () => {
  const token = process.env.BROWSERLESS_API_KEY;
  if (!token) throw new Error("BROWSERLESS_API_KEY not set");
  const out = process.argv[2] || "probe.webm";

  const ws = `wss://production-sfo.browserless.io/?token=${token}&headless=false&stealth=true&record=true&timeout=55000`;
  console.log("connecting...");
  const browser = await puppeteer.connect({ browserWSEndpoint: ws });
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 720 });

  const cdp = await page.createCDPSession();
  await cdp.send("Browserless.startRecording");
  console.log("recording started");

  await page.goto("https://www.sunbowl.ca", { waitUntil: "networkidle2", timeout: 60000 });
  // Smooth scroll for ~6s so the probe has real motion to encode.
  await page.evaluate(() => new Promise((resolve) => {
    const total = Math.min(document.body.scrollHeight - innerHeight, 3000);
    const start = performance.now();
    const dur = 6000;
    (function step(now) {
      const t = Math.min((now - start) / dur, 1);
      scrollTo(0, total * (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2));
      t < 1 ? requestAnimationFrame(step) : resolve();
    })(performance.now());
  }));

  const resp = await cdp.send("Browserless.stopRecording", { encoding: "base64" });
  const buf = Buffer.from(resp.value, "base64");
  fs.writeFileSync(out, buf);
  console.log(`recording saved: ${out} (${buf.length} bytes)`);
  await browser.close();
})().catch((err) => {
  console.error("PROBE FAILED:", err.message);
  process.exit(1);
});
