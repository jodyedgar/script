#!/bin/bash

# Test: QA Process Recording Failed State
# Purpose: Demonstrate that there is no way to record QA process in Notion
#
# Expected Result: FAIL - No QA tracking infrastructure exists
#
# Without QA recording in Notion:
#   - No audit trail of who approved what
#   - No evidence that changes were verified
#   - No staging preview URLs stored
#   - No QA screenshots/recordings linked
#   - No way to know if QA passed or failed
#   - No accountability for QA sign-off
#
# This is critical for:
#   - Client confidence (proof of verification)
#   - Team accountability (who approved?)
#   - Debugging regressions (when was it last verified?)
#   - Batch processing (which tickets in batch are QA'd?)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"

# Notion database ID
TICKETS_DATABASE_ID="1abc197b3ae7808fa454dd0c0e96ca6f"

echo "========================================"
echo "TEST: QA Process Recording in Notion"
echo "========================================"
echo ""
echo "This test verifies that QA verification can be"
echo "properly recorded and tracked in Notion tickets."
echo ""

mkdir -p "$RESULTS_DIR"

# Load credentials
if [ -f "$HOME/.bash_profile" ]; then
    source "$HOME/.bash_profile"
fi

if [ -z "$NOTION_API_KEY" ]; then
    echo -e "${RED}FAIL: NOTION_API_KEY not set${NC}"
    exit 1
fi

FAILURES=0
PASSES=0

# ============================================
# Fetch current database schema
# ============================================
echo "Fetching Notion database schema..."
echo ""

SCHEMA=$(curl -s -X GET "https://api.notion.com/v1/databases/$TICKETS_DATABASE_ID" \
  -H "Authorization: Bearer $NOTION_API_KEY" \
  -H "Notion-Version: 2022-06-28")

# Save schema for analysis
echo "$SCHEMA" > "$RESULTS_DIR/notion_schema.json"

# Extract property names
PROPERTIES=$(echo "$SCHEMA" | jq -r '.properties | keys[]')
echo "Current database fields:"
echo "$PROPERTIES" | sed 's/^/  - /'
echo ""

# ============================================
# CHECK 1: QA Status Field
# ============================================
echo -e "${BLUE}Check 1: QA Status Field${NC}"
echo "Is there a field to track QA verification status?"
echo ""

# Required QA status options: Pending QA, QA In Progress, QA Passed, QA Failed, QA Skipped
if echo "$PROPERTIES" | grep -qi "QA Status\|QA Verification\|Verified"; then
    echo -e "  ${GREEN}✓ PASS: QA Status field exists${NC}"
    PASSES=$((PASSES + 1))

    # Check if it has proper options
    QA_FIELD=$(echo "$SCHEMA" | jq '.properties | to_entries[] | select(.key | test("QA|Verified"; "i"))')
    echo "  Field details: $QA_FIELD"
else
    echo -e "  ${RED}✗ FAIL: No QA Status field${NC}"
    echo "    Missing field to track: Pending QA → QA Passed/Failed"
    echo "    Cannot record whether changes have been verified"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 2: QA Approved By Field
# ============================================
echo -e "${BLUE}Check 2: QA Approved By Field${NC}"
echo "Is there a field to record who performed QA?"
echo ""

if echo "$PROPERTIES" | grep -qi "QA.*By\|Approved By\|Verified By\|QA Reviewer"; then
    echo -e "  ${GREEN}✓ PASS: QA Approved By field exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No QA Approved By field${NC}"
    echo "    Missing: Person field for QA reviewer"
    echo "    No accountability for who signed off on changes"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 3: QA Timestamp Field
# ============================================
echo -e "${BLUE}Check 3: QA Timestamp Field${NC}"
echo "Is there a field to record when QA was performed?"
echo ""

if echo "$PROPERTIES" | grep -qi "QA.*Time\|QA.*Date\|Verified.*Time\|Approved.*Date"; then
    echo -e "  ${GREEN}✓ PASS: QA Timestamp field exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No QA Timestamp field${NC}"
    echo "    Missing: Date field for QA completion time"
    echo "    Cannot track when verification occurred"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 4: Staging Preview URL Field
# ============================================
echo -e "${BLUE}Check 4: Staging Preview URL Field${NC}"
echo "Is there a field to store the staging/preview URL?"
echo ""

if echo "$PROPERTIES" | grep -qi "Staging.*URL\|Preview.*URL\|Theme.*Preview"; then
    echo -e "  ${GREEN}✓ PASS: Staging Preview URL field exists${NC}"
    PASSES=$((PASSES + 1))
