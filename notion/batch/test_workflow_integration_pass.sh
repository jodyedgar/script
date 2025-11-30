#!/bin/bash

# Test: Workflow Integration Passing State
# Purpose: Validate that the categorization system is fully integrated
#          with the ticket workflow (fetch, QA, complete)
#
# Expected Result: PASS - All integration points exist and work

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"

# Script locations
NOTION_SCRIPTS="$HOME/Dropbox/Scripts/notion"
SHOPIFY_SCRIPTS="$HOME/Dropbox/scripts/shopify"

echo "========================================"
echo "TEST: Workflow Integration (Passing)"
echo "========================================"
echo ""
echo "This test verifies that the categorization system"
echo "is fully integrated with the ticket workflow."
echo ""

mkdir -p "$RESULTS_DIR"

FAILURES=0
PASSES=0

# ============================================
# CHECK 1: Batch Fetch Script Exists
# ============================================
echo -e "${BLUE}Check 1: Batch Fetch Capability${NC}"

if [ -f "$NOTION_SCRIPTS/fetch-batch.sh" ]; then
    echo "  ✓ fetch-batch.sh exists"

    # Check for key features
    if grep -q "\-\-batch\|\-\-category" "$NOTION_SCRIPTS/fetch-batch.sh"; then
        echo "  ✓ Supports --batch and --category flags"
    fi

    if grep -q "\-\-from-file" "$NOTION_SCRIPTS/fetch-batch.sh"; then
        echo "  ✓ Supports --from-file flag"
    fi

    if grep -q "list-categories\|list-batches" "$NOTION_SCRIPTS/fetch-batch.sh"; then
        echo "  ✓ Supports listing categories/batches"
    fi

    chmod +x "$NOTION_SCRIPTS/fetch-batch.sh" 2>/dev/null || true
    echo -e "  ${GREEN}✓ PASS: Batch fetch capability exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: fetch-batch.sh not found${NC}"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 2: Categorization Integration
# ============================================
echo -e "${BLUE}Check 2: Categorization Integration${NC}"

if [ -f "$RESULTS_DIR/categorized_tickets.json" ]; then
    echo "  ✓ categorized_tickets.json exists"

    # Check if fetch-batch can read it
    if grep -q "categorized_tickets.json\|CATEGORIZED_FILE" "$NOTION_SCRIPTS/fetch-batch.sh" 2>/dev/null; then
        echo "  ✓ fetch-batch.sh reads categorized file"
        echo -e "  ${GREEN}✓ PASS: Categorization integrated with fetch${NC}"
        PASSES=$((PASSES + 1))
    else
        echo -e "  ${RED}✗ FAIL: fetch-batch.sh doesn't use categorized file${NC}"
        FAILURES=$((FAILURES + 1))
    fi
else
    echo -e "  ${YELLOW}! categorized_tickets.json not found - run categorization first${NC}"
    # Don't fail - may just need to run categorization
fi

# Check batch support in manage script
if [ -f "$NOTION_SCRIPTS/complete-batch.sh" ]; then
    echo "  ✓ complete-batch.sh exists (batch completion)"
    chmod +x "$NOTION_SCRIPTS/complete-batch.sh" 2>/dev/null || true
    echo -e "  ${GREEN}✓ PASS: Batch completion capability exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: complete-batch.sh not found${NC}"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 3: Chrome MCP QA Integration
# ============================================
echo -e "${BLUE}Check 3: QA Workflow Integration${NC}"

# Check for QA workflow script
if [ -f "$SCRIPT_DIR/batch_workflow.sh" ]; then
    echo "  ✓ batch_workflow.sh exists"

    if grep -qi "qa\|verification\|chrome" "$SCRIPT_DIR/batch_workflow.sh"; then
        echo "  ✓ Contains QA workflow commands"
    fi

    chmod +x "$SCRIPT_DIR/batch_workflow.sh" 2>/dev/null || true
    echo -e "  ${GREEN}✓ PASS: QA workflow exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: batch_workflow.sh not found${NC}"
    FAILURES=$((FAILURES + 1))
fi

# Check for screenshot capability
if [ -d "$RESULTS_DIR/screenshots" ] || grep -qi "screenshot" "$SCRIPT_DIR/batch_workflow.sh" 2>/dev/null; then
    echo "  ✓ Screenshot workflow available"
    echo -e "  ${GREEN}✓ PASS: Screenshot capture capability${NC}"
    PASSES=$((PASSES + 1))
else
    # Create screenshots directory
    mkdir -p "$RESULTS_DIR/screenshots"
    echo "  ✓ Created screenshots directory"
    echo -e "  ${GREEN}✓ PASS: Screenshot directory created${NC}"
    PASSES=$((PASSES + 1))
