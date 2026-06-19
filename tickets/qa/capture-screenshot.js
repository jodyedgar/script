#!/usr/bin/env node
/**
 * Capture Screenshot from Chrome DevTools or macOS screencapture
 *
 * Connects to Chrome's DevTools Protocol to take a screenshot.
 * Falls back to macOS screencapture if Chrome debugging isn't available.
 *
 * Usage:
 *   node capture-screenshot.js --output <path> [--full-page]
 */

import { writeFileSync, existsSync, statSync } from 'fs';
import { execSync } from 'child_process';
import WebSocket from 'ws';

// Parse command line arguments
function parseArgs() {
  const args = process.argv.slice(2);
  const parsed = {
    output: './screenshot.png',
    fullPage: false,
    viewport: null, // { width, height } - resize viewport before capture
    url: null, // Navigate to URL before capture
    ports: [9222, 9223, 9224, 9225, 9229], // Try multiple common ports
    useFallback: false // Disabled - macOS screencapture captures wrong monitor
  };

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--output' || args[i] === '-o') {
      parsed.output = args[++i];
    } else if (args[i] === '--full-page' || args[i] === '-f') {
      parsed.fullPage = true;
    } else if (args[i] === '--viewport' || args[i] === '-v') {
      // Parse viewport as WIDTHxHEIGHT (e.g., 1442x1056)
      const dims = args[++i].split('x').map(n => parseInt(n, 10));
      if (dims.length === 2 && !isNaN(dims[0]) && !isNaN(dims[1])) {
        parsed.viewport = { width: dims[0], height: dims[1] };
      } else {
        console.error(`Invalid viewport format: ${args[i]}. Use WIDTHxHEIGHT (e.g., 1442x1056)`);
        process.exit(1);
      }
    } else if (args[i] === '--url' || args[i] === '-u') {
      parsed.url = args[++i];
    } else if (args[i] === '--port' || args[i] === '-p') {
      parsed.ports = [parseInt(args[++i], 10)];
    } else if (args[i] === '--no-fallback') {
      parsed.useFallback = false;
    } else if (args[i] === '--help' || args[i] === '-h') {
      console.log(`
Capture Screenshot from Chrome DevTools

Usage:
  node capture-screenshot.js --output <path> [--full-page] [--viewport WxH] [--url URL]

Options:
  --output, -o PATH      Output file path (default: ./screenshot.png)
  --full-page, -f        Capture full page instead of viewport
  --viewport, -v WxH     Resize viewport before capture (e.g., 1442x1056)
  --url, -u URL          Navigate to URL before capture
  --port, -p PORT        Chrome DevTools port (default: tries 9222-9225, 9229)
  --no-fallback          Don't fall back to macOS screencapture
  --help, -h             Show this help message

Requirements:
  Chrome must be running with remote debugging:
  /Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome --remote-debugging-port=9222

  Or the script will fall back to macOS screencapture (captures frontmost window).
`);
      process.exit(0);
    }
  }

  return parsed;
}

// Try to get list of available pages from Chrome on given port
async function tryGetPages(port, timeout = 2000) {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeout);

  try {
    const response = await fetch(`http://localhost:${port}/json`, {
      signal: controller.signal
    });
    clearTimeout(timeoutId);

    if (!response.ok) {
      return null;
    }
    return { port, pages: await response.json() };
  } catch (e) {
    clearTimeout(timeoutId);
    return null;
  }
}

// Find Chrome debugging port by trying multiple ports
async function findChromeDebugPort(ports) {
  for (const port of ports) {
    const result = await tryGetPages(port);
    if (result && result.pages && result.pages.length > 0) {
      return result;
    }
  }
  return null;
}

// Connect to Chrome DevTools via WebSocket
function connectToPage(wsUrl) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    const timeout = setTimeout(() => {
      ws.close();
      reject(new Error('WebSocket connection timeout'));
    }, 5000);

    ws.on('open', () => {
      clearTimeout(timeout);
      resolve(ws);
    });
    ws.on('error', (err) => {
      clearTimeout(timeout);
      reject(err);
    });
  });
}

// Send CDP command
async function sendCommand(ws, method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = Date.now();
    const timeout = setTimeout(() => {
      reject(new Error(`Command ${method} timed out`));
    }, 10000);

    const handler = (data) => {
      const response = JSON.parse(data.toString());
      if (response.id === id) {
        clearTimeout(timeout);
        ws.off('message', handler);
        if (response.error) {
          reject(new Error(response.error.message));
        } else {
          resolve(response.result);
        }
      }
    };

    ws.on('message', handler);
    ws.send(JSON.stringify({ id, method, params }));
  });
}

