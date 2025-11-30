#!/usr/bin/env node
/**
 * Upload Screenshot to Firebase Storage
 *
 * Usage:
 *   node upload-screenshot.js --file <path> --ticket <TICK-###> --type <before|after>
 *
 * Returns JSON with:
 *   - url: Public URL for the uploaded image
 *   - path: Storage path
 *   - metadata: Firestore document ID
 */

import { initializeApp, cert } from 'firebase-admin/app';
import { getStorage } from 'firebase-admin/storage';
import { getFirestore } from 'firebase-admin/firestore';
import { readFileSync, existsSync } from 'fs';
import { basename, extname } from 'path';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Parse command line arguments
function parseArgs() {
  const args = process.argv.slice(2);
  const parsed = {};

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--file' || args[i] === '-f') {
      parsed.file = args[++i];
    } else if (args[i] === '--ticket' || args[i] === '-t') {
      parsed.ticket = args[++i];
    } else if (args[i] === '--type') {
      parsed.type = args[++i];
    } else if (args[i] === '--url') {
      parsed.sourceUrl = args[++i];
    } else if (args[i] === '--notion-page-id') {
      parsed.notionPageId = args[++i];
    } else if (args[i] === '--help' || args[i] === '-h') {
      console.log(`
Upload Screenshot to Firebase Storage

Usage:
  node upload-screenshot.js --file <path> --ticket <TICK-###> --type <before|after>
  node upload-screenshot.js --url <url> --ticket <TICK-###> --type <before|after>

Options:
  --file, -f         Local file path to upload
  --url              URL to download and upload (for Feedbucket images)
  --ticket, -t       Ticket ID (e.g., TICK-123)
  --type             Screenshot type: 'before' or 'after'
  --notion-page-id   Optional: Notion page ID for metadata linking
  --help, -h         Show this help message

Examples:
  node upload-screenshot.js --file ./screenshot.png --ticket TICK-123 --type after
  node upload-screenshot.js --url "https://feedbucket..." --ticket TICK-123 --type before
`);
      process.exit(0);
    }
  }

  return parsed;
}

// Initialize Firebase
function initFirebase() {
  const serviceAccountPath = join(__dirname, 'service-account.json');

  if (!existsSync(serviceAccountPath)) {
    console.error(JSON.stringify({
      error: 'Service account not found',
      message: `Please download service account key from Firebase Console and save to: ${serviceAccountPath}`,
      instructions: [
        '1. Go to Firebase Console > Project Settings > Service Accounts',
        '2. Click "Generate new private key"',
        '3. Save the JSON file as: notion/qa/service-account.json'
      ]
    }));
    process.exit(1);
  }

  const serviceAccount = JSON.parse(readFileSync(serviceAccountPath, 'utf8'));

  initializeApp({
    credential: cert(serviceAccount),
    storageBucket: 'bucky-app-355a3.firebasestorage.app'
  });

  return {
    storage: getStorage(),
    firestore: getFirestore()
  };
}

// Download file from URL
async function downloadFromUrl(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to download: ${response.status} ${response.statusText}`);
  }

  const buffer = Buffer.from(await response.arrayBuffer());
  const contentType = response.headers.get('content-type') || 'image/png';

  // Determine extension from content type
  let ext = '.png';
  if (contentType.includes('jpeg') || contentType.includes('jpg')) ext = '.jpg';
  else if (contentType.includes('gif')) ext = '.gif';
  else if (contentType.includes('webp')) ext = '.webp';
  else if (contentType.includes('mp4')) ext = '.mp4';

  return { buffer, contentType, ext };
}

// Upload to Firebase Storage
async function uploadToStorage(storage, buffer, storagePath, contentType) {
  const bucket = storage.bucket();
  const file = bucket.file(storagePath);

  await file.save(buffer, {
    metadata: {
      contentType: contentType
    }
  });

  // Make the file publicly accessible
  await file.makePublic();

  // Get public URL
  const publicUrl = `https://storage.googleapis.com/${bucket.name}/${storagePath}`;

  return publicUrl;
}

// Save metadata to Firestore
async function saveMetadata(firestore, metadata) {
  const collection = firestore.collection('qa_screenshots');
  const docRef = await collection.add({
    ...metadata,
    createdAt: new Date().toISOString()
  });

  return docRef.id;
}

// Main function
async function main() {
  const args = parseArgs();

  // Validate arguments
  if (!args.ticket) {
    console.error(JSON.stringify({ error: 'Missing required argument: --ticket' }));
    process.exit(1);
  }

  if (!args.type || !['before', 'after'].includes(args.type)) {
    console.error(JSON.stringify({ error: 'Invalid --type. Must be "before" or "after"' }));
    process.exit(1);
  }

  if (!args.file && !args.sourceUrl) {
    console.error(JSON.stringify({ error: 'Must provide either --file or --url' }));
    process.exit(1);
  }

  try {
    const { storage, firestore } = initFirebase();

    let buffer, contentType, ext;

    if (args.sourceUrl) {
      // Download from URL
      const downloaded = await downloadFromUrl(args.sourceUrl);
      buffer = downloaded.buffer;
      contentType = downloaded.contentType;
      ext = downloaded.ext;
    } else {
      // Read from local file
      if (!existsSync(args.file)) {
        console.error(JSON.stringify({ error: `File not found: ${args.file}` }));
        process.exit(1);
      }

      buffer = readFileSync(args.file);
      ext = extname(args.file).toLowerCase() || '.png';

      // Determine content type
      const contentTypes = {
        '.png': 'image/png',
        '.jpg': 'image/jpeg',
        '.jpeg': 'image/jpeg',
        '.gif': 'image/gif',
        '.webp': 'image/webp',
        '.mp4': 'video/mp4'
      };
      contentType = contentTypes[ext] || 'application/octet-stream';
    }

    // Generate storage path
    const timestamp = Date.now();
    const storagePath = `qa-screenshots/${args.ticket}/${args.type}_${timestamp}${ext}`;

    // Upload to storage
    const publicUrl = await uploadToStorage(storage, buffer, storagePath, contentType);

    // Prepare metadata
    const metadata = {
      ticketId: args.ticket,
      type: args.type,
      storagePath: storagePath,
      publicUrl: publicUrl,
      contentType: contentType,
      sourceUrl: args.sourceUrl || null,
      sourceFile: args.file ? basename(args.file) : null,
      notionPageId: args.notionPageId || null,
      fileSize: buffer.length
    };

    // Save metadata to Firestore
    const docId = await saveMetadata(firestore, metadata);

    // Output result as JSON
    console.log(JSON.stringify({
      success: true,
      url: publicUrl,
      path: storagePath,
      metadataId: docId,
      ticket: args.ticket,
      type: args.type
    }));

  } catch (error) {
    console.error(JSON.stringify({
      error: error.message,
      stack: error.stack
    }));
    process.exit(1);
  }
}

main();