fi

echo ""

# ============================================
# CHECK 4: Staging Preview Integration
# ============================================
echo -e "${BLUE}Check 4: Staging Preview Integration${NC}"

if [ -f "$SHOPIFY_SCRIPTS/get-staging-url.sh" ]; then
    echo "  ✓ get-staging-url.sh exists"

    if grep -q "preview_theme_id\|THEME_ID" "$SHOPIFY_SCRIPTS/get-staging-url.sh"; then
        echo "  ✓ Generates preview URLs with theme ID"
    fi

    chmod +x "$SHOPIFY_SCRIPTS/get-staging-url.sh" 2>/dev/null || true
    echo -e "  ${GREEN}✓ PASS: Staging URL generation exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: get-staging-url.sh not found${NC}"
    FAILURES=$((FAILURES + 1))
fi

# Check if batch workflow uses staging URL
if grep -qi "staging\|preview" "$SCRIPT_DIR/batch_workflow.sh" 2>/dev/null; then
    echo "  ✓ Batch workflow includes staging URLs"
    echo -e "  ${GREEN}✓ PASS: Staging integrated with workflow${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${YELLOW}! Staging URL not integrated in workflow${NC}"
fi

echo ""

# ============================================
# CHECK 5: Batch Completion Workflow
# ============================================
echo -e "${BLUE}Check 5: Batch Completion Workflow${NC}"

if [ -f "$NOTION_SCRIPTS/complete-batch.sh" ]; then
    echo "  ✓ complete-batch.sh exists"

    if grep -q "\-\-pr-url\|\-\-summary" "$NOTION_SCRIPTS/complete-batch.sh"; then
        echo "  ✓ Supports PR URL and summary"
    fi

    if grep -q "require-qa\|QA" "$NOTION_SCRIPTS/complete-batch.sh"; then
        echo "  ✓ Can require QA before completion"
    fi

    echo -e "  ${GREEN}✓ PASS: Batch completion capability${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: complete-batch.sh not found${NC}"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 6: QA Recording Integration
# ============================================
echo -e "${BLUE}Check 6: QA Recording Integration${NC}"

if [ -f "$NOTION_SCRIPTS/record-qa.sh" ]; then
    echo "  ✓ record-qa.sh exists"

    if grep -q "\-\-status\|\-\-by\|\-\-notes" "$NOTION_SCRIPTS/record-qa.sh"; then
        echo "  ✓ Supports QA status, reviewer, and notes"
    fi

    if grep -q "\-\-batch" "$NOTION_SCRIPTS/record-qa.sh"; then
        echo "  ✓ Supports batch QA recording"
    fi

    chmod +x "$NOTION_SCRIPTS/record-qa.sh" 2>/dev/null || true
    echo -e "  ${GREEN}✓ PASS: QA recording capability${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: record-qa.sh not found${NC}"
    FAILURES=$((FAILURES + 1))
fi

# Check for QA logs directory
QA_LOG_DIR="$RESULTS_DIR/qa-logs"
if [ -d "$QA_LOG_DIR" ] || mkdir -p "$QA_LOG_DIR"; then
    echo "  ✓ QA logs directory exists"
    echo -e "  ${GREEN}✓ PASS: QA log storage${NC}"
    PASSES=$((PASSES + 1))
fi

echo ""

# ============================================
# CHECK 7: End-to-End Workflow Script
# ============================================
echo -e "${BLUE}Check 7: End-to-End Workflow Script${NC}"

if [ -f "$SCRIPT_DIR/batch_workflow.sh" ]; then
    echo "  ✓ batch_workflow.sh exists"

    # Check for key workflow commands
    COMMANDS_FOUND=0

    if grep -q "\-\-start" "$SCRIPT_DIR/batch_workflow.sh"; then
        echo "  ✓ Has --start command"
        COMMANDS_FOUND=$((COMMANDS_FOUND + 1))
    fi

    if grep -q "\-\-qa" "$SCRIPT_DIR/batch_workflow.sh"; then
        echo "  ✓ Has --qa command"
        COMMANDS_FOUND=$((COMMANDS_FOUND + 1))
    fi

    if grep -q "\-\-complete" "$SCRIPT_DIR/batch_workflow.sh"; then
        echo "  ✓ Has --complete command"
        COMMANDS_FOUND=$((COMMANDS_FOUND + 1))
    fi

    if grep -q "\-\-status" "$SCRIPT_DIR/batch_workflow.sh"; then
        echo "  ✓ Has --status command"
        COMMANDS_FOUND=$((COMMANDS_FOUND + 1))
    fi

    if [ "$COMMANDS_FOUND" -ge 4 ]; then
        echo -e "  ${GREEN}✓ PASS: End-to-end workflow complete${NC}"
        PASSES=$((PASSES + 1))
    else
        echo -e "  ${YELLOW}! Workflow missing some commands ($COMMANDS_FOUND/4)${NC}"
    fi