// Capture using Chrome DevTools
async function captureWithChrome(args, chromeInfo) {
  const { port, pages } = chromeInfo;

  // Find the first http/https page (prefer actual web pages over chrome:// pages)
  let page = pages.find(p =>
    p.type === 'page' &&
    (p.url.startsWith('http://') || p.url.startsWith('https://'))
  );

  // Fallback to any non-extension page if no http page found
  if (!page) {
    page = pages.find(p =>
      p.type === 'page' &&
      !p.url.startsWith('chrome-extension://') &&
      !p.url.startsWith('devtools://')
    );
  }

  if (!page) {
    throw new Error('No suitable page found in Chrome');
  }

  console.error(`Connecting to: ${page.title} (${page.url})`);

  // Connect to the page
  const ws = await connectToPage(page.webSocketDebuggerUrl);

  try {
    // Set viewport if specified (must be done BEFORE navigation)
    if (args.viewport) {
      console.error(`Setting viewport: ${args.viewport.width}x${args.viewport.height}`);
      await sendCommand(ws, 'Emulation.setDeviceMetricsOverride', {
        width: args.viewport.width,
        height: args.viewport.height,
        deviceScaleFactor: 1,
        mobile: args.viewport.width < 768
      });
    }

    // Navigate to URL if specified
    if (args.url) {
      console.error(`Navigating to: ${args.url}`);
      await sendCommand(ws, 'Page.enable');
      await sendCommand(ws, 'Page.navigate', { url: args.url });
      // Wait for page load
      await new Promise(resolve => setTimeout(resolve, 3000));
      // Update page info for result
      page.url = args.url;
    }

    // Get page dimensions if full page capture
    if (args.fullPage) {
      const { result } = await sendCommand(ws, 'Runtime.evaluate', {
        expression: 'JSON.stringify({width: document.documentElement.scrollWidth, height: document.documentElement.scrollHeight})',
        returnByValue: true
      });
      const dims = JSON.parse(result.value);
      console.error(`Full page dimensions: ${dims.width}x${dims.height}`);

      await sendCommand(ws, 'Emulation.setDeviceMetricsOverride', {
        width: args.viewport ? args.viewport.width : dims.width,
        height: dims.height,
        deviceScaleFactor: 1,
        mobile: args.viewport ? args.viewport.width < 768 : false
      });
    }

    // Scroll to top before capture
    await sendCommand(ws, 'Runtime.evaluate', {
      expression: 'window.scrollTo(0, 0)',
      returnByValue: true
    });
    await new Promise(resolve => setTimeout(resolve, 500));

    // Take screenshot
    console.error(`Capturing screenshot...`);
    const screenshot = await sendCommand(ws, 'Page.captureScreenshot', {
      format: args.output.endsWith('.jpg') || args.output.endsWith('.jpeg') ? 'jpeg' : 'png',
      quality: 90,
      captureBeyondViewport: args.fullPage
    });

    // Reset viewport if we changed it
    if (args.fullPage || args.viewport) {
      await sendCommand(ws, 'Emulation.clearDeviceMetricsOverride');
    }

    // Save screenshot
    const buffer = Buffer.from(screenshot.data, 'base64');
    writeFileSync(args.output, buffer);

    return {
      success: true,
      method: 'chrome-devtools',
      file: args.output,
      size: buffer.length,
      viewport: args.viewport,
      fullPage: args.fullPage,
      page: {
        title: page.title,
        url: page.url
      }
    };

  } finally {
    ws.close();
  }
}

// Capture using macOS screencapture (fallback)
function captureWithScreencapture(args) {
  try {
    // Capture the frontmost window (-w waits for user to click a window)
    // Using -l to capture a specific window would require the window ID
    // For now, capture the frontmost window without interaction
    execSync(`screencapture -x "${args.output}"`, { stdio: 'pipe' });

    if (existsSync(args.output)) {
      const stats = statSync(args.output);
      return {
        success: true,
        method: 'macos-screencapture',
        file: args.output,
        size: stats.size,
        note: 'Captured using macOS screencapture (full screen)'
      };
    }
    throw new Error('Screenshot file was not created');
  } catch (e) {
    throw new Error(`macOS screencapture failed: ${e.message}`);
  }
}

// Main function
async function main() {
  const args = parseArgs();

  // Try Chrome DevTools first
  const chromeInfo = await findChromeDebugPort(args.ports);

  if (chromeInfo) {
    try {
      const result = await captureWithChrome(args, chromeInfo);
      console.log(JSON.stringify(result));
      return;
    } catch (error) {
      console.error(`Chrome capture failed: ${error.message}`);
      if (!args.useFallback) {
        console.error(JSON.stringify({ error: error.message }));
        process.exit(1);
      }
    }
  }

  // Fall back to macOS screencapture
  if (args.useFallback) {
    console.error('Chrome DevTools not available, using macOS screencapture...');
    try {
      const result = captureWithScreencapture(args);
      console.log(JSON.stringify(result));
      return;
    } catch (error) {
      console.error(JSON.stringify({
        error: error.message,
        hint: 'Start Chrome with: /Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome --remote-debugging-port=9222'
      }));
      process.exit(1);
    }
  }

  // No methods available
  console.error(JSON.stringify({
    error: 'Cannot connect to Chrome DevTools',
    hint: 'Start Chrome with: /Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome --remote-debugging-port=9222',
    tried_ports: args.ports
  }));
  process.exit(1);
}

main();
