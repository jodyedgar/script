#!/usr/bin/env node
/**
 * Upload a ticket Attachment (brief, PDF, source file, image, ...) to Firebase Storage.
 *
 * Unlike upload-screenshot.js (which is QA-before/after specific and writes to the
 * qa_screenshots collection), this uploads ANY file type for ticket creation and
 * just returns a public URL. The caller (ticket.sh --create) wires the URL into
 * the ticket document.
 *
 * Usage:
 *   node upload-attachment.js --file <path> --ticket <TICK-### | tmp-id>
 *
 * Output (stdout, JSON):
 *   { success, url, path, name, contentType, isImage, fileSize }
 */

import { initializeApp, cert } from 'firebase-admin/app';
import { getStorage } from 'firebase-admin/storage';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { readFileSync, existsSync } from 'fs';
import { basename, extname } from 'path';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Common content types. Anything not listed falls back to octet-stream, which is
// fine for source files (.liquid, .scss, .ts, .zip, ...) — the browser downloads them.
const CONTENT_TYPES = {
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.gif': 'image/gif', '.webp': 'image/webp', '.svg': 'image/svg+xml',
  '.mp4': 'video/mp4', '.mov': 'video/quicktime', '.webm': 'video/webm',
  '.pdf': 'application/pdf',
  '.txt': 'text/plain', '.md': 'text/markdown', '.csv': 'text/csv',
  '.json': 'application/json', '.html': 'text/html', '.css': 'text/css',
  '.js': 'text/javascript', '.ts': 'text/plain', '.tsx': 'text/plain',
  '.jsx': 'text/plain', '.liquid': 'text/plain', '.scss': 'text/plain',
  '.zip': 'application/zip',
  '.doc': 'application/msword',
  '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
};

const IMAGE_TYPES = new Set(['image/png', 'image/jpeg', 'image/gif', 'image/webp', 'image/svg+xml']);

function parseArgs() {
  const args = process.argv.slice(2);
  const parsed = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--file' || args[i] === '-f') parsed.file = args[++i];
    else if (args[i] === '--ticket' || args[i] === '-t') parsed.ticket = args[++i];
    // When given, also attach the uploaded file to the ticket doc (arrayUnion an
    // attachment object) so the CLI writes the same object shape as the app.
    else if (args[i] === '--doc-path' || args[i] === '-D') parsed.docPath = args[++i];
    else if (args[i] === '--help' || args[i] === '-h') {
      console.log('Usage: node upload-attachment.js --file <path> --ticket <TICK-### | tmp-id> [--doc-path tickets/<id>]');
      process.exit(0);
    }
  }
  return parsed;
}

function initFirebase() {
  const serviceAccountPath = join(__dirname, 'service-account.json');
  if (!existsSync(serviceAccountPath)) {
    console.error(JSON.stringify({ error: 'Service account not found', path: serviceAccountPath }));
    process.exit(1);
  }
  const serviceAccount = JSON.parse(readFileSync(serviceAccountPath, 'utf8'));
  initializeApp({
    credential: cert(serviceAccount),
    storageBucket: 'bucky-app-355a3.firebasestorage.app',
  });
  return getStorage();
}

// Make the storage key safe and keep the original (readable) basename.
function safeName(name) {
  return name.replace(/[^a-zA-Z0-9._-]+/g, '_').replace(/_+/g, '_');
}

async function main() {
  const args = parseArgs();
  if (!args.ticket) {
    console.error(JSON.stringify({ error: 'Missing required argument: --ticket' }));
    process.exit(1);
  }
  if (!args.file) {
    console.error(JSON.stringify({ error: 'Missing required argument: --file' }));
    process.exit(1);
  }
  if (!existsSync(args.file)) {
    console.error(JSON.stringify({ error: `File not found: ${args.file}` }));
    process.exit(1);
  }

  try {
    const storage = initFirebase();
    const buffer = readFileSync(args.file);
    const origName = basename(args.file);
    const ext = extname(origName).toLowerCase();
    const contentType = CONTENT_TYPES[ext] || 'application/octet-stream';
    const isImage = IMAGE_TYPES.has(contentType);

    const timestamp = Date.now();
    const storagePath = `ticket-attachments/${args.ticket}/${timestamp}_${safeName(origName)}`;

    const bucket = storage.bucket();
    const file = bucket.file(storagePath);
    await file.save(buffer, { metadata: { contentType } });
    await file.makePublic();
    const url = `https://storage.googleapis.com/${bucket.name}/${storagePath}`;

    // Optionally attach to the ticket doc directly (object shape, matches the app).
    if (args.docPath) {
      const db = getFirestore();
      const attachment = {
        url, name: origName, contentType, isImage,
        source: 'cli', storagePath,
        // Timestamp.now() — never serverTimestamp inside arrayUnion.
        uploadedAt: Timestamp.now(),
      };
      const update = {
        attachments: FieldValue.arrayUnion(attachment),
        updatedAt: Timestamp.now(),
      };
      if (isImage) update.screenshots = FieldValue.arrayUnion(url);
      await db.doc(args.docPath).update(update);
    }

    console.log(JSON.stringify({
      success: true,
      url,
      path: storagePath,
      name: origName,
      contentType,
      isImage,
      fileSize: buffer.length,
    }));
  } catch (error) {
    console.error(JSON.stringify({ error: error.message, stack: error.stack }));
    process.exit(1);
  }
}

main();
