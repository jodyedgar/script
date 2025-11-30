#!/usr/bin/env node
/**
 * Capture Screenshot from Chrome DevTools
 *
 * Connects to Chrome's DevTools Protocol to take a screenshot.
 * Chrome must be running with remote debugging enabled.
 *
 * Usage:
 *   node capture-screenshot.js --output <path> [--full-page]
 */

import { writeFileSync } from 'fs';
import { basename } from 'path';
import WebSocket from 'ws';

// Parse command line arguments
function parseArgs() {
  const args = process.argv.slice(2);
  const parsed = {
    output: './screenshot.png',
    fullPage: false,
    port: 9222
  };

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--output' || args[i] === '-o') {
      parsed.output = args[++i];
    } else if (args[i] === '--full-page' || args[i] === '-f') {
      parsed.fullPage = true;
    } else if (args[i] === '--port' || args[i] === '-p') {
      parsed.port = parseInt(args[++i], 10);
    } else if (args[i] === '--help' || args[i] === '-h') {
      console.log(`
Capture Screenshot from Chrome DevTools

Usage:
  node capture-screenshot.js --output <path> [--full-page]

Options:
  --output, -o PATH    Output file path (default: ./screenshot.png)
  --full-page, -f      Capture full page instead of viewport
  --port, -p PORT      Chrome DevTools port (default: 9222)
  --help, -h           Show this help message

Requirements:
  Chrome must be running with remote debugging:
  /Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome --remote-debugging-port=9222
`);
      process.exit(0);
    }
  }

  return parsed;
}

// Get list of available pages from Chrome
async function getPages(port) {
  const response = await fetch(`http://localhost:${port}/json`);
  if (!response.ok) {
    throw new Error(`Failed to connect to Chrome DevTools on port ${port}`);
  }
  return response.json();
}

// Connect to Chrome DevTools via WebSocket
function connectToPage(wsUrl) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);

    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

// Send CDP command
async function sendCommand(ws, method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = Date.now();

    const handler = (data) => {
      const response = JSON.parse(data.toString());
      if (response.id === id) {
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

// Main function
async function main() {
  const args = parseArgs();

  try {
    // Get available pages
    const pages = await getPages(args.port);

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
      console.error(JSON.stringify({
        error: 'No suitable page found in Chrome',
        hint: 'Make sure Chrome has a regular webpage open'
      }));
      process.exit(1);
    }

    console.error(`Capturing: ${page.title} (${page.url})`);

    // Connect to the page
    const ws = await connectToPage(page.webSocketDebuggerUrl);

    try {
      // Get page dimensions if full page capture
      let clip = undefined;
      if (args.fullPage) {
        // Get full page dimensions
        const { result } = await sendCommand(ws, 'Runtime.evaluate', {
          expression: 'JSON.stringify({width: document.documentElement.scrollWidth, height: document.documentElement.scrollHeight})',
          returnByValue: true
        });
        const dims = JSON.parse(result.value);

        // Set viewport to full page size
        await sendCommand(ws, 'Emulation.setDeviceMetricsOverride', {
          width: dims.width,
          height: dims.height,
          deviceScaleFactor: 1,
          mobile: false
        });
      }

      // Take screenshot
      const screenshot = await sendCommand(ws, 'Page.captureScreenshot', {
        format: args.output.endsWith('.jpg') || args.output.endsWith('.jpeg') ? 'jpeg' : 'png',
        quality: 90,
        captureBeyondViewport: args.fullPage
      });

      // Reset viewport if we changed it
      if (args.fullPage) {
        await sendCommand(ws, 'Emulation.clearDeviceMetricsOverride');
      }

      // Save screenshot
      const buffer = Buffer.from(screenshot.data, 'base64');
      writeFileSync(args.output, buffer);

      console.log(JSON.stringify({
        success: true,
        file: args.output,
        size: buffer.length,
        page: {
          title: page.title,
          url: page.url
        }
      }));

    } finally {
      ws.close();
    }

  } catch (error) {
    if (error.message.includes('ECONNREFUSED')) {
      console.error(JSON.stringify({
        error: 'Cannot connect to Chrome DevTools',
        hint: 'Start Chrome with: /Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome --remote-debugging-port=9222',
        port: args.port
      }));
    } else {
      console.error(JSON.stringify({
        error: error.message
      }));
    }
    process.exit(1);
  }
}

main();
