#!/usr/bin/env node
/**
 * Align Screenshot - Template Matching for Scroll Position
 *
 * Uses template matching to find where a Feedbucket screenshot
 * appears within a full-page capture, then crops that region.
 *
 * Usage:
 *   node align-screenshot.js --template <feedbucket.jpg> --fullpage <fullpage.png> --output <aligned.png>
 */

import sharp from 'sharp';
import fs from 'fs';
import https from 'https';
import http from 'http';
import path from 'path';

// Parse command line arguments
function parseArgs() {
  const args = process.argv.slice(2);
  const parsed = {};

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--template' || args[i] === '-t') {
      parsed.template = args[++i];
    } else if (args[i] === '--fullpage' || args[i] === '-f') {
      parsed.fullpage = args[++i];
    } else if (args[i] === '--output' || args[i] === '-o') {
      parsed.output = args[++i];
    } else if (args[i] === '--threshold') {
      parsed.threshold = parseFloat(args[++i]);
    }
  }

  return parsed;
}

// Download image from URL
async function downloadImage(url, destPath) {
  return new Promise((resolve, reject) => {
    const proto = url.startsWith('https') ? https : http;
    const file = fs.createWriteStream(destPath);

    proto.get(url, (response) => {
      if (response.statusCode === 301 || response.statusCode === 302) {
        downloadImage(response.headers.location, destPath).then(resolve).catch(reject);
        return;
      }
      response.pipe(file);
      file.on('finish', () => {
        file.close();
        resolve(destPath);
      });
    }).on('error', (err) => {
      fs.unlink(destPath, () => {});
      reject(err);
    });
  });
}

// Get raw pixel data from image
async function getPixelData(imagePath) {
  const image = sharp(imagePath);
  const metadata = await image.metadata();
  const { data, info } = await image
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });

  return {
    data,
    width: info.width,
    height: info.height,
    channels: info.channels
  };
}

// Calculate similarity between two regions using Sum of Squared Differences (SSD)
// Lower score = better match
// IMPORTANT:
// - Skip the fixed header area (top ~80px)
// - Focus on left 50% where product image typically is (more stable than text on right)
// - Weight colorful pixels more heavily (they're more distinctive than gray/white backgrounds)
const FIXED_HEADER_HEIGHT = 80;

function getColorfulness(r, g, b) {
  // How "colorful" is this pixel? Gray pixels have low colorfulness
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const saturation = max === 0 ? 0 : (max - min) / max;
  return saturation;
}

function calculateSSD(fullpageData, templateData, startY, sampleStep = 4) {
  const fw = fullpageData.width;
  const tw = templateData.width;
  const th = templateData.height;
  const channels = 4; // RGBA

  let totalDiff = 0;
  let totalWeight = 0;

  // Only sample left 50% of image (product images are usually on left, text on right changes)
  const maxX = Math.floor(tw * 0.5);

  // Sample pixels (skip some for speed)
  // Start from FIXED_HEADER_HEIGHT to skip the fixed header
  for (let ty = FIXED_HEADER_HEIGHT; ty < th; ty += sampleStep) {
    for (let tx = 0; tx < maxX; tx += sampleStep) {
      const tIdx = (ty * tw + tx) * channels;
      const fIdx = ((startY + ty) * fw + tx) * channels;

      const tR = templateData.data[tIdx];
      const tG = templateData.data[tIdx + 1];
      const tB = templateData.data[tIdx + 2];

      // Weight colorful pixels more heavily (3x for saturated colors)
      const colorfulness = getColorfulness(tR, tG, tB);
      const weight = 1 + colorfulness * 2; // 1-3x weight based on saturation

      // Compare RGB
      for (let c = 0; c < 3; c++) {
        const diff = fullpageData.data[fIdx + c] - templateData.data[tIdx + c];
        totalDiff += diff * diff * weight;
      }
      totalWeight += weight * 3; // 3 channels
    }
  }

  // Normalize by total weight and max possible diff
  return totalDiff / (totalWeight * 255 * 255);
}