else
    # Check if Theme ID exists (partial credit)
    if echo "$PROPERTIES" | grep -qi "Theme ID"; then
        echo -e "  ${YELLOW}~ PARTIAL: Shopify Theme ID exists but no Preview URL${NC}"
        echo "    Theme ID can generate preview URL but it's not stored"
    fi
    echo -e "  ${RED}✗ FAIL: No Staging Preview URL field${NC}"
    echo "    Missing: URL field for staging preview link"
    echo "    QA reviewer cannot easily access preview"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 5: QA Evidence/Screenshots Field
# ============================================
echo -e "${BLUE}Check 5: QA Evidence Field${NC}"
echo "Is there a field to attach QA screenshots/recordings?"
echo ""

# Check for files field or dedicated QA evidence field
if echo "$PROPERTIES" | grep -qi "QA.*Screenshot\|QA.*Evidence\|QA.*Files\|Verification.*Screenshot"; then
    echo -e "  ${GREEN}✓ PASS: QA Evidence field exists${NC}"
    PASSES=$((PASSES + 1))
else
    # Check if general Files field could be used
    if echo "$PROPERTIES" | grep -qi "Files\|Artifact"; then
        echo -e "  ${YELLOW}~ PARTIAL: General Files field exists${NC}"
        echo "    Could store QA evidence but not dedicated/organized"
    fi
    echo -e "  ${RED}✗ FAIL: No dedicated QA Evidence field${NC}"
    echo "    Missing: Files field for QA screenshots/recordings"
    echo "    No visual proof of verification"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 6: QA Notes/Comments Field
# ============================================
echo -e "${BLUE}Check 6: QA Notes Field${NC}"
echo "Is there a field for QA reviewer notes/feedback?"
echo ""

if echo "$PROPERTIES" | grep -qi "QA.*Notes\|QA.*Comments\|QA.*Feedback\|Verification.*Notes"; then
    echo -e "  ${GREEN}✓ PASS: QA Notes field exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No QA Notes field${NC}"
    echo "    Missing: Text field for QA observations"
    echo "    Cannot document issues found during QA"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 7: QA Environment Field
# ============================================
echo -e "${BLUE}Check 7: QA Environment Field${NC}"
echo "Is there a field to record QA test environment?"
echo ""

if echo "$PROPERTIES" | grep -qi "QA.*Environment\|Test.*Environment\|Browser\|Device"; then
    echo -e "  ${GREEN}✓ PASS: QA Environment field exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No QA Environment field${NC}"
    echo "    Missing: Field for browser/device/viewport tested"
    echo "    Cannot track which environments were verified"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 8: Batch QA Tracking
# ============================================
echo -e "${BLUE}Check 8: Batch QA Identifier${NC}"
echo "Is there a field to group tickets by QA batch?"
echo ""

if echo "$PROPERTIES" | grep -qi "QA.*Batch\|Batch.*ID\|Cycle.*ID"; then
    # Check if it's specifically for QA batching
    if echo "$PROPERTIES" | grep -qi "QA.*Batch"; then
        echo -e "  ${GREEN}✓ PASS: QA Batch field exists${NC}"
        PASSES=$((PASSES + 1))
    else
        echo -e "  ${YELLOW}~ PARTIAL: Cycle ID exists but not QA-specific${NC}"
        echo "    Bucky Cycle ID tracks work cycles, not QA batches"
        echo -e "  ${RED}✗ FAIL: No QA Batch identifier${NC}"
        FAILURES=$((FAILURES + 1))
    fi
else
    echo -e "  ${RED}✗ FAIL: No QA Batch identifier${NC}"
    echo "    Missing: Field to group tickets QA'd together"
    echo "    Cannot track batch QA sessions"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 9: QA Script Integration
# ============================================
echo -e "${BLUE}Check 9: QA Recording Script${NC}"
echo "Is there a script to record QA results in Notion?"
echo ""

QA_RECORD_SCRIPT="$HOME/Dropbox/scripts/notion/record-qa.sh"
QA_UPDATE_SCRIPT="$HOME/Dropbox/scripts/notion/update-qa-status.sh"

if [ -f "$QA_RECORD_SCRIPT" ] || [ -f "$QA_UPDATE_SCRIPT" ]; then
    echo -e "  ${GREEN}✓ PASS: QA recording script exists${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "  ${RED}✗ FAIL: No QA recording script${NC}"
    echo "    Missing: record-qa.sh or update-qa-status.sh"
    echo "    No automated way to update QA fields in Notion"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 10: manage-notion-ticket.sh QA Support
