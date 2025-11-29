# Infrastructure Upgrade: Batch Processing System

**Date:** November 28, 2025
**Client:** hs-figma
**Tickets:** 75 backlog tickets

---

## Overview

This document describes the batch processing infrastructure developed to efficiently process 75+ Notion tickets. The system uses test-driven development with pass/fail/error state tests to ensure reliability.

---

## Notion Database Changes

### New Fields Added

| Field Name | Type | Purpose |
|------------|------|---------|
| **QA Before** | Files & media | Stores Feedbucket screenshot (issue before fix) |
| **QA After** | Files & media | Stores Chrome MCP screenshot (result after fix) |

**Database ID:** `1abc197b3ae7808fa454dd0c0e96ca6f`

---

## Test Framework

All tests located in: `~/Dropbox/wwwroot/store.figma.com/shopify-the-figma-store/horizon/tests/`

### Test Summary

| Test | Type | Purpose | Status |
|------|------|---------|--------|
| `test_ticket_categorization.sh` | Fail State | Naive categorization doesn't work | FAIL (designed) |
| `test_ticket_categorization_pass.sh` | Pass State | Smart categorization achieves 93% | PASS |
| `test_workflow_integration.sh` | Fail State | No workflow integration | FAIL (designed) |
| `test_workflow_integration_pass.sh` | Pass State | All integration scripts exist | PASS |
| `test_qa_process_recording.sh` | Fail State | No QA tracking + no single-ticket QA images | FAIL (designed) |
| `test_qa_process_recording_pass.sh` | Pass State | QA Before/After fields in Notion | PASS |
| `test_qa_error_states.sh` | Error Detection | Identifies missing data for QA workflow | WARNING |

### Running Tests

```bash
cd ~/Dropbox/wwwroot/store.figma.com/shopify-the-figma-store/horizon/tests

# Run all pass tests
./test_ticket_categorization_pass.sh
./test_workflow_integration_pass.sh
./test_qa_process_recording_pass.sh

# Run error detection
./test_qa_error_states.sh
```

---

## Categorization System

### Categories (12 total)

| Category | Description | Files Affected |
|----------|-------------|----------------|
| pdp | Product Detail Page | `sections/main-product.liquid`, `snippets/product-*` |
| cart | Cart & Checkout | `sections/cart-*.liquid`, `snippets/cart-*` |
| header-nav | Header & Navigation | `sections/header.liquid`, `snippets/header-*` |
| footer | Footer | `sections/footer.liquid` |
| collection | Collection Pages | `sections/collection-*.liquid` |
| homepage | Homepage | `sections/homepage-*.liquid`, `templates/index.json` |
| mobile | Mobile/Responsive | Cross-cutting mobile issues |
| spacing-layout | Spacing & Layout | CSS spacing, margins, padding |
| animation | Animations | Transitions, keyframes |
| icons-images | Icons & Images | SVGs, image handling |
| pages | Static Pages | `templates/page.*.json` |
| uncategorized | Needs Review | Could not auto-categorize |

### Priority System

| Priority | Description | Ticket Count |
|----------|-------------|--------------|
| P1-QuickWins | Simple fixes, isolated changes | 47 |
| P2-Structural | Layout/structure changes | 22 |
| P3-CrossCutting | Affects multiple areas | 1 |
| P4-Responsive | Viewport-specific fixes | 4 |
| P5-Complex | Requires investigation | 1 |

### Batch Keys

Batches are named: `{category}-{priority}`

Example batches:
- `pdp-P1-QuickWins` (21 tickets)
- `cart-P1-QuickWins` (7 tickets)
- `header-nav-P1-QuickWins` (6 tickets)
- `collection-P1-QuickWins` (7 tickets)

---

## Scripts Created

### Integration Scripts

| Script | Location | Purpose |
|--------|----------|---------|
| `fetch-batch.sh` | `~/Dropbox/scripts/notion/` | Fetch tickets by category/batch |
| `complete-batch.sh` | `~/Dropbox/scripts/notion/` | Batch ticket completion |
| `record-qa.sh` | `~/Dropbox/scripts/notion/` | Record QA in Notion |
| `get-staging-url.sh` | `~/Dropbox/scripts/shopify/` | Generate preview URLs |

### Test Scripts

| Script | Location | Purpose |
|--------|----------|---------|
| `categorize_tickets.sh` | `tests/` | Categorization engine |
| `categorization_rules.json` | `tests/` | Category definitions |
| `batch_workflow.sh` | `tests/` | End-to-end orchestration |

### One-Time Batch Processor

| Script | Location | Purpose |
|--------|----------|---------|
| `batch_process_hs_figma.sh` | `tests/` | Main batch processing script |

---

## Batch Processing Workflow

### Using `batch_process_hs_figma.sh`

```bash
cd ~/Dropbox/wwwroot/store.figma.com/shopify-the-figma-store/horizon/tests

# Step 1: Pre-flight check
./batch_process_hs_figma.sh --check

# Step 2: List available batches
./batch_process_hs_figma.sh --list

# Step 3: Process a batch (fetches tickets, extracts Feedbucket URLs)
./batch_process_hs_figma.sh --process pdp-P1-QuickWins

# Step 4: Implement fixes for tickets in batch...

# Step 5: Run QA workflow (stores QA Before images in Notion)
./batch_process_hs_figma.sh --qa pdp-P1-QuickWins

# Step 6: Capture QA After screenshots via Chrome MCP

# Step 7: Complete batch (marks tickets as Complete)
./batch_process_hs_figma.sh --complete pdp-P1-QuickWins

# Check progress
./batch_process_hs_figma.sh --status
```

### Command Reference