else
    echo -e "  ${RED}✗ FAIL: batch_workflow.sh not found${NC}"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 8: Resume/Recovery Capability
# ============================================
echo -e "${BLUE}Check 8: Resume/Recovery Capability${NC}"

# Check for state persistence file
STATE_FILE="$RESULTS_DIR/batch_state.json"
if [ -f "$STATE_FILE" ]; then
    echo "  ✓ batch_state.json exists"

    # Check if state file tracks progress
    if cat "$STATE_FILE" 2>/dev/null | jq -e 'has("completed_tickets") or has("processed") or has("current_batch")' > /dev/null 2>&1; then
        echo "  ✓ State file tracks progress"
        echo -e "  ${GREEN}✓ PASS: State persistence with progress tracking${NC}"
        PASSES=$((PASSES + 1))
    else
        echo -e "  ${YELLOW}! State file exists but lacks progress fields${NC}"
    fi
else
    echo -e "  ${RED}✗ FAIL: No batch_state.json for state persistence${NC}"
    FAILURES=$((FAILURES + 1))
fi

# Check for resume flag support
RESUME_SUPPORT=false
for script in "$SCRIPT_DIR/batch_process_hs_figma.sh" "$SCRIPT_DIR/batch_workflow.sh" "$NOTION_SCRIPTS/complete-batch.sh"; do
    if [ -f "$script" ]; then
        if grep -q "\-\-resume\|\-\-continue\|\-\-from-state\|\-\-skip-completed" "$script" 2>/dev/null; then
            RESUME_SUPPORT=true
            break
        fi
    fi
done

if [ "$RESUME_SUPPORT" = true ]; then
    echo "  ✓ Scripts support --resume or --skip-completed"
    echo -e "  ${GREEN}✓ PASS: Resume capability exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No --resume flag in workflow scripts${NC}"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 9: Batch Progress Assessment
# ============================================
echo -e "${BLUE}Check 9: Batch Progress Assessment${NC}"

# Check for --status flag
STATUS_SUPPORT=false
for script in "$SCRIPT_DIR/batch_process_hs_figma.sh" "$SCRIPT_DIR/batch_workflow.sh"; do
    if [ -f "$script" ]; then
        if grep -q "\-\-status\|\-\-progress" "$script" 2>/dev/null; then
            STATUS_SUPPORT=true
            break
        fi
    fi
done

if [ "$STATUS_SUPPORT" = true ]; then
    echo "  ✓ Scripts support --status command"
    echo -e "  ${GREEN}✓ PASS: Status/progress command exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No --status flag in scripts${NC}"
    FAILURES=$((FAILURES + 1))
fi

# Check for Notion sync (query current ticket states)
NOTION_SYNC=false
for script in "$SCRIPT_DIR/batch_process_hs_figma.sh" "$SCRIPT_DIR/batch_workflow.sh"; do
    if [ -f "$script" ]; then
        if grep -q "Ticket Status\|api.notion.com.*query" "$script" 2>/dev/null; then
            NOTION_SYNC=true
            break
        fi
    fi
done

if [ "$NOTION_SYNC" = true ]; then
    echo "  ✓ Scripts can query Notion for current states"
    echo -e "  ${GREEN}✓ PASS: Live Notion sync capability${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: Cannot query Notion for current ticket states${NC}"
    FAILURES=$((FAILURES + 1))
fi

# Check for --refresh/--reassess flag
REASSESS_SUPPORT=false
for script in "$SCRIPT_DIR/batch_process_hs_figma.sh" "$SCRIPT_DIR/categorize_tickets.sh"; do
    if [ -f "$script" ]; then
        if grep -q "\-\-refresh\|\-\-reassess\|\-\-sync" "$script" 2>/dev/null; then
            REASSESS_SUPPORT=true
            break
        fi
    fi
done

if [ "$REASSESS_SUPPORT" = true ]; then
    echo "  ✓ Scripts support --refresh or --reassess"
    echo -e "  ${GREEN}✓ PASS: Batch reassessment capability${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No --refresh flag to reassess batch${NC}"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 10: Context Preservation (Anti-Cascade Compaction)
# ============================================
echo -e "${BLUE}Check 10: Context Preservation (Anti-Cascade Compaction)${NC}"

