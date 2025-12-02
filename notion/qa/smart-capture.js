#!/usr/bin/env node
/**
 * Smart QA capture that matches Feedbucket screenshot region.
 * - Gets Feedbucket image dimensions for viewport sizing
 * - Detects if screenshot is from top of page (header visible)
 * - Uses pixel comparison for scroll position matching
 */

import sharp from 'sharp';
import https from 'https';
import http from 'http';
import fs from 'fs';
import path from 'path';

/**
 * Download image from URL to local path
 */
async function downloadImage(url, outputPath) {
  return new Promise((resolve, reject) => {
    const protocol = url.startsWith('https') ? https : http;
    const file = fs.createWriteStream(outputPath);

    protocol.get(url, (response) => {
      if (response.statusCode === 301 || response.statusCode === 302) {
        // Handle redirect
        downloadImage(response.headers.location, outputPath)
          .then(resolve)
          .catch(reject);
        return;
      }

      response.pipe(file);
      file.on('finish', () => {
        file.close();
        resolve(outputPath);
      });
    }).on('error', (err) => {
      fs.unlink(outputPath, () => {});
      reject(err);
    });
  });
}

/**
 * Get image dimensions from URL or local path
 */
async function getImageDimensions(pathOrUrl) {
  let imagePath = pathOrUrl;

  if (pathOrUrl.startsWith('http')) {
    imagePath = '/tmp/feedbucket_dim_check.jpg';
    await downloadImage(pathOrUrl, imagePath);
  }

  const metadata = await sharp(imagePath).metadata();
  return {
    width: metadata.width,
    height: metadata.height
  };
}

/**
 * Detect if image shows top of page (header visible)
 * Looks for dark header bar in top portion of image
 */
async function detectHeaderVisible(pathOrUrl) {
  let imagePath = pathOrUrl;

  if (pathOrUrl.startsWith('http')) {
    imagePath = '/tmp/feedbucket_header_check.jpg';
    await downloadImage(pathOrUrl, imagePath);
  }

  // Extract top 80 pixels and analyze
  const topRegion = await sharp(imagePath)
    .extract({ left: 0, top: 0, width: 1000, height: 80 })
    .grayscale()
    .raw()
    .toBuffer({ resolveWithObject: true });

  const { data, info } = topRegion;

  // Count dark pixels (typical for header bars)
  let darkPixels = 0;
  for (let i = 0; i < data.length; i++) {
    if (data[i] < 60) darkPixels++;
  }

  const darkRatio = darkPixels / data.length;

  // Header typically present if more than 5% of top region is dark
  return darkRatio > 0.05;
}

/**
 * Find scroll position by comparing template to full page screenshot
 * Uses a simplified pixel matching approach
 */
async function findScrollPosition(fullPagePath, templatePathOrUrl) {
  let templatePath = templatePathOrUrl;

  if (templatePathOrUrl.startsWith('http')) {
    templatePath = '/tmp/feedbucket_scroll_template.jpg';
    await downloadImage(templatePathOrUrl, templatePath);
  }

  // Get dimensions
  const fullMeta = await sharp(fullPagePath).metadata();
  const tmplMeta = await sharp(templatePath).metadata();

  // Resize template to match full page width
  const scaledTemplate = await sharp(templatePath)
    .resize(fullMeta.width, null)
    .grayscale()
    .raw()
    .toBuffer({ resolveWithObject: true });

  const scaledHeight = scaledTemplate.info.height;

  // Get full page as grayscale
  const fullPage = await sharp(fullPagePath)
    .grayscale()
    .raw()
    .toBuffer({ resolveWithObject: true });

  // Simple vertical scan to find best match
  let bestY = 0;
  let bestScore = Infinity;
  const stepSize = 10; // Check every 10 pixels for speed

  for (let y = 0; y <= fullMeta.height - scaledHeight; y += stepSize) {
    let diff = 0;
    const sampleStep = 100; // Sample every 100th pixel for speed

    for (let i = 0; i < scaledTemplate.data.length; i += sampleStep) {
      const fullIdx = (y * fullMeta.width) + (i % fullMeta.width) +
                      Math.floor(i / scaledTemplate.info.width) * fullMeta.width;
      diff += Math.abs(scaledTemplate.data[i] - (fullPage.data[fullIdx] || 0));
    }

    if (diff < bestScore) {
      bestScore = diff;
      bestY = y;
    }
  }

  return {
    scroll_y: bestY,
    confidence: 1 - (bestScore / (scaledTemplate.data.length / 100 * 255)),
    template_height: scaledHeight
  };
}

/**
 * Analyze what's needed to capture the same region as Feedbucket
 */