| Command | Description |
|---------|-------------|
| `--check, -c` | Pre-flight check (Notion API, QA fields, scripts) |
| `--categorize, -cat` | Run ticket categorization |
| `--list, -l` | List available batches |
| `--process, -p <batch>` | Process a batch (fetch tickets) |
| `--qa, -q <batch>` | Run QA workflow for batch |
| `--complete, -comp <batch> [pr-url]` | Complete batch with optional PR URL |
| `--status, -s` | Show progress |

---

## QA Workflow

### Simple Before/After Comparison

1. **QA Before**: Feedbucket screenshot (captured when issue reported)
   - Automatically extracted from ticket content
   - Stored in "QA Before" Notion field

2. **QA After**: Chrome MCP screenshot (captured after fix)
   - Capture via: `mcp__chrome-devtools__take_screenshot`
   - Store in "QA After" Notion field

3. **Comparison**: Both images visible on ticket for easy comparison

### Media Type Support

| Type | Support | Notes |
|------|---------|-------|
| JPG | ✅ Full | Primary format (75 tickets) |
| PNG | ✅ Full | Supported |
| Video | ⚠️ Partial | Flagged for separate batch |
| GIF | ✅ Full | Supported |

---

## Error Handling

### Error States Detected

| Error | Count | Impact | Resolution |
|-------|-------|--------|------------|
| Missing Feedbucket media | 0 | Cannot populate QA Before | Manual screenshot |
| Missing Page URL | 75 | Cannot auto-capture QA After | Add URL or manual capture |
| Missing Theme ID | 75 | Cannot generate staging URL | Use client default |
| Video content | 0 | Needs special handling | Separate batch |

### Output Files

Error detection creates these files in `tests/results/`:

- `tickets_missing_feedbucket.txt`
- `tickets_missing_page_url.txt`
- `tickets_with_png.txt`
- `tickets_with_jpg.txt`
- `tickets_with_video.txt`

---

## Directory Structure

```
tests/
├── batch_process_hs_figma.sh    # Main batch processor
├── batch_workflow.sh            # Workflow orchestration
├── categorize_tickets.sh        # Categorization engine
├── categorization_rules.json    # Category definitions
├── infrastructure-upgrade.md    # This file
│
├── test_ticket_categorization.sh       # Fail: naive categorization
├── test_ticket_categorization_pass.sh  # Pass: smart categorization
├── test_workflow_integration.sh        # Fail: no integration
├── test_workflow_integration_pass.sh   # Pass: scripts exist
├── test_qa_process_recording.sh        # Fail: no QA tracking
├── test_qa_process_recording_pass.sh   # Pass: QA fields exist
├── test_qa_error_states.sh             # Error detection
│
├── NOTION_QA_FIELDS_SPEC.md     # QA fields specification
│
└── results/
    ├── categorized_tickets.json      # Categorization output
    ├── batch_state.json              # Processing state
    ├── batch_process.log             # Processing log
    ├── screenshots/                  # QA screenshots
    ├── qa-logs/                      # QA logs
    ├── completion-logs/              # Completion logs
    └── batches/                      # Per-batch data
        └── {batch-key}/
            ├── tickets.json
            ├── TICK-####.txt
            └── TICK-####_qa_before.url
```

---

## Recommended Processing Order

Based on categorization results, process batches in this order:

### Phase 1: Quick Wins (47 tickets)
1. `pdp-P1-QuickWins` - 21 tickets
2. `cart-P1-QuickWins` - 7 tickets
3. `collection-P1-QuickWins` - 7 tickets
4. `header-nav-P1-QuickWins` - 6 tickets
5. `homepage-P1-QuickWins` - 3 tickets
6. `footer-P1-QuickWins` - 1 ticket
7. `icons-images-P1-QuickWins` - 1 ticket
8. `pages-P1-QuickWins` - 1 ticket

### Phase 2: Structural (22 tickets)
9. `spacing-layout-P2-Structural` - 8 tickets
10. `collection-P2-Structural` - 6 tickets
11. `header-nav-P2-Structural` - 3 tickets
12. `pdp-P2-Structural` - 3 tickets
13. `animation-P2-Structural` - 1 ticket
14. `homepage-P2-Structural` - 1 ticket

### Phase 3: Cross-Cutting (1 ticket)
15. `mobile-P3-CrossCutting` - 1 ticket

### Phase 4: Responsive (4 tickets)
16. `uncategorized-P4-Responsive` - 4 tickets

### Phase 5: Complex (1 ticket)
17. `uncategorized-P5-Complex` - 1 ticket

---

## Integration with Existing Scripts

This system integrates with existing Notion scripts:

```bash
# Fetch single ticket (existing)
~/Dropbox/scripts/notion/fetch-notion-ticket.sh TICK-###

# Manage ticket (existing)
~/Dropbox/scripts/notion/manage-notion-ticket.sh TICK-### --status Complete

# New: Batch operations
~/Dropbox/scripts/notion/fetch-batch.sh --batch pdp-P1-QuickWins
~/Dropbox/scripts/notion/complete-batch.sh --batch pdp-P1-QuickWins --pr-url <url>
```

---

## Future Improvements

1. **Single Ticket QA Integration**: Add `--qa-before` and `--qa-after` flags to `manage-notion-ticket.sh`
2. **Page URL Extraction**: Auto-extract Page URL from Feedbucket image URL
3. **Chrome MCP Automation**: Script to auto-capture QA After screenshots
4. **Video Handling**: First-frame extraction for video tickets

---

## Changelog

- **2025-11-28**: Initial infrastructure created
  - Added QA Before/After fields to Notion
  - Created test framework (7 tests)
  - Built categorization system (93% accuracy)
  - Created batch processing script
  - Documented 75 tickets across 17 batches
