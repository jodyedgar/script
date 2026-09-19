// Visible cursor + pacing for recordings. The point of a walkthrough is to
// TEACH: the viewer must be able to follow where the click is going. A model
// that resolves a target in 130ms removes the natural pause a slow model used
// to give, so the pace is now explicit: glide a drawn cursor to the target,
// rest on it (with a highlight ring), click with a ripple, then rest again so
// the result can be seen. Nothing here touches the page's own behaviour: the
// overlay is pointer-events:none and lives in the top frame, above iframes.
//
// Scenario-level "pacing": false disables everything; "pacing": {...} overrides
// any of the defaults below.
const DEFAULTS = {
  cursor: true,          // draw the cursor
  highlight: true,       // ring around the target while resting on it
  moveMs: 900,           // glide time to the target
  dwellBeforeMs: 600,    // rest on the target before clicking
  dwellAfterMs: 1200,    // rest after the click so the result is visible
  afterNavMs: 1500,      // rest after a navigation so the new page registers
  typeDelayMs: 60,       // per-character typing delay
};

const CURSOR_ID = "__jr_cursor";

function resolvePacing(raw) {
  if (raw === false) return {...DEFAULTS, cursor: false, highlight: false, moveMs: 0, dwellBeforeMs: 0, dwellAfterMs: 0, afterNavMs: 0, enabled: false};
  return {...DEFAULTS, ...(raw && typeof raw === "object" ? raw : {}), enabled: true};
}

const sleep = (ms) => (ms > 0 ? new Promise((r) => setTimeout(r, ms)) : Promise.resolve());

// Injected into the TOP frame. Idempotent; survives being called after every navigation.
function installOverlay(id, x, y) {
  if (document.getElementById(id)) return;
  const el = document.createElement("div");
  el.id = id;
  el.setAttribute("aria-hidden", "true");
  el.style.cssText = `position:fixed;left:0;top:0;width:28px;height:28px;z-index:2147483647;pointer-events:none;` +
    `transform:translate(${x}px,${y}px);transition:transform 0ms cubic-bezier(.25,.8,.25,1);filter:drop-shadow(0 1px 2px rgba(0,0,0,.45));`;
  el.innerHTML = `<svg width="28" height="28" viewBox="0 0 28 28" xmlns="http://www.w3.org/2000/svg">` +
    `<path d="M4 3 L4 22 L9.2 17.6 L12.6 25 L16 23.6 L12.6 16.4 L19.5 16.4 Z" fill="#111" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>`;
  const ring = document.createElement("div");
  ring.id = id + "_ring";
  ring.style.cssText = "position:fixed;left:0;top:0;width:0;height:0;z-index:2147483646;pointer-events:none;" +
    "border:3px solid #7ECCEE;border-radius:8px;box-shadow:0 0 0 3px rgba(126,204,238,.35);opacity:0;transition:opacity 200ms;";
  document.documentElement.appendChild(ring);
  document.documentElement.appendChild(el);
}

class Cursor {
  constructor(page, pacing) {
    this.page = page;
    this.p = pacing;
    this.x = 0;
    this.y = 0;
  }

  async ensure() {
    if (!this.p.cursor) return;
    const vp = this.page.viewport() || {width: 1440, height: 900};
    if (!this.x && !this.y) { this.x = Math.round(vp.width * 0.6); this.y = Math.round(vp.height * 0.55); }
    await this.page.evaluate(installOverlay, CURSOR_ID, this.x, this.y).catch(() => {});
  }

  /** Glide to page (top-frame) coordinates. */
  async moveTo(x, y, ms = this.p.moveMs) {
    if (!this.p.cursor) return;
    await this.ensure();
    const dist = Math.hypot(x - this.x, y - this.y);
    const dur = dist < 40 ? Math.min(ms, 250) : ms; // tiny hops should not crawl
    this.x = x; this.y = y;
    await this.page.evaluate((id, x, y, dur) => {
      const el = document.getElementById(id);
      if (!el) return;
      el.style.transition = `transform ${dur}ms cubic-bezier(.25,.8,.25,1)`;
      // force a style flush so the new transition applies to this move
      void el.offsetWidth;
      el.style.transform = `translate(${x - 2}px,${y - 2}px)`;
    }, CURSOR_ID, x, y, dur).catch(() => {});
    await sleep(dur + 50);
  }

  async highlight(box, on) {
    if (!this.p.highlight || !this.p.cursor) return;
    await this.page.evaluate((id, box, on) => {
      const ring = document.getElementById(id + "_ring");
      if (!ring) return;
      if (on && box) {
        ring.style.left = `${box.x - 6}px`; ring.style.top = `${box.y - 6}px`;
        ring.style.width = `${box.width + 12}px`; ring.style.height = `${box.height + 12}px`;
        ring.style.opacity = "1";
      } else ring.style.opacity = "0";
    }, CURSOR_ID, box, on).catch(() => {});
  }

  async ripple() {
    if (!this.p.cursor) return;
    await this.page.evaluate((x, y) => {
      const r = document.createElement("div");
      r.style.cssText = `position:fixed;left:${x - 4}px;top:${y - 4}px;width:8px;height:8px;border-radius:50%;` +
        "border:3px solid #7ECCEE;z-index:2147483647;pointer-events:none;opacity:.95;transition:all 450ms ease-out;";
      document.documentElement.appendChild(r);
      requestAnimationFrame(() => {
        r.style.left = `${x - 22}px`; r.style.top = `${y - 22}px`; r.style.width = "44px"; r.style.height = "44px"; r.style.opacity = "0";
      });
      setTimeout(() => r.remove(), 600);
    }, this.x, this.y).catch(() => {});
  }

  /**
   * The full teaching beat around a click: scroll the target into view, glide
   * to it, rest with a ring, click, ripple, rest. `doClick` performs the actual
   * click (element handle click, label click, ...).
   */
  async clickBeat(handle, doClick, {nextIsPause = false} = {}) {
    let box = null;
    if (handle) {
      await handle.evaluate((e) => e.scrollIntoView({block: "center", inline: "nearest", behavior: "smooth"})).catch(() => {});
      await sleep(this.p.enabled ? 500 : 0);
      box = await handle.boundingBox().catch(() => null);
    }
    if (box) {
      await this.moveTo(box.x + box.width / 2, box.y + Math.min(box.height / 2, box.height - 4));
      await this.highlight(box, true);
      await sleep(this.p.dwellBeforeMs);
    }
    await this.highlight(box, false);
    await this.ripple();
    // doClick may report that the click navigated (record.js clickAndSettle):
    // then the new page has already been waited for and the post-navigation
    // rest replaces the post-click rest. The overlay is re-created by ensure().
    const settledMs = await doClick();
    if (settledMs) return this.afterNavigation(settledMs);
    await sleep(nextIsPause ? Math.min(this.p.dwellAfterMs, 300) : this.p.dwellAfterMs);
  }

  /** Rest after a navigation; time the viewer already spent watching it load counts. */
  async afterNavigation(alreadyWaitedMs = 0) {
    await this.ensure();
    await sleep(Math.max(300, this.p.afterNavMs - alreadyWaitedMs));
  }
}

module.exports = {Cursor, resolvePacing, DEFAULTS, CURSOR_ID};