# ============================================
echo -e "${BLUE}Check 10: QA Options in manage-notion-ticket.sh${NC}"
echo "Does the manage script support QA-related updates?"
echo ""

MANAGE_SCRIPT="$HOME/Dropbox/scripts/notion/manage-notion-ticket.sh"

if [ -f "$MANAGE_SCRIPT" ]; then
    if grep -qi "\-\-qa\|\-\-verified\|\-\-approved" "$MANAGE_SCRIPT"; then
        echo -e "  ${GREEN}✓ PASS: QA options in manage script${NC}"
        PASSES=$((PASSES + 1))
    else
        echo -e "  ${RED}✗ FAIL: No QA options in manage-notion-ticket.sh${NC}"
        echo "    Missing flags: --qa-status, --qa-by, --qa-notes"
        echo "    Cannot record QA through existing workflow"
        FAILURES=$((FAILURES + 1))
    fi
else
    echo -e "  ${RED}✗ FAIL: manage-notion-ticket.sh not found${NC}"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# CHECK 11: QA Image Storage in Single Ticket Workflow
# ============================================
echo -e "${BLUE}Check 11: QA Image Storage in Single Ticket Workflow${NC}"
echo "Does the single ticket workflow support QA Before/After images?"
echo ""

MANAGE_SCRIPT="$HOME/Dropbox/scripts/notion/manage-notion-ticket.sh"

if [ -f "$MANAGE_SCRIPT" ]; then
    # Check if manage script supports storing QA images
    if grep -qi "\-\-qa-before\|\-\-qa-after\|\-\-feedbucket\|\-\-screenshot" "$MANAGE_SCRIPT"; then
        echo -e "  ${GREEN}✓ PASS: Single ticket workflow supports QA images${NC}"
        echo "    QA image storage from batch processing is integrated"
        PASSES=$((PASSES + 1))
    else
        echo -e "  ${RED}✗ FAIL: QA image storage not in single ticket workflow${NC}"
        echo "    Missing flags: --qa-before, --qa-after, --screenshot"
        echo "    Batch processing QA improvements not available for single tickets"
        echo ""
        echo "    Impact: Must use batch workflow even for single ticket QA"
        FAILURES=$((FAILURES + 1))
    fi
else
    echo -e "  ${RED}✗ FAIL: manage-notion-ticket.sh not found${NC}"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# ============================================
# SUMMARY: Required QA Fields
# ============================================
echo "========================================"
echo "REQUIRED QA FIELDS (Missing from Notion)"
echo "========================================"
echo ""

echo "The following fields should be added to the Tickets database:"
echo ""
echo "  1. QA Status (Select)"
echo "     Options: Pending QA, QA In Progress, QA Passed, QA Failed, QA Skipped"
echo ""
echo "  2. QA Approved By (Person)"
echo "     Who performed the QA verification"
echo ""
echo "  3. QA Completed Time (Date)"
echo "     When QA was performed"
echo ""
echo "  4. Staging Preview URL (URL)"
echo "     Link to preview the changes"
echo ""
echo "  5. QA Evidence (Files)"
echo "     Screenshots, recordings, or other proof"
echo ""
echo "  6. QA Notes (Rich Text)"
echo "     Observations, issues found, feedback"
echo ""
echo "  7. QA Environment (Multi-select)"
echo "     Browser, device, viewport tested"
echo ""
echo "  8. QA Batch ID (Text)"
echo "     Groups tickets QA'd together"
echo ""

# ============================================
# RESULTS
# ============================================
echo "========================================"
echo "RESULTS: QA Process Recording"
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

echo "QA Infrastructure: $PERCENT% complete"
echo ""

if [ "$FAILURES" -gt 0 ]; then
    echo -e "${RED}TEST FAILED: QA process cannot be recorded in Notion${NC}"
    echo ""
    echo "Impact:"
    echo "  - No proof that changes were verified before completion"
    echo "  - No accountability for QA sign-off"
    echo "  - No audit trail for client review"
    echo "  - Cannot track QA coverage across batches"
    echo "  - Debugging regressions is harder (was it ever tested?)"
    echo "  - QA improvements from batch processing not in single ticket workflow"
    echo ""
    echo "Current Notion fields lack:"
    for field in "QA Status" "QA Approved By" "QA Timestamp" "Staging Preview URL" "QA Evidence" "QA Notes" "QA Environment" "QA Batch ID"; do
        if ! echo "$PROPERTIES" | grep -qi "$(echo $field | sed 's/ /.*/')"; then
            echo "  □ $field"
        fi
    done
    echo ""
    exit 1
else
    echo -e "${GREEN}TEST PASSED: QA process recording is available${NC}"
    exit 0
fi
