#!/bin/bash

# Test: Workflow Integration Failed State
# Purpose: Demonstrate that the categorization system has no integration
#          with the existing workflow (fetch-notion-ticket.sh, Chrome MCP, GitHub)
#
# Expected Result: FAIL - No integration points exist
#
# The categorization is useless if we can't:
#   1. Fetch tickets by batch/category
#   2. Process multiple tickets efficiently
#   3. Trigger Chrome MCP for QA verification
#   4. Track staging preview URLs
#   5. Batch complete tickets after QA approval
#
# Current workflow is single-ticket-at-a-time, losing all batch efficiency gains.

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"

# Workflow script locations
FETCH_SCRIPT="$HOME/Dropbox/scripts/notion/fetch-notion-ticket.sh"
MANAGE_SCRIPT="$HOME/Dropbox/scripts/notion/manage-notion-ticket.sh"

echo "========================================"
echo "TEST: Workflow Integration"
echo "========================================"
echo ""
echo "This test verifies that the categorization system"
echo "integrates with the existing ticket workflow."
echo ""

mkdir -p "$RESULTS_DIR"

FAILURES=0
PASSES=0

# ============================================
# CHECK 1: Batch Fetch Capability
# ============================================
echo -e "${BLUE}Check 1: Batch Fetch Capability${NC}"
echo "Does fetch-notion-ticket.sh support fetching multiple tickets at once?"
echo ""

# Check if fetch script exists
if [ -f "$FETCH_SCRIPT" ]; then
    echo "  ✓ fetch-notion-ticket.sh exists"

    # Check for batch support (--batch, --category, --from-file flags)
    if grep -q "\-\-batch\|\-\-category\|\-\-from-file\|\-\-from-json" "$FETCH_SCRIPT" 2>/dev/null; then
        echo -e "  ${GREEN}✓ PASS: Batch fetch capability found${NC}"
        PASSES=$((PASSES + 1))
    else
        echo -e "  ${RED}✗ FAIL: No batch fetch capability${NC}"
        echo "    Script only supports: fetch-notion-ticket.sh TICK-###"
        echo "    Missing: --batch, --category, or --from-file flags"
        FAILURES=$((FAILURES + 1))
    fi
else
    echo -e "  ${RED}✗ FAIL: fetch-notion-ticket.sh not found${NC}"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 2: Categorization Integration
# ============================================
echo -e "${BLUE}Check 2: Categorization Integration${NC}"
echo "Can we fetch tickets by category from categorized_tickets.json?"
echo ""

# Check if there's a script that reads from categorized output
BATCH_FETCH_SCRIPT="$HOME/Dropbox/scripts/notion/fetch-batch.sh"
CATEGORY_FETCH_SCRIPT="$HOME/Dropbox/scripts/notion/fetch-by-category.sh"

if [ -f "$BATCH_FETCH_SCRIPT" ] || [ -f "$CATEGORY_FETCH_SCRIPT" ]; then
    echo -e "  ${GREEN}✓ PASS: Category-aware fetch script exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No category-aware fetch capability${NC}"
    echo "    Missing: fetch-batch.sh or fetch-by-category.sh"
    echo "    Cannot process tickets from categorized_tickets.json"
    FAILURES=$((FAILURES + 1))
fi

# Check if manage script can accept batch input
if grep -q "\-\-batch\|\-\-from-file\|\-\-tickets" "$MANAGE_SCRIPT" 2>/dev/null; then
    echo -e "  ${GREEN}✓ PASS: Batch update capability found${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: manage-notion-ticket.sh lacks batch support${NC}"
    echo "    Can only update one ticket at a time"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 3: Chrome MCP QA Integration
# ============================================
echo -e "${BLUE}Check 3: Chrome MCP QA Integration${NC}"
echo "Is there automated QA verification with Chrome MCP?"
echo ""

# Check for QA automation scripts
QA_SCRIPT="$SCRIPT_DIR/qa_verify.sh"
QA_WORKFLOW="$SCRIPT_DIR/qa_workflow.sh"
CHROME_QA_SCRIPT="$HOME/Dropbox/scripts/qa/chrome-qa.sh"

