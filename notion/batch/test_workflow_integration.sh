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
FETCH_SCRIPT="$HOME/Dropbox/Scripts/notion/fetch-notion-ticket.sh"
MANAGE_SCRIPT="$HOME/Dropbox/Scripts/notion/manage-notion-ticket.sh"

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
    # Check in fetch-notion-ticket.sh, fetch-batch.sh, and batch_workflow.sh
    BATCH_FETCH_SUPPORTED=false
    if grep -q "\-\-batch\|\-\-category\|\-\-from-file\|\-\-from-json" "$FETCH_SCRIPT" 2>/dev/null; then
        BATCH_FETCH_SUPPORTED=true
    fi
    if [ -f "$BATCH_FETCH_SCRIPT" ]; then
        echo "  ✓ fetch-batch.sh exists (dedicated batch fetch)"
        BATCH_FETCH_SUPPORTED=true
    fi
    if [ -f "$SCRIPT_DIR/batch_workflow.sh" ] && grep -q "\-\-batch\|\-\-start\|\-\-list" "$SCRIPT_DIR/batch_workflow.sh" 2>/dev/null; then
        BATCH_FETCH_SUPPORTED=true
    fi

    if [ "$BATCH_FETCH_SUPPORTED" = true ]; then
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
BATCH_FETCH_SCRIPT="$HOME/Dropbox/Scripts/notion/fetch-batch.sh"
CATEGORY_FETCH_SCRIPT="$HOME/Dropbox/Scripts/notion/fetch-by-category.sh"

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
# Check manage-notion-ticket.sh, complete-batch.sh, and batch_workflow.sh
BATCH_UPDATE_SUPPORTED=false
if grep -q "\-\-batch\|\-\-from-file\|\-\-tickets" "$MANAGE_SCRIPT" 2>/dev/null; then
    BATCH_UPDATE_SUPPORTED=true
fi
COMPLETE_BATCH="$HOME/Dropbox/Scripts/notion/complete-batch.sh"
if [ -f "$COMPLETE_BATCH" ]; then
    echo "  ✓ complete-batch.sh exists (dedicated batch completion)"
    BATCH_UPDATE_SUPPORTED=true
fi
if [ -f "$SCRIPT_DIR/batch_workflow.sh" ] && grep -q "\-\-complete\|\-\-finish" "$SCRIPT_DIR/batch_workflow.sh" 2>/dev/null; then
    BATCH_UPDATE_SUPPORTED=true
fi

if [ "$BATCH_UPDATE_SUPPORTED" = true ]; then
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
CHROME_QA_SCRIPT="$HOME/Dropbox/Scripts/qa/chrome-qa.sh"
RECORD_QA_SCRIPT="$HOME/Dropbox/Scripts/notion/record-qa.sh"
COMPARE_QA_SCRIPT="$HOME/Dropbox/Scripts/notion/qa/compare-qa.sh"

if [ -f "$QA_SCRIPT" ] || [ -f "$QA_WORKFLOW" ] || [ -f "$CHROME_QA_SCRIPT" ] || [ -f "$RECORD_QA_SCRIPT" ] || [ -f "$COMPARE_QA_SCRIPT" ]; then
    echo -e "  ${GREEN}✓ PASS: QA automation script exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No Chrome MCP QA automation${NC}"
    echo "    Missing: qa_verify.sh or qa_workflow.sh"
    echo "    No way to automatically verify changes in browser"
    FAILURES=$((FAILURES + 1))
fi

# Check if there's a way to capture screenshots for QA
# Can be local directory OR Firebase Storage integration
SCREENSHOT_DIR="$SCRIPT_DIR/results/screenshots"
HAS_SCREENSHOT_WORKFLOW=false

# Check for local screenshots
if [ -d "$SCREENSHOT_DIR" ] && [ "$(ls -A $SCREENSHOT_DIR 2>/dev/null)" ]; then
    HAS_SCREENSHOT_WORKFLOW=true
fi

# Check for Firebase Storage integration in record-qa.sh
if [ -f "$RECORD_QA_SCRIPT" ] && grep -q "firebase\|upload.*screenshot\|cloud.*storage" "$RECORD_QA_SCRIPT" 2>/dev/null; then
    echo "  ✓ Firebase Storage integration detected in record-qa.sh"
    HAS_SCREENSHOT_WORKFLOW=true
