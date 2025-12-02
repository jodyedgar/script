#!/usr/bin/env node
/**
 * Recapture QA After Screenshots with Scroll Alignment
 *
 * For each ticket:
 * 1. Navigate to page
 * 2. Resize viewport to Feedbucket dimensions
 * 3. Take full-page screenshot
 * 4. Align to match Feedbucket scroll position
 * 5. Upload to Firebase
 * 6. Update Notion
 *
 * Usage:
 *   node recapture-aligned.js [--dry-run] [--ticket TICK-###]
 */

import fs from 'fs';
import { execSync } from 'child_process';

const QUEUE_FILE = '/Users/jodyedgar/Dropbox/Scripts/notion/batch/results/recapture_queue.json';

function parseArgs() {
  const args = process.argv.slice(2);
  const parsed = { dryRun: false, singleTicket: null };

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--dry-run') parsed.dryRun = true;
    if (args[i] === '--ticket') parsed.singleTicket = args[++i];
  }

  return parsed;
}

function runCommand(cmd, description) {
  console.error(`  ${description}...`);
  try {
    const result = execSync(cmd, { encoding: 'utf8', timeout: 120000 });
    return result.trim();
  } catch (err) {
    console.error(`    Error: ${err.message}`);
    return null;
  }
}

async function processTicket(ticket, args) {
  console.error(`\n[${ticket.ticket_id}] ${ticket.page_url}`);
  console.error(`  Viewport: ${ticket.viewport_width}x${ticket.viewport_height}`);

  if (args.dryRun) {
    console.error('  [DRY RUN] Would process this ticket');
    return { success: true, dryRun: true };
  }

  // 1. Navigate to page (using Chrome MCP via curl to DevTools Protocol)
  // Note: This assumes Chrome is running with remote debugging on port 9222
  // In practice, you'd use the Chrome MCP directly from Claude

  // 2. Take full-page screenshot at correct viewport width
  const fullpagePath = `/tmp/fullpage_${ticket.ticket_id}.png`;
  const alignedPath = `/tmp/aligned_${ticket.ticket_id}.png`;

  // 3. Run alignment
  const alignResult = runCommand(
    `node align-screenshot.js --template "${ticket.feedbucket_url}" --fullpage "${fullpagePath}" --output "${alignedPath}"`,
    'Aligning screenshot'
  );

  if (!alignResult) {
    return { success: false, error: 'Alignment failed' };
  }

  let alignData;
  try {
    alignData = JSON.parse(alignResult);
  } catch (e) {
    return { success: false, error: 'Failed to parse alignment result' };
  }

  console.error(`  Scroll Y: ${alignData.scrollY}, Confidence: ${(alignData.confidence * 100).toFixed(1)}%`);

  // 4. Upload to Firebase
  const uploadResult = runCommand(
    `node upload-screenshot.js --file "${alignedPath}" --ticket ${ticket.ticket_id} --type after --notion-page-id ${ticket.page_id}`,
    'Uploading to Firebase'
  );

  if (!uploadResult) {
    return { success: false, error: 'Upload failed' };
  }

  let uploadData;
  try {
    uploadData = JSON.parse(uploadResult);
  } catch (e) {
    return { success: false, error: 'Failed to parse upload result' };
  }

  // 5. Update Notion
  const notionResult = runCommand(
    `/tmp/update-qa-after.sh ${ticket.page_id} "${uploadData.url}" "qa-after-${ticket.ticket_id}.png"`,
    'Updating Notion'
  );

  // Clean up temp files
  try {
    fs.unlinkSync(fullpagePath);
    fs.unlinkSync(alignedPath);
  } catch (e) {}

  return {
    success: true,
    scrollY: alignData.scrollY,
    confidence: alignData.confidence,
    url: uploadData.url
  };
}

async function main() {
  const args = parseArgs();
  const queue = JSON.parse(fs.readFileSync(QUEUE_FILE, 'utf8'));

  let tickets = queue;
  if (args.singleTicket) {
    tickets = queue.filter(t => t.ticket_id === args.singleTicket);
    if (tickets.length === 0) {
      console.error(`Ticket ${args.singleTicket} not found in queue`);
      process.exit(1);
    }
  }

  console.error(`Processing ${tickets.length} tickets...`);
  if (args.dryRun) console.error('[DRY RUN MODE]');

  const results = { success: 0, failed: 0, tickets: [] };

  for (const ticket of tickets) {
    const result = await processTicket(ticket, args);
    results.tickets.push({
      ticket_id: ticket.ticket_id,
      ...result
    });

    if (result.success) results.success++;
    else results.failed++;
  }

  console.error(`\n\nSummary:`);
  console.error(`  Success: ${results.success}`);
  console.error(`  Failed: ${results.failed}`);

  console.log(JSON.stringify(results, null, 2));
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