if [ -f "$QA_SCRIPT" ] || [ -f "$QA_WORKFLOW" ] || [ -f "$CHROME_QA_SCRIPT" ]; then
    echo -e "  ${GREEN}✓ PASS: QA automation script exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No Chrome MCP QA automation${NC}"
    echo "    Missing: qa_verify.sh or qa_workflow.sh"
    echo "    No way to automatically verify changes in browser"
    FAILURES=$((FAILURES + 1))
fi

# Check if there's a way to capture screenshots for QA
SCREENSHOT_DIR="$SCRIPT_DIR/results/screenshots"
if [ -d "$SCREENSHOT_DIR" ] && [ "$(ls -A $SCREENSHOT_DIR 2>/dev/null)" ]; then
    echo -e "  ${GREEN}✓ PASS: Screenshot capture exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No QA screenshot workflow${NC}"
    echo "    Missing: results/screenshots/ directory or automation"
    echo "    Cannot document visual changes for QA approval"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 4: Staging Preview Integration
# ============================================
echo -e "${BLUE}Check 4: Staging Preview Integration${NC}"
echo "Is staging preview URL captured and linked to tickets?"
echo ""

# Check if manage script captures theme preview URL
if grep -q "theme-id\|preview\|staging" "$MANAGE_SCRIPT" 2>/dev/null; then
    echo "  ✓ Theme ID field exists in manage script"
else
    echo "  ! Theme ID field not prominently used"
fi

# Check for staging URL generation script
STAGING_SCRIPT="$HOME/Dropbox/scripts/shopify/get-staging-url.sh"
PREVIEW_SCRIPT="$HOME/Dropbox/scripts/shopify/preview-url.sh"

if [ -f "$STAGING_SCRIPT" ] || [ -f "$PREVIEW_SCRIPT" ]; then
    echo -e "  ${GREEN}✓ PASS: Staging URL script exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No staging URL generation${NC}"
    echo "    Missing: get-staging-url.sh or preview-url.sh"
    echo "    Cannot auto-generate preview URLs for QA"
    FAILURES=$((FAILURES + 1))
fi

# Check if there's a way to batch-update tickets with staging URLs
if [ -f "$RESULTS_DIR/batches.json" ]; then
    # Check if batches have staging URLs
    HAS_STAGING=$(cat "$RESULTS_DIR/batches.json" 2>/dev/null | jq 'any(.[]; .staging_url != null)' 2>/dev/null || echo "false")
    if [ "$HAS_STAGING" = "true" ]; then
        echo -e "  ${GREEN}✓ PASS: Batches have staging URLs${NC}"
        PASSES=$((PASSES + 1))
    else
        echo -e "  ${RED}✗ FAIL: Batches lack staging URLs${NC}"
        echo "    batches.json exists but no staging_url field"
        FAILURES=$((FAILURES + 1))
    fi
else
    echo -e "  ${RED}✗ FAIL: No batches.json with staging integration${NC}"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 5: Batch Completion Workflow
# ============================================
echo -e "${BLUE}Check 5: Batch Completion Workflow${NC}"
echo "Can we mark an entire batch as complete after QA?"
echo ""

# Check for batch completion script
BATCH_COMPLETE="$HOME/Dropbox/scripts/notion/complete-batch.sh"
BATCH_UPDATE="$HOME/Dropbox/scripts/notion/batch-update.sh"

if [ -f "$BATCH_COMPLETE" ] || [ -f "$BATCH_UPDATE" ]; then
    echo -e "  ${GREEN}✓ PASS: Batch completion script exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No batch completion capability${NC}"
    echo "    Missing: complete-batch.sh or batch-update.sh"
    echo "    Must complete tickets one-by-one manually"
    FAILURES=$((FAILURES + 1))
fi

# Check if completion includes PR URL auto-detection
if grep -q "git.*remote\|gh.*pr\|pull.*request" "$MANAGE_SCRIPT" 2>/dev/null; then
    echo "  ✓ PR URL handling exists"
else
    echo -e "  ${YELLOW}! No auto-detection of current PR${NC}"
fi

echo ""

