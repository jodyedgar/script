#!/usr/bin/env node
/**
 * Check which tickets need scroll alignment
 *
 * Analyzes Feedbucket images to determine if they show top of page
 * or a scrolled position requiring template matching.
 */

import sharp from 'sharp';
import fs from 'fs';
import https from 'https';
import http from 'http';

const QUEUE_FILE = '/Users/jodyedgar/Dropbox/Scripts/notion/batch/results/recapture_queue.json';

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

// Check if image shows top of page (dark header visible)
async function detectsTopOfPage(imagePath) {
  try {
    const meta = await sharp(imagePath).metadata();

    // Check center-top of image for dark nav bar
    const centerX = Math.max(0, Math.floor(meta.width / 2) - 100);
    const sampleWidth = Math.min(200, meta.width - centerX);

    const { data } = await sharp(imagePath)
      .extract({
        left: centerX,
        top: 10,
        width: sampleWidth,
        height: 50
      })
      .ensureAlpha()
      .raw()
      .toBuffer({ resolveWithObject: true });

    // Calculate average brightness
    let totalBrightness = 0;
    const pixelCount = data.length / 4;

    for (let i = 0; i < data.length; i += 4) {
      totalBrightness += (data[i] + data[i+1] + data[i+2]) / 3;
    }

    const avgBrightness = totalBrightness / pixelCount;
    return { isTop: avgBrightness < 80, brightness: avgBrightness };
  } catch (err) {
    return { isTop: true, brightness: 0, error: err.message };
  }
}

async function main() {
  const queue = JSON.parse(fs.readFileSync(QUEUE_FILE, 'utf8'));

  console.error(`Checking ${queue.length} tickets for scroll alignment needs...\n`);

  const needsAlignment = [];
  const topOfPage = [];

  for (let i = 0; i < queue.length; i++) {
    const ticket = queue[i];
    process.stderr.write(`\r[${i+1}/${queue.length}] ${ticket.ticket_id}...`);

    const tempPath = `/tmp/feedbucket_check_${i}.jpg`;

    try {
      await downloadImage(ticket.feedbucket_url, tempPath);
      const result = await detectsTopOfPage(tempPath);

      if (result.isTop) {
        topOfPage.push({
          ticket_id: ticket.ticket_id,
          brightness: result.brightness
        });
      } else {
        needsAlignment.push({
          ticket_id: ticket.ticket_id,
          page_id: ticket.page_id,
          page_url: ticket.page_url,
          feedbucket_url: ticket.feedbucket_url,
          viewport_width: ticket.viewport_width,
          viewport_height: ticket.viewport_height,
          brightness: result.brightness
        });
      }

      // Clean up
      fs.unlinkSync(tempPath);
    } catch (err) {
      console.error(`\nError processing ${ticket.ticket_id}: ${err.message}`);
    }
  }

  console.error('\n\n');
  console.error(`Top of page (no alignment needed): ${topOfPage.length}`);
  console.error(`Needs scroll alignment: ${needsAlignment.length}`);

  if (needsAlignment.length > 0) {
    console.error('\nTickets needing scroll alignment:');
    for (const t of needsAlignment) {
      console.error(`  ${t.ticket_id} (brightness: ${t.brightness.toFixed(1)})`);
    }
  }

  // Output as JSON
  console.log(JSON.stringify({
    topOfPage: topOfPage.length,
    needsAlignment: needsAlignment.length,
    tickets: needsAlignment
  }, null, 2));
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