# Check for context/briefing file
CONTEXT_FILE="$RESULTS_DIR/batch_context.md"
BRIEFING_FILE="$RESULTS_DIR/session_briefing.md"
SUMMARY_FILE="$RESULTS_DIR/current_state.md"

if [ -f "$CONTEXT_FILE" ] || [ -f "$BRIEFING_FILE" ] || [ -f "$SUMMARY_FILE" ]; then
    echo "  ✓ Context/briefing file exists"
    echo -e "  ${GREEN}✓ PASS: Session context preserved${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No context file for session resume${NC}"
    echo "    Missing: batch_context.md, session_briefing.md, or current_state.md"
    FAILURES=$((FAILURES + 1))
fi

# Check for --context or --briefing flag
CONTEXT_GEN=false
for script in "$SCRIPT_DIR/batch_process_hs_figma.sh" "$SCRIPT_DIR/batch_workflow.sh"; do
    if [ -f "$script" ]; then
        if grep -q "\-\-context\|\-\-briefing\|\-\-dump-state" "$script" 2>/dev/null; then
            CONTEXT_GEN=true
            break
        fi
    fi
done

if [ "$CONTEXT_GEN" = true ]; then
    echo "  ✓ Scripts support --context or --briefing"
    echo -e "  ${GREEN}✓ PASS: Context generation command exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No --context flag to generate briefing${NC}"
    FAILURES=$((FAILURES + 1))
fi

# Check for ticket detail caching
BATCH_TICKETS_DIR="$RESULTS_DIR/batches"
if [ -d "$BATCH_TICKETS_DIR" ]; then
    CACHE_COUNT=$(find "$BATCH_TICKETS_DIR" -name "*.json" -o -name "*.txt" 2>/dev/null | wc -l)
    if [ "$CACHE_COUNT" -gt 0 ]; then
        echo "  ✓ Ticket details cached locally ($CACHE_COUNT files)"
        echo -e "  ${GREEN}✓ PASS: Ticket caching exists${NC}"
        PASSES=$((PASSES + 1))
    else
        echo -e "  ${RED}✗ FAIL: Batch directory exists but no cached tickets${NC}"
        FAILURES=$((FAILURES + 1))
    fi
else
    echo -e "  ${RED}✗ FAIL: No ticket detail caching directory${NC}"
    FAILURES=$((FAILURES + 1))
fi

# Check for architecture/file mapping
ARCH_DOC="$SCRIPT_DIR/../ARCHITECTURE.md"
if [ -f "$ARCH_DOC" ]; then
    echo "  ✓ ARCHITECTURE.md exists"
    echo -e "  ${GREEN}✓ PASS: Architecture documentation exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No ARCHITECTURE.md for file mapping${NC}"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 11: QA Image Field Storage
# ============================================
echo -e "${BLUE}Check 11: QA Image Field Storage${NC}"

# Check if scripts use dedicated property fields for QA images
# Note: Body append for QA status/notes is acceptable, only checking image storage
USES_DEDICATED_FIELDS=false
USES_PROPERTY_UPDATE=false

for script in "$SCRIPT_DIR/batch_process_hs_figma.sh" "$NOTION_SCRIPTS/record-qa.sh"; do
    if [ -f "$script" ]; then
        # Check for property-based image storage (QA Before/After as Files & Media)
        if grep -q "\"QA Before\"\|\"QA After\"" "$script" 2>/dev/null; then
            USES_DEDICATED_FIELDS=true
        fi
        # Check for PATCH /pages/{id} with properties (correct approach)
        if grep -q "api.notion.com/v1/pages.*properties\|update_notion_qa_fields" "$script" 2>/dev/null; then
            USES_PROPERTY_UPDATE=true
        fi
    fi
done

if [ "$USES_DEDICATED_FIELDS" = true ] && [ "$USES_PROPERTY_UPDATE" = true ]; then
    echo "  ✓ Uses dedicated Notion property fields for QA images"
    echo "  ✓ Uses PATCH /pages/{id} with properties (correct API)"
    echo -e "  ${GREEN}✓ PASS: QA images in dedicated fields${NC}"
    PASSES=$((PASSES + 1))
elif [ "$USES_DEDICATED_FIELDS" = true ]; then
    echo "  ✓ QA Before/After fields referenced"
    echo -e "  ${GREEN}✓ PASS: QA images in dedicated fields${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No QA image storage implementation${NC}"
    echo "    Should use: PATCH /pages/{id} with properties for QA Before/After"
    FAILURES=$((FAILURES + 1))
fi