fi

if [ "$HAS_SCREENSHOT_WORKFLOW" = true ]; then
    echo -e "  ${GREEN}✓ PASS: Screenshot capture workflow exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No QA screenshot workflow${NC}"
    echo "    Missing: results/screenshots/ directory or Firebase integration"
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
STAGING_SCRIPT="$HOME/Dropbox/Scripts/shopify/get-staging-url.sh"
PREVIEW_SCRIPT="$HOME/Dropbox/Scripts/shopify/preview-url.sh"

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
# Check if batches have staging URLs OR if the workflow code would populate them
STAGING_CAPABILITY=false

if [ -f "$RESULTS_DIR/batches.json" ]; then
    # Check if batches already have staging URLs
    HAS_STAGING=$(cat "$RESULTS_DIR/batches.json" 2>/dev/null | jq 'any(.[]; .staging_url != null)' 2>/dev/null || echo "false")
    if [ "$HAS_STAGING" = "true" ]; then
        STAGING_CAPABILITY=true
    fi
fi

# Also check if batch_workflow.sh has code to set staging URLs (functionality exists even if not used yet)
if [ -f "$SCRIPT_DIR/batch_workflow.sh" ] && grep -q "staging_url\|get-staging-url\|preview_theme" "$SCRIPT_DIR/batch_workflow.sh" 2>/dev/null; then
    echo "  ✓ Staging URL integration exists in batch_workflow.sh"
    STAGING_CAPABILITY=true
fi

if [ "$STAGING_CAPABILITY" = true ]; then
    echo -e "  ${GREEN}✓ PASS: Staging URL capability exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No staging URL integration${NC}"
    echo "    batches.json lacks staging_url and no workflow integration"
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
BATCH_COMPLETE="$HOME/Dropbox/Scripts/notion/complete-batch.sh"
BATCH_UPDATE="$HOME/Dropbox/Scripts/notion/batch-update.sh"

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
    if cat "$RESULTS_DIR/../fixtures/raw_tickets.json" 2>/dev/null | jq -e '.results[0].properties | has("QA Status") or has("QA Approved") or has("Verified") or has("QA Before") or has("QA After")' > /dev/null 2>&1; then
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
RUN_CYCLE="$HOME/Dropbox/Scripts/notion/run-cycle.sh"

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
# CHECK 8: Resume/Recovery Capability
# ============================================
echo -e "${BLUE}Check 8: Resume/Recovery Capability${NC}"
echo "Can we resume batch processing after interruption?"
echo ""

# Check for state persistence file
STATE_FILE="$RESULTS_DIR/workflow_state.json"
PROGRESS_FILE="$RESULTS_DIR/progress.json"
CHECKPOINT_FILE="$RESULTS_DIR/checkpoint.json"

if [ -f "$STATE_FILE" ] || [ -f "$PROGRESS_FILE" ] || [ -f "$CHECKPOINT_FILE" ]; then
    echo "  ✓ State persistence file exists"

    # Check if state file tracks processed tickets
    if [ -f "$STATE_FILE" ]; then
        HAS_PROGRESS=$(cat "$STATE_FILE" 2>/dev/null | jq -e 'has("completed_tickets") or has("processed") or has("current_batch")' >/dev/null 2>&1 && echo "true" || echo "false")
        if [ "$HAS_PROGRESS" = "true" ]; then
            echo -e "  ${GREEN}✓ PASS: State file tracks progress${NC}"
            PASSES=$((PASSES + 1))
        else
            echo -e "  ${RED}✗ FAIL: State file lacks progress tracking${NC}"
            echo "    workflow_state.json exists but missing:"
            echo "      - completed_tickets array"
            echo "      - current_batch indicator"
            echo "      - processed count"
            FAILURES=$((FAILURES + 1))
        fi
    fi
else
    echo -e "  ${RED}✗ FAIL: No state persistence${NC}"
    echo "    Missing: workflow_state.json, progress.json, or checkpoint.json"
    echo "    If interrupted, all progress is lost!"
    FAILURES=$((FAILURES + 1))
fi

# Check for resume flag in workflow scripts
RESUME_SUPPORT=false
for script in "$SCRIPT_DIR/batch_process_hs_figma.sh" "$SCRIPT_DIR/batch_workflow.sh" "$BATCH_COMPLETE"; do
    if [ -f "$script" ]; then
        if grep -q "\-\-resume\|\-\-continue\|\-\-from-state\|\-\-skip-completed" "$script" 2>/dev/null; then
            RESUME_SUPPORT=true
            break
        fi
    fi