async function analyzeCaptureRequirements(feedbucketUrl, fullPagePath = null) {
  // Get Feedbucket image dimensions
  const dims = await getImageDimensions(feedbucketUrl);

  // Check if header is visible (top of page)
  const headerVisible = await detectHeaderVisible(feedbucketUrl);

  const result = {
    viewport_width: dims.width,
    viewport_height: dims.height,
    capture_type: headerVisible ? 'viewport' : 'scroll_match',
    header_visible: headerVisible
  };

  // If header not visible and we have a full page screenshot, find scroll position
  if (!headerVisible && fullPagePath) {
    const scrollInfo = await findScrollPosition(fullPagePath, feedbucketUrl);
    result.scroll_y = scrollInfo.scroll_y;
    result.match_confidence = scrollInfo.confidence;
  } else if (!headerVisible) {
    result.needs_full_page = true;
  }

  return result;
}

/**
 * Build recapture queue with viewport info for all tickets
 */
async function buildRecaptureQueue(inputQueuePath, outputQueuePath) {
  const queue = JSON.parse(fs.readFileSync(inputQueuePath, 'utf8'));

  const recaptureQueue = [];

  for (const item of queue) {
    const fbUrl = item.feedbucket_url;
    if (fbUrl) {
      try {
        const dims = await getImageDimensions(fbUrl);
        item.viewport_width = dims.width;
        item.viewport_height = dims.height;
        item.capture_type = 'viewport';
      } catch (err) {
        console.error(`Error getting dimensions for ${item.ticket_id}: ${err.message}`);
        item.viewport_width = 1440;
        item.viewport_height = 900;
        item.capture_type = 'viewport';
      }
    }
    recaptureQueue.push(item);
  }

  fs.writeFileSync(outputQueuePath, JSON.stringify(recaptureQueue, null, 2));

  // Group by page_url + viewport
  const groups = {};
  for (const item of recaptureQueue) {
    const key = `${item.page_url.split('?')[0]}|${item.viewport_width}x${item.viewport_height}`;
    if (!groups[key]) groups[key] = [];
    groups[key].push(item);
  }

  return { queue: recaptureQueue, groups };
}

// CLI interface
async function main() {
  const args = process.argv.slice(2);

  if (args.includes('--help') || args.length === 0) {
    console.log(`
Smart QA Capture Tool

Usage:
  node smart-capture.js --analyze --feedbucket-url <url> [--full-page <path>]
  node smart-capture.js --build-queue --input <queue.json> --output <recapture.json>
  node smart-capture.js --dimensions --feedbucket-url <url>

Options:
  --analyze           Analyze Feedbucket image for capture requirements
  --build-queue       Build recapture queue with viewport info
  --dimensions        Just get image dimensions
  --feedbucket-url    URL to Feedbucket image
  --full-page         Path to full page screenshot (for scroll detection)
  --input             Input queue JSON file
  --output            Output queue JSON file
`);
    process.exit(0);
  }

  try {
    if (args.includes('--dimensions')) {
      const urlIdx = args.indexOf('--feedbucket-url');
      const url = args[urlIdx + 1];
      const dims = await getImageDimensions(url);
      console.log(JSON.stringify(dims));
    }
    else if (args.includes('--analyze')) {
      const urlIdx = args.indexOf('--feedbucket-url');
      const url = args[urlIdx + 1];
      const fullPageIdx = args.indexOf('--full-page');
      const fullPage = fullPageIdx !== -1 ? args[fullPageIdx + 1] : null;

      const result = await analyzeCaptureRequirements(url, fullPage);
      console.log(JSON.stringify(result));
    }
    else if (args.includes('--build-queue')) {
      const inputIdx = args.indexOf('--input');
      const outputIdx = args.indexOf('--output');
      const inputPath = args[inputIdx + 1];
      const outputPath = args[outputIdx + 1];

      const { queue, groups } = await buildRecaptureQueue(inputPath, outputPath);

      console.log(`Generated recapture queue with ${queue.length} tickets`);
      console.log(`\nGrouped into ${Object.keys(groups).length} unique page+viewport combinations:`);

      const sorted = Object.entries(groups).sort((a, b) => b[1].length - a[1].length);
      for (const [key, items] of sorted) {
        console.log(`  ${key}: ${items.length} tickets`);
      }
    }
  } catch (err) {
    console.error(JSON.stringify({ error: err.message }));
    process.exit(1);
  }
}

main();

export {
  getImageDimensions,
  detectHeaderVisible,
  findScrollPosition,
  analyzeCaptureRequirements,
  buildRecaptureQueue
};