// Find best match position using sliding window
async function findBestMatch(fullpagePath, templatePath, stepSize = 10) {
  console.error('Loading images...');

  const fullpage = await getPixelData(fullpagePath);
  const template = await getPixelData(templatePath);

  console.error(`Fullpage: ${fullpage.width}x${fullpage.height}`);
  console.error(`Template: ${template.width}x${template.height}`);

  // If template is wider than fullpage, resize template to match width
  let resizedTemplate = template;
  if (template.width !== fullpage.width) {
    console.error(`Resizing template to match fullpage width (${fullpage.width})...`);
    const resizedPath = '/tmp/resized_template.png';
    await sharp(templatePath)
      .resize(fullpage.width, null, { fit: 'fill' })
      .toFile(resizedPath);
    resizedTemplate = await getPixelData(resizedPath);
    console.error(`Resized template: ${resizedTemplate.width}x${resizedTemplate.height}`);
  }

  const maxY = fullpage.height - resizedTemplate.height;

  if (maxY < 0) {
    console.error('Template is taller than fullpage - returning top of page');
    return { y: 0, confidence: 0, height: fullpage.height };
  }

  console.error(`Searching for best match (0 to ${maxY})...`);

  let bestY = 0;
  let bestScore = Infinity;

  // First pass: coarse search
  for (let y = 0; y <= maxY; y += stepSize) {
    const score = calculateSSD(fullpage, resizedTemplate, y);
    if (score < bestScore) {
      bestScore = score;
      bestY = y;
    }

    if (y % 100 === 0) {
      process.stderr.write(`\rSearching... ${Math.round(y/maxY*100)}%`);
    }
  }
  console.error('');

  // Second pass: fine search around best position
  const fineStart = Math.max(0, bestY - stepSize);
  const fineEnd = Math.min(maxY, bestY + stepSize);

  for (let y = fineStart; y <= fineEnd; y++) {
    const score = calculateSSD(fullpage, resizedTemplate, y, 2);
    if (score < bestScore) {
      bestScore = score;
      bestY = y;
    }
  }

  // Convert score to confidence (1 - normalized_score)
  const confidence = Math.max(0, 1 - bestScore);

  console.error(`Best match at Y=${bestY} with confidence ${(confidence * 100).toFixed(1)}%`);

  return {
    y: bestY,
    confidence,
    templateHeight: resizedTemplate.height
  };
}

// Extract region from fullpage at given position
async function extractRegion(fullpagePath, y, width, height, outputPath) {
  await sharp(fullpagePath)
    .extract({ left: 0, top: y, width, height })
    .toFile(outputPath);

  console.error(`Extracted region saved to ${outputPath}`);
}

// Main function
async function main() {
  const args = parseArgs();
  const MIN_CONFIDENCE = args.threshold || 0.75; // 75% default threshold

  if (!args.template || !args.fullpage || !args.output) {
    console.error('Usage: node align-screenshot.js --template <url_or_path> --fullpage <path> --output <path> [--threshold 0.75]');
    process.exit(1);
  }

  let templatePath = args.template;

  // Download template if it's a URL
  if (args.template.startsWith('http')) {
    console.error('Downloading template image...');
    templatePath = '/tmp/template_for_matching.jpg';
    await downloadImage(args.template, templatePath);
  }

  // Get template dimensions
  const templateMeta = await sharp(templatePath).metadata();

  // Always use template matching to find scroll position
  // (Fixed header appears at same position regardless of scroll)
  console.error('Finding scroll position via template matching...');
  const match = await findBestMatch(args.fullpage, templatePath);

  const scrollY = match.y;
  const confidence = match.confidence;

  if (confidence < MIN_CONFIDENCE) {
    console.error(`Warning: Low confidence (${(confidence*100).toFixed(1)}%) - content may have changed significantly`);
  }

  // Get fullpage dimensions
  const fullpageMeta = await sharp(args.fullpage).metadata();

  // Extract the matching region
  const extractHeight = Math.min(templateMeta.height, fullpageMeta.height - scrollY);
  await extractRegion(args.fullpage, scrollY, fullpageMeta.width, extractHeight, args.output);

  // Output result as JSON
  console.log(JSON.stringify({
    success: true,
    scrollY: scrollY,
    confidence: confidence,
    meetsThreshold: confidence >= MIN_CONFIDENCE,
    extractedHeight: extractHeight,
    output: args.output
  }));
}

main().catch(err => {
  console.error(JSON.stringify({ error: err.message }));
  process.exit(1);
});