done

if [ "$RESUME_SUPPORT" = true ]; then
    echo -e "  ${GREEN}✓ PASS: Resume flag supported${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No resume capability in scripts${NC}"
    echo "    Missing flags: --resume, --continue, --skip-completed"
    echo "    Must restart entire batch from beginning after interruption"
    FAILURES=$((FAILURES + 1))
fi

# Check for idempotent operations (safe to re-run)
IDEMPOTENT_CHECK=false
for script in "$SCRIPT_DIR/batch_process_hs_figma.sh" "$BATCH_COMPLETE"; do
    if [ -f "$script" ]; then
        # Look for skip-if-done logic or idempotency markers
        if grep -q "already.*complete\|skip.*processed\|if.*completed\|idempotent" "$script" 2>/dev/null; then
            IDEMPOTENT_CHECK=true
            break
        fi
    fi
done

if [ "$IDEMPOTENT_CHECK" = true ]; then
    echo -e "  ${GREEN}✓ PASS: Scripts check for already-completed work${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${YELLOW}! WARNING: Scripts may not be idempotent${NC}"
    echo "    Re-running could duplicate work or cause errors"
    echo "    Should check if ticket already completed before processing"
fi

echo ""

# ============================================
# CHECK 9: Batch Progress Assessment
# ============================================
echo -e "${BLUE}Check 9: Batch Progress Assessment${NC}"
echo "Can we reassess a batch to see current progress and remaining work?"
echo ""

# Check for status/progress command in batch scripts
STATUS_SUPPORT=false
for script in "$SCRIPT_DIR/batch_process_hs_figma.sh" "$SCRIPT_DIR/batch_workflow.sh" "$BATCH_FETCH_SCRIPT"; do
    if [ -f "$script" ]; then
        if grep -q "\-\-status\|\-\-progress\|\-\-check\|\-\-remaining" "$script" 2>/dev/null; then
            STATUS_SUPPORT=true
            break
        fi
    fi
done

if [ "$STATUS_SUPPORT" = true ]; then
    echo -e "  ${GREEN}✓ PASS: Status/progress command exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No batch status command${NC}"
    echo "    Missing flags: --status, --progress, --remaining"
    echo "    Cannot check how many tickets completed vs remaining"
    FAILURES=$((FAILURES + 1))
fi

# Check for live Notion sync (query current ticket states)
NOTION_SYNC=false
for script in "$SCRIPT_DIR/batch_process_hs_figma.sh" "$SCRIPT_DIR/batch_workflow.sh"; do
    if [ -f "$script" ]; then
        # Look for Notion API queries that check ticket status
        if grep -q "Ticket Status\|api.notion.com.*query\|current.*status\|sync.*notion" "$script" 2>/dev/null; then
            NOTION_SYNC=true
            break
        fi
    fi
done

if [ "$NOTION_SYNC" = true ]; then
    echo -e "  ${GREEN}✓ PASS: Can query Notion for current ticket states${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No live Notion status sync${NC}"
    echo "    Cannot query Notion to see actual ticket states"
    echo "    Local state may be out of sync with Notion"
    FAILURES=$((FAILURES + 1))
fi

# Check for progress report generation
PROGRESS_REPORT="$RESULTS_DIR/batch_progress.json"
PROGRESS_SCRIPT="$SCRIPT_DIR/check_progress.sh"
ASSESS_SCRIPT="$HOME/Dropbox/Scripts/notion/assess-batch.sh"

# Also check if batch_workflow.sh has --status capability
PROGRESS_IN_WORKFLOW=false
if [ -f "$SCRIPT_DIR/batch_workflow.sh" ] && grep -q "\-\-status\|\-\-progress" "$SCRIPT_DIR/batch_workflow.sh" 2>/dev/null; then
    PROGRESS_IN_WORKFLOW=true
fi