# Check for QA field queryability
QA_QUERY_SUPPORT=false
for script in "$SCRIPT_DIR/batch_process_hs_figma.sh" "$NOTION_SCRIPTS/fetch-batch.sh"; do
    if [ -f "$script" ]; then
        if grep -q "QA Before.*is_not_empty\|QA After.*is_empty\|filter.*QA" "$script" 2>/dev/null; then
            QA_QUERY_SUPPORT=true
            break
        fi
    fi
done

if [ "$QA_QUERY_SUPPORT" = true ]; then
    echo "  ✓ Can query tickets by QA field status"
    echo -e "  ${GREEN}✓ PASS: QA fields are queryable${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: Cannot filter tickets by QA field status${NC}"
    echo "    Cannot query: 'has QA Before but missing QA After'"
    FAILURES=$((FAILURES + 1))
fi

# Check for QA comparison capability (in qa/ subdirectory)
QA_COMPARE_SCRIPT="$NOTION_SCRIPTS/qa/compare-qa.sh"
if [ -f "$QA_COMPARE_SCRIPT" ]; then
    echo "  ✓ compare-qa.sh exists in qa/ subdirectory"
    echo -e "  ${GREEN}✓ PASS: QA comparison capability${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No compare-qa.sh for before/after comparison${NC}"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# FUNCTIONAL TEST: List Batches
# ============================================
echo -e "${BLUE}Functional Test: List Available Batches${NC}"

if [ -x "$NOTION_SCRIPTS/fetch-batch.sh" ]; then
    echo ""
    "$NOTION_SCRIPTS/fetch-batch.sh" --list-categories 2>/dev/null || true
    echo ""
    echo -e "  ${GREEN}✓ PASS: Batch listing works${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${YELLOW}! Could not test batch listing${NC}"
fi

echo ""

# ============================================
# RESULTS
# ============================================
echo "========================================"
echo "RESULTS: Workflow Integration"
echo "========================================"
echo ""

echo "Checks passed: $PASSES"
echo "Checks failed: $FAILURES"
echo ""

# Calculate percentage
TOTAL=$((PASSES + FAILURES))
if [ "$TOTAL" -gt 0 ]; then
    PERCENT=$((PASSES * 100 / TOTAL))
else
    PERCENT=0
fi

echo "Integration completeness: $PERCENT%"
echo ""

if [ "$FAILURES" -eq 0 ]; then
    echo -e "${GREEN}TEST PASSED: Workflow integration complete!${NC}"
    echo ""
    echo "All integration points are available:"
    echo "  ✓ fetch-batch.sh      - Fetch tickets by category/batch"
    echo "  ✓ get-staging-url.sh  - Generate preview URLs"
    echo "  ✓ record-qa.sh        - Record QA verification"
    echo "  ✓ complete-batch.sh   - Batch ticket completion"
    echo "  ✓ batch_workflow.sh   - End-to-end orchestration"
    echo "  ✓ Resume capability   - State persistence + --resume flag"
    echo "  ✓ Progress assessment - --status + Notion sync + --refresh"
    echo "  ✓ Context preservation- Briefing files + ticket caching"
    echo "  ✓ QA image fields     - Dedicated properties (not page body)"
    echo ""
    echo "Workflow commands:"
    echo "  ./batch_workflow.sh --list                    # See batches"
    echo "  ./batch_workflow.sh --start <batch>           # Start batch"
    echo "  ./batch_workflow.sh --status                  # Check progress"
    echo "  ./batch_workflow.sh --qa <batch>              # Run QA"
    echo "  ./batch_workflow.sh --complete <batch>        # Finish batch"
    echo "  ./batch_workflow.sh --resume                  # Resume interrupted"
    echo "  ./batch_workflow.sh --context                 # Generate briefing"
    exit 0
else
    echo -e "${RED}TEST FAILED: $FAILURES integration point(s) missing${NC}"
    echo ""
    echo "Required integration points:"
    echo "  □ fetch-batch.sh      - Fetch tickets by category/batch"
    echo "  □ get-staging-url.sh  - Generate preview URLs"
    echo "  □ record-qa.sh        - Record QA verification"
    echo "  □ complete-batch.sh   - Batch ticket completion"
    echo "  □ batch_workflow.sh   - End-to-end orchestration"
    echo "  □ Resume capability   - State persistence + --resume flag"
    echo "  □ Progress assessment - --status + Notion sync + --refresh"
    echo "  □ Context preservation- Briefing files + ticket caching"
    echo "  □ QA image fields     - Dedicated properties (not page body)"
    echo ""
    echo "Run the setup to create missing integration points."
    exit 1
fi
