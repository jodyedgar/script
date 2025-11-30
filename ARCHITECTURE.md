# Architecture - Current Active Files

**Last Updated:** 2025-11-30 12:00:00

> ⚠️ **IMPORTANT for AI Assistants and Developers**
>
> **Only reference files listed in this document.**
>
> Files in `/deprecated/` are obsolete and should be **completely ignored**.
> They exist only for historical reference and will be deleted after 30 days.

---

## Project Structure

```
Directory tree (install 'tree' for better visualization):
/Users/jodyedgar/Dropbox/Scripts
/Users/jodyedgar/Dropbox/Scripts/.git
/Users/jodyedgar/Dropbox/Scripts/.necro
/Users/jodyedgar/Dropbox/Scripts/deprecated
/Users/jodyedgar/Dropbox/Scripts/echo-sonos-master
/Users/jodyedgar/Dropbox/Scripts/echo-sonos-master/echo
/Users/jodyedgar/Dropbox/Scripts/echo-sonos-master/echo/custom_slots
/Users/jodyedgar/Dropbox/Scripts/echo-sonos-master/lambda
/Users/jodyedgar/Dropbox/Scripts/echo-sonos-master/lambda/src
/Users/jodyedgar/Dropbox/Scripts/echo-sonos-master/node-sonos-http-api
/Users/jodyedgar/Dropbox/Scripts/echo-sonos-master/server
/Users/jodyedgar/Dropbox/Scripts/necro
/Users/jodyedgar/Dropbox/Scripts/necro/bin
/Users/jodyedgar/Dropbox/Scripts/necro/docs
/Users/jodyedgar/Dropbox/Scripts/necro/lib
/Users/jodyedgar/Dropbox/Scripts/necro/templates
/Users/jodyedgar/Dropbox/Scripts/necro/tests
/Users/jodyedgar/Dropbox/Scripts/node-sonos-http-api-master
/Users/jodyedgar/Dropbox/Scripts/node-sonos-http-api-master/lib
/Users/jodyedgar/Dropbox/Scripts/node-sonos-http-api-master/lib/actions
/Users/jodyedgar/Dropbox/Scripts/node-sonos-http-api-master/node_modules
/Users/jodyedgar/Dropbox/Scripts/node-sonos-http-api-master/static
/Users/jodyedgar/Dropbox/Scripts/node-sonos-http-api-master/static/docs
/Users/jodyedgar/Dropbox/Scripts/node-sonos-http-api-master/static/tts
/Users/jodyedgar/Dropbox/Scripts/notion
/Users/jodyedgar/Dropbox/Scripts/notion/batch
/Users/jodyedgar/Dropbox/Scripts/notion/qa
/Users/jodyedgar/Dropbox/Scripts/shopify
```

## Active Source Directories

No standard source directories found.

## Scripts

### Shell Scripts (.sh)

- `echo-sonos-master/server/daemon.sh` ⚡
- `echo-sonos-master/server/pi-daemon.sh` ⚡
- `echo-sonos-master/server/pi-restart.sh` ⚡
- `echo-sonos-master/server/restart.sh` ⚡
- `necro/lib/common.sh` ⚡
- `necro/necro-generator.sh`
- `node-sonos-http-api-master/dockerstart.sh` ⚡
- `notion/fetch-and-navigate.sh` ⚡
- `notion/fetch-notion-ticket.sh` ⚡
- `notion/manage-notion-ticket.sh` ⚡
- `notion/record-qa.sh` ⚡ - QA verification with Firebase screenshot storage
- `notion/ticket-time-estimator.sh` ⚡
- `notion/update-ticket-credits.sh` ⚡
- `notion/batch/batch-workflow.sh` ⚡ - Batch processing for multiple tickets
- `notion/batch/test_workflow_integration.sh` ⚡
- `notion/qa/compare-qa.sh` ⚡ - Compare QA Before/After screenshots
- `notion/qa/extract-feedbucket-image.sh` ⚡ - Extract Feedbucket images from tickets
- `notion/qa/setup-firebase.sh` ⚡ - Firebase Storage setup helper
- `shopify/add-clinerules-to-project.sh` ⚡
- `shopify/setup-shopify-store.sh` ⚡

### Node.js Scripts (.js)

- `notion/qa/upload-screenshot.js` - Firebase Storage upload handler
- `notion/qa/capture-screenshot.js` - Chrome DevTools screenshot capture

### PowerShell Scripts (.ps1)

No PowerShell scripts found.

## Documentation

- `echo-sonos-master/README.md` (10.7 KB)
  - echo-sonos
- `necro/NECRO_CLAUDE_CODE_INSTRUCTIONS.md` (8.5 KB)
  - NECRO SETUP - Instructions for Claude Code
- `necro/NECRO_IMPLEMENTATION_GUIDE.md` (12.1 KB)
  - Necro System - Implementation Guide for Claude Code
- `necro/README.md` (13.0 KB)
  - Necro - Project Archaeology & Cleanup System
- `node-sonos-http-api-master/LICENSE.md` (1.1 KB)
  - The MIT License (MIT)
- `node-sonos-http-api-master/README.md` (11.4 KB)
  - [![PayPal donate button](https://img.shields.io/badge/paypal-donate-yellow.svg)]

## Package.json Scripts

### notion/qa/package.json

Dependencies for QA screenshot system:
- `firebase-admin` - Firebase Storage and Firestore access
- `ws` - WebSocket for Chrome DevTools Protocol

## External Services

### Firebase (bucky-app-355a3)

The QA screenshot system uses Firebase for storage:
- **Firebase Storage**: `bucky-app-355a3.firebasestorage.app` - Stores QA Before/After screenshots
- **Firestore**: `qa_screenshots` collection - Metadata for uploaded screenshots
- **Service Account**: `notion/qa/service-account.json` (git-ignored, sensitive)

## Git Information

**Current Branch:** `batch`

**Recent Commits:**
```
2592270 Add QA screenshot system with Firebase Storage integration
821a855 Expand batch workflow tests with resume, progress, and QA field checks
a33ecbb Add batch processing system for Notion ticket management
6bc7753 Fix ANSI color code display in all Necro scripts
```

---

## ⛔ DO NOT USE - Deprecated Files

**All files in `/deprecated/` are obsolete and must not be referenced.**

The deprecated directory contains old code that has been replaced or is no longer used.
These files are kept temporarily (30 days) for historical reference only.

**For replacement information:** Check `deprecated/DEPRECATION_LOG.md`

---

## Using This Document

### For Developers

This document should be consulted:
- Before starting new development work
- When debugging existing features
- During code reviews
- When refactoring code

### For AI Coding Assistants

When working with this project:
1. **Only reference files listed in this document**
2. **Completely ignore `/deprecated/` directory**
3. **Check this document for current implementations**
4. **Ask for clarification if a file isn't listed**

### Keeping Current

Run `necro arch` to regenerate this document with the latest project state.

**Recommended:** Update before major work sessions and after significant changes.