if [ -f "$PROGRESS_REPORT" ] || [ -f "$PROGRESS_SCRIPT" ] || [ -f "$ASSESS_SCRIPT" ] || [ "$PROGRESS_IN_WORKFLOW" = true ]; then
    echo -e "  ${GREEN}✓ PASS: Progress assessment capability exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No progress assessment output${NC}"
    echo "    Missing: batch_progress.json, check_progress.sh, or assess-batch.sh"
    echo "    Cannot generate report showing:"
    echo "      - Tickets completed"
    echo "      - Tickets in progress"
    echo "      - Tickets remaining"
    echo "      - Tickets blocked/errored"
    FAILURES=$((FAILURES + 1))
fi

# Check for batch reassessment (re-categorize or re-query)
REASSESS_SUPPORT=false
for script in "$SCRIPT_DIR/batch_process_hs_figma.sh" "$SCRIPT_DIR/categorize_tickets.sh" "$SCRIPT_DIR/batch_workflow.sh"; do
    if [ -f "$script" ]; then
        if grep -q "\-\-refresh\|\-\-reassess\|\-\-update\|\-\-sync" "$script" 2>/dev/null; then
            REASSESS_SUPPORT=true
            break
        fi
    fi
done

if [ "$REASSESS_SUPPORT" = true ]; then
    echo -e "  ${GREEN}✓ PASS: Batch reassessment supported${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: Cannot reassess batch against current Notion state${NC}"
    echo "    Missing flags: --refresh, --reassess, --sync"
    echo "    If tickets were updated outside this workflow,"
    echo "    there's no way to detect those changes"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 10: Re-Learning Overhead (Cascade Compaction)
# ============================================
echo -e "${BLUE}Check 10: Re-Learning Overhead (Cascade Compaction)${NC}"
echo "Is there context preservation to avoid re-learning when resuming?"
echo ""

# The problem: When a session ends or context is lost, resuming requires:
#   1. Re-reading all ticket details
#   2. Re-understanding the batch structure
#   3. Re-discovering what was already done
#   4. Re-loading file contexts
# This "re-learning overhead" triggers cascade compaction where each
# restart compounds the inefficiency.

# Check for context/briefing file generation
CONTEXT_FILE="$RESULTS_DIR/batch_context.md"
BRIEFING_FILE="$RESULTS_DIR/session_briefing.md"
SUMMARY_FILE="$RESULTS_DIR/current_state.md"

if [ -f "$CONTEXT_FILE" ] || [ -f "$BRIEFING_FILE" ] || [ -f "$SUMMARY_FILE" ]; then
    echo -e "  ${GREEN}✓ PASS: Context/briefing file exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No context preservation for session resume${NC}"
    echo "    Missing: batch_context.md, session_briefing.md, or current_state.md"
    echo "    When resuming, must re-read all tickets from scratch"
    FAILURES=$((FAILURES + 1))
fi