# ============================================
# CHECK 6: QA Approval Tracking
# ============================================
echo -e "${BLUE}Check 6: QA Approval Tracking${NC}"
echo "Is there a way to record QA approval for batches?"
echo ""

# Check for QA tracking in Notion schema
QA_FIELD_EXISTS=false

# Check if tickets have QA-related fields by looking at a sample ticket
if [ -f "$RESULTS_DIR/../fixtures/raw_tickets.json" ]; then
    if cat "$RESULTS_DIR/../fixtures/raw_tickets.json" 2>/dev/null | jq -e '.results[0].properties | has("QA Status") or has("QA Approved") or has("Verified")' > /dev/null 2>&1; then
        QA_FIELD_EXISTS=true
    fi
fi

if [ "$QA_FIELD_EXISTS" = true ]; then
    echo -e "  ${GREEN}✓ PASS: QA tracking field exists in Notion${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No QA approval tracking${NC}"
    echo "    Notion tickets lack QA Status/Approved field"
    echo "    Cannot track which changes have been verified"
    FAILURES=$((FAILURES + 1))
fi

# Check for QA report generation
QA_REPORT="$RESULTS_DIR/qa_report.json"
if [ -f "$QA_REPORT" ]; then
    echo -e "  ${GREEN}✓ PASS: QA report generation exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No QA report generation${NC}"
    echo "    Missing: results/qa_report.json"
    echo "    Cannot generate QA summary for batch approval"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 7: End-to-End Workflow Script
# ============================================
echo -e "${BLUE}Check 7: End-to-End Workflow Script${NC}"
echo "Is there a unified workflow that ties everything together?"
echo ""

# Check for workflow orchestration
WORKFLOW_SCRIPT="$SCRIPT_DIR/batch_workflow.sh"
PROCESS_BATCH="$SCRIPT_DIR/process_batch.sh"
RUN_CYCLE="$HOME/Dropbox/scripts/notion/run-cycle.sh"

if [ -f "$WORKFLOW_SCRIPT" ] || [ -f "$PROCESS_BATCH" ] || [ -f "$RUN_CYCLE" ]; then
    echo -e "  ${GREEN}✓ PASS: Workflow orchestration exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No end-to-end workflow${NC}"
    echo "    Missing unified script that:"
    echo "      1. Selects batch from categorized tickets"
    echo "      2. Fetches ticket details"
    echo "      3. Creates staging branch"
    echo "      4. Triggers QA verification"
    echo "      5. Captures approval"
    echo "      6. Completes tickets in batch"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# RESULTS
# ============================================
echo "========================================"
echo "RESULTS: Workflow Integration Assessment"
echo "========================================"
echo ""

echo "Checks passed: $PASSES"
echo "Checks failed: $FAILURES"
echo ""

if [ "$FAILURES" -gt 0 ]; then
    echo -e "${RED}TEST FAILED: $FAILURES integration point(s) missing${NC}"
    echo ""
    echo "The categorization system is NOT integrated with the workflow."
    echo ""
    echo "Current state:"
    echo "  - Categorization: ✓ Works (93% accuracy)"
    echo "  - Batch processing plan: ✓ Generated"
    echo "  - Workflow integration: ✗ MISSING"
    echo ""
    echo "Without integration, developers must:"
    echo "  1. Manually look up tickets from batches.json"
    echo "  2. Run fetch-notion-ticket.sh for EACH ticket"
    echo "  3. Manually track which tickets are done"
    echo "  4. Manually verify changes in browser"
    echo "  5. Manually complete each ticket"
    echo ""
    echo "This defeats the purpose of batch categorization!"
    echo ""
    echo "Required integration points:"
    echo "  □ fetch-batch.sh - Fetch tickets by category/batch"
    echo "  □ qa_workflow.sh - Chrome MCP verification automation"
    echo "  □ get-staging-url.sh - Generate preview URLs"
    echo "  □ complete-batch.sh - Batch ticket completion"
    echo "  □ batch_workflow.sh - End-to-end orchestration"
    echo ""
    exit 1
else
    echo -e "${GREEN}TEST PASSED: Workflow integration complete${NC}"
    exit 0
fi