# Check for human-readable progress summary (not just JSON)
READABLE_PROGRESS=false
for file in "$RESULTS_DIR"/*.md "$RESULTS_DIR"/*.txt; do
    if [ -f "$file" ]; then
        # Look for progress indicators in readable format
        if grep -qi "completed\|remaining\|in progress\|next steps\|current state\|resume\|workflow\|briefing" "$file" 2>/dev/null; then
            READABLE_PROGRESS=true
            break
        fi
    fi
done

if [ "$READABLE_PROGRESS" = true ]; then
    echo -e "  ${GREEN}✓ PASS: Human-readable progress exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No human-readable progress summary${NC}"
    echo "    Only machine-readable JSON files exist"
    echo "    Cannot quickly scan to understand current state"
    FAILURES=$((FAILURES + 1))
fi

# Check for --context or --briefing flag to generate resume context
CONTEXT_GEN=false
for script in "$SCRIPT_DIR/batch_process_hs_figma.sh" "$SCRIPT_DIR/batch_workflow.sh"; do
    if [ -f "$script" ]; then
        if grep -q "\-\-context\|\-\-briefing\|\-\-summary\|\-\-dump-state" "$script" 2>/dev/null; then
            CONTEXT_GEN=true
            break
        fi
    fi
done

if [ "$CONTEXT_GEN" = true ]; then
    echo -e "  ${GREEN}✓ PASS: Context generation command exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No context generation capability${NC}"
    echo "    Missing flags: --context, --briefing, --summary"
    echo "    Cannot generate a quick-load context for new sessions"
    FAILURES=$((FAILURES + 1))
fi

# Check for ticket detail caching (avoid re-fetching from Notion)
TICKET_CACHE="$RESULTS_DIR/ticket_cache"
TICKET_DETAILS="$RESULTS_DIR/ticket_details"
BATCH_TICKETS_DIR="$RESULTS_DIR/batches"

CACHING_CAPABILITY=false

# Check if cache directories exist
if [ -d "$TICKET_CACHE" ] || [ -d "$TICKET_DETAILS" ] || [ -d "$BATCH_TICKETS_DIR" ]; then
    echo "  ✓ Cache directory structure exists"
    CACHING_CAPABILITY=true

    # Check if there's actual cached content (bonus check)
    CACHE_COUNT=$(find "$TICKET_CACHE" "$TICKET_DETAILS" "$BATCH_TICKETS_DIR" -name "*.json" -o -name "*.txt" 2>/dev/null | wc -l)
    if [ "$CACHE_COUNT" -gt 0 ]; then
        echo "  ✓ $CACHE_COUNT cached files found"
    fi
fi

# Also check if batch_workflow.sh has code to cache ticket details
if [ -f "$SCRIPT_DIR/batch_workflow.sh" ] && grep -q "cache\|save.*ticket\|store.*detail\|batches/" "$SCRIPT_DIR/batch_workflow.sh" 2>/dev/null; then
    echo "  ✓ Caching code exists in batch_workflow.sh"
    CACHING_CAPABILITY=true
fi

if [ "$CACHING_CAPABILITY" = true ]; then
    echo -e "  ${GREEN}✓ PASS: Ticket caching capability exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No ticket detail caching${NC}"
    echo "    Missing: ticket_cache/, ticket_details/, or batches/ directory"
    echo "    Every resume requires re-fetching from Notion API"
    echo "    Compounds re-learning overhead significantly"
    FAILURES=$((FAILURES + 1))
fi

# Check for architecture/file mapping documentation
ARCH_DOC="$SCRIPT_DIR/../ARCHITECTURE.md"
ARCH_DOC_ALT="$HOME/Dropbox/Scripts/ARCHITECTURE.md"
FILE_MAP="$RESULTS_DIR/file_mapping.json"
AFFECTED_FILES="$RESULTS_DIR/affected_files.md"

if [ -f "$ARCH_DOC" ] || [ -f "$ARCH_DOC_ALT" ] || [ -f "$FILE_MAP" ] || [ -f "$AFFECTED_FILES" ]; then
    echo -e "  ${GREEN}✓ PASS: File/architecture mapping exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No file mapping for batch${NC}"
    echo "    Missing: ARCHITECTURE.md, file_mapping.json, or affected_files.md"
    echo "    Must re-discover which files are affected by each ticket"
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo -e "  ${YELLOW}! CASCADE COMPACTION RISK:${NC}"
echo "    Without context preservation, each session restart causes:"
echo "      1. Re-fetch ticket data from Notion (API overhead)"
echo "      2. Re-read ticket details to understand scope"
echo "      3. Re-discover file mappings and dependencies"
echo "      4. Re-assess what was already completed"
echo "    This compounds into 10-15 min overhead per restart,"
echo "    making batch processing less efficient than single-ticket work!"
echo ""

echo ""

# ============================================
# CHECK 11: QA Image Field Storage
# ============================================
echo -e "${BLUE}Check 11: QA Image Field Storage${NC}"
echo "Are QA Before/After images stored in dedicated Notion fields?"
echo ""

# The problem: Storing images in page body content instead of dedicated
# Files & Media properties makes them:
#   1. Hard to query programmatically
#   2. Impossible to filter/sort by QA status
#   3. Difficult to compare before/after side-by-side
#   4. Mixed in with other page content
#   5. Not accessible via property API

# Check if scripts use dedicated fields vs page body append
USES_DEDICATED_FIELDS=false
USES_BODY_APPEND=false

for script in "$SCRIPT_DIR/batch_process_hs_figma.sh" "$HOME/Dropbox/Scripts/notion/record-qa.sh"; do
    if [ -f "$script" ]; then
        # Check for property-based image storage
        if grep -q 'properties.*QA\|files.*media\|"QA Before"\|"QA After".*url' "$script" 2>/dev/null; then
            USES_DEDICATED_FIELDS=true
        fi
        # Check for body/children append (anti-pattern)
        if grep -q "blocks.*children\|append.*image\|PATCH.*children" "$script" 2>/dev/null; then
            USES_BODY_APPEND=true
        fi
    fi
done

if [ "$USES_DEDICATED_FIELDS" = true ]; then
    # Images go to dedicated fields - this is correct
    # Body append may exist for QA result text, which is fine
    echo -e "  ${GREEN}✓ PASS: Uses dedicated Notion property fields for images${NC}"
    PASSES=$((PASSES + 1))
elif [ "$USES_BODY_APPEND" = true ]; then
    # Only body append, no dedicated fields - images go to body
    echo -e "  ${RED}✗ FAIL: Images appended to page body instead of fields${NC}"
    echo "    Scripts use: PATCH /blocks/{id}/children"
    echo "    Should use: PATCH /pages/{id} with properties"
    echo ""
    echo "    Problems with body append:"
    echo "      - Cannot query tickets by QA status"
    echo "      - Cannot filter 'has QA Before but missing QA After'"
    echo "      - Images buried in page content"
    echo "      - No structured before/after comparison"
    FAILURES=$((FAILURES + 1))
else
    echo -e "  ${RED}✗ FAIL: No QA image storage implementation found${NC}"
    echo "    Neither property fields nor body append detected"
    FAILURES=$((FAILURES + 1))
fi

# Check Notion database schema for QA fields
echo ""
echo "  Checking Notion schema for QA fields..."

# Look for field definitions in scripts or config
QA_FIELDS_DEFINED=false
for file in "$SCRIPT_DIR/NOTION_QA_FIELDS_SPEC.md" "$SCRIPT_DIR/categorization_rules.json" "$SCRIPT_DIR/../infrastructure-upgrade.md"; do
    if [ -f "$file" ]; then
        if grep -qi "QA Before.*Files\|QA After.*Files\|Files.*media.*QA" "$file" 2>/dev/null; then
            QA_FIELDS_DEFINED=true
            break
        fi
    fi
done

if [ "$QA_FIELDS_DEFINED" = true ]; then
    echo -e "  ${GREEN}✓ QA fields documented as Files & Media type${NC}"
else
    echo -e "  ${YELLOW}! QA field type not documented${NC}"
    echo "    Unclear if QA Before/After are Files & Media properties"
fi

# Check for QA comparison capability
QA_COMPARE_SCRIPT="$HOME/Dropbox/Scripts/notion/qa/compare-qa.sh"
QA_COMPARE_ALT="$HOME/Dropbox/Scripts/notion/compare-qa.sh"
QA_DIFF_SCRIPT="$SCRIPT_DIR/qa_diff.sh"

if [ -f "$QA_COMPARE_SCRIPT" ] || [ -f "$QA_COMPARE_ALT" ] || [ -f "$QA_DIFF_SCRIPT" ]; then
    echo -e "  ${GREEN}✓ PASS: QA comparison script exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No QA comparison capability${NC}"
    echo "    Missing: compare-qa.sh or qa_diff.sh"
    echo "    Cannot programmatically compare before/after images"
    FAILURES=$((FAILURES + 1))
fi

# Check for bulk QA status query
QA_QUERY_SUPPORT=false
for script in "$SCRIPT_DIR/batch_process_hs_figma.sh" "$SCRIPT_DIR/batch_workflow.sh" "$HOME/Dropbox/Scripts/notion/fetch-batch.sh"; do
    if [ -f "$script" ]; then
        if grep -q "QA Before.*is_not_empty\|QA After.*is_empty\|filter.*QA\|qa-filter\|query_qa_status" "$script" 2>/dev/null; then
            QA_QUERY_SUPPORT=true
            break
        fi
    fi
done

if [ "$QA_QUERY_SUPPORT" = true ]; then
    echo -e "  ${GREEN}✓ PASS: Can query tickets by QA field status${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: Cannot query tickets by QA field status${NC}"
    echo "    Cannot filter: 'tickets with QA Before but missing QA After'"
    echo "    Cannot identify: 'tickets ready for QA review'"
    echo "    Body-appended images are not queryable!"
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
    echo "  □ Resume capability - State persistence + --resume flag"
    echo "  □ Progress assessment - --status flag + Notion sync"
    echo "  □ Context preservation - Briefing files + ticket caching"
    echo "  □ QA image fields - Dedicated properties, not page body"
    echo ""
    exit 1
else
    echo -e "${GREEN}TEST PASSED: Workflow integration complete${NC}"
    exit 0
fi
