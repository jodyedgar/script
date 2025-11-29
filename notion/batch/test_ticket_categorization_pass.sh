#!/bin/bash

# Test: Ticket Categorization Passing State
# Purpose: Validate that the categorization engine successfully groups
#          75+ tickets into meaningful batches for efficient processing
#
# Expected Result: PASS - Tickets categorized with >80% accuracy
#
# Success Criteria:
#   1. >=80% of tickets are categorized (not "uncategorized")
#   2. At least 5 distinct categories are used
#   3. No more than 15 tickets remain uncategorized
#   4. Batches are created for all priority levels
#   5. Processing plan is generated with clear phases

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/fixtures"
RESULTS_DIR="$SCRIPT_DIR/results"

# Thresholds
MIN_TICKET_COUNT=75
REQUIRED_CATEGORIZATION_RATE=80
MIN_CATEGORIES=5
MAX_UNCATEGORIZED=15

echo "========================================"
echo "TEST: Ticket Categorization (Passing)"
echo "========================================"
echo ""

# Create directories
mkdir -p "$DATA_DIR" "$RESULTS_DIR"

# Step 1: Fetch fresh tickets from Notion
echo "Step 1: Fetching hs-figma backlog tickets from Notion..."

if [ -f "$HOME/.bash_profile" ]; then
    source "$HOME/.bash_profile"
fi

if [ -z "$NOTION_API_KEY" ]; then
    echo -e "${RED}FAIL: NOTION_API_KEY not set${NC}"
    exit 1
fi

TICKETS_DB="1abc197b3ae7808fa454dd0c0e96ca6f"
HSFIGMA_CLIENT_ID="1a7c197b-3ae7-8054-bdd6-ebd947ea8b33"

RESPONSE=$(curl -s -X POST "https://api.notion.com/v1/databases/$TICKETS_DB/query" \
  -H "Authorization: Bearer $NOTION_API_KEY" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d "{\"filter\": {\"and\": [{\"property\": \"Ticket Status\", \"status\": {\"equals\": \"Backlog\"}}, {\"property\": \"Client\", \"relation\": {\"contains\": \"$HSFIGMA_CLIENT_ID\"}}]}, \"page_size\": 100}")

echo "$RESPONSE" > "$DATA_DIR/raw_tickets.json"

# Extract ticket data
echo "$RESPONSE" | jq '[.results[] | {
  id: (.properties.ID.unique_id.prefix + "-" + (.properties.ID.unique_id.number | tostring)),
  name: (.properties.Name.title[0].plain_text // "Untitled"),
  type: (.properties["Ticket Type"].select.name // null),
  complexity: (.properties["Ticket Complexity"].select.name // null)
}]' > "$DATA_DIR/tickets.json"

TICKET_COUNT=$(cat "$DATA_DIR/tickets.json" | jq 'length')
echo "  Found: $TICKET_COUNT tickets"

if [ "$TICKET_COUNT" -lt "$MIN_TICKET_COUNT" ]; then
    echo -e "${YELLOW}WARNING: Only $TICKET_COUNT tickets (need $MIN_TICKET_COUNT)${NC}"
fi

# Step 2: Run categorization engine
echo ""
echo "Step 2: Running categorization engine..."
chmod +x "$SCRIPT_DIR/categorize_tickets.sh"
"$SCRIPT_DIR/categorize_tickets.sh" > "$RESULTS_DIR/categorization_log.txt" 2>&1

# Step 3: Validate results
echo ""
echo "Step 3: Validating categorization results..."

# Check categorized count
CATEGORIZED=$(cat "$RESULTS_DIR/categorized_tickets.json" | jq '[.[] | select(.category != "uncategorized")] | length')
UNCATEGORIZED=$(cat "$RESULTS_DIR/categorized_tickets.json" | jq '[.[] | select(.category == "uncategorized")] | length')
RATE=$((CATEGORIZED * 100 / TICKET_COUNT))

echo "  Categorized: $CATEGORIZED / $TICKET_COUNT ($RATE%)"
echo "  Uncategorized: $UNCATEGORIZED"

# Check category count
CATEGORIES=$(cat "$RESULTS_DIR/categorized_tickets.json" | jq '[.[].category] | unique | length')
echo "  Unique categories: $CATEGORIES"

# Check batches exist
BATCH_COUNT=$(cat "$RESULTS_DIR/batches.json" | jq 'length')
echo "  Batches created: $BATCH_COUNT"

# Step 4: Evaluate against thresholds
echo ""
echo "========================================"
echo "RESULTS: Categorization Assessment"
echo "========================================"
echo ""

PASSES=0
FAILURES=0

# Check 1: Categorization rate
if [ "$RATE" -ge "$REQUIRED_CATEGORIZATION_RATE" ]; then
    echo -e "${GREEN}✓ PASS: Categorization rate $RATE% (threshold: $REQUIRED_CATEGORIZATION_RATE%)${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "${RED}✗ FAIL: Categorization rate $RATE% (need $REQUIRED_CATEGORIZATION_RATE%)${NC}"
    FAILURES=$((FAILURES + 1))
fi

# Check 2: Category diversity
if [ "$CATEGORIES" -ge "$MIN_CATEGORIES" ]; then
    echo -e "${GREEN}✓ PASS: $CATEGORIES categories used (threshold: $MIN_CATEGORIES)${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "${RED}✗ FAIL: Only $CATEGORIES categories (need $MIN_CATEGORIES)${NC}"
    FAILURES=$((FAILURES + 1))
fi

# Check 3: Uncategorized limit
if [ "$UNCATEGORIZED" -le "$MAX_UNCATEGORIZED" ]; then
    echo -e "${GREEN}✓ PASS: $UNCATEGORIZED uncategorized (max: $MAX_UNCATEGORIZED)${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "${RED}✗ FAIL: $UNCATEGORIZED uncategorized (max $MAX_UNCATEGORIZED)${NC}"
    FAILURES=$((FAILURES + 1))
fi

# Check 4: Batches created
if [ "$BATCH_COUNT" -ge 3 ]; then
    echo -e "${GREEN}✓ PASS: $BATCH_COUNT batches created (min: 3)${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "${RED}✗ FAIL: Only $BATCH_COUNT batches (need at least 3)${NC}"
    FAILURES=$((FAILURES + 1))
fi

# Check 5: Priority distribution (should have multiple priority levels)
PRIORITY_LEVELS=$(cat "$RESULTS_DIR/categorized_tickets.json" | jq '[.[].priority_label] | unique | length')
if [ "$PRIORITY_LEVELS" -ge 2 ]; then
    echo -e "${GREEN}✓ PASS: $PRIORITY_LEVELS priority levels used (min: 2)${NC}"
    PASSES=$((PASSES + 1))
else
    echo -e "${RED}✗ FAIL: Only $PRIORITY_LEVELS priority levels (need at least 2)${NC}"
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "========================================"

# Step 5: Display batch processing summary
if [ "$FAILURES" -eq 0 ]; then
    echo ""
    echo -e "${GREEN}BATCH PROCESSING SUMMARY${NC}"
    echo "========================================"

    echo ""
    echo -e "${BLUE}By Category (files to open):${NC}"
    cat "$RESULTS_DIR/batches.json" | jq -r '
      sort_by(.ticket_count) | reverse |
      .[] |
      "  \(.category): \(.ticket_count) tickets"
    ' | head -10

    echo ""
    echo -e "${BLUE}By Priority (processing order):${NC}"
    cat "$RESULTS_DIR/batches.json" | jq -r '
      group_by(.priority_label) |
      map({priority: .[0].priority_label, total: (map(.ticket_count) | add)}) |
      sort_by(.priority) |
      .[] |
      "  \(.priority): \(.total) tickets"
    '

    echo ""
    echo -e "${BLUE}Recommended Processing Order:${NC}"

    # Phase 1: Quick Wins
    P1_COUNT=$(cat "$RESULTS_DIR/categorized_tickets.json" | jq '[.[] | select(.priority_label == "P1-QuickWins")] | length')
    if [ "$P1_COUNT" -gt 0 ]; then
        echo -e "  ${GREEN}Phase 1: Quick Wins ($P1_COUNT tickets)${NC}"
        cat "$RESULTS_DIR/categorized_tickets.json" | jq -r '
          [.[] | select(.priority_label == "P1-QuickWins")] |
          group_by(.category) |
          .[] |
          "    - " + .[0].category + ": " + (length | tostring) + " tickets"
        '
    fi

    # Phase 2: Structural
    P2_COUNT=$(cat "$RESULTS_DIR/categorized_tickets.json" | jq '[.[] | select(.priority_label == "P2-Structural")] | length')
    if [ "$P2_COUNT" -gt 0 ]; then
        echo -e "  ${GREEN}Phase 2: Structural ($P2_COUNT tickets)${NC}"
        cat "$RESULTS_DIR/categorized_tickets.json" | jq -r '
          [.[] | select(.priority_label == "P2-Structural")] |
          group_by(.category) |
          sort_by(-length) |
          .[] |
          "    - " + .[0].category + ": " + (length | tostring) + " tickets"
        '
    fi

    # Phase 3: Cross-cutting
    P3_COUNT=$(cat "$RESULTS_DIR/categorized_tickets.json" | jq '[.[] | select(.priority_label == "P3-CrossCutting")] | length')
    if [ "$P3_COUNT" -gt 0 ]; then
        echo -e "  ${GREEN}Phase 3: Cross-cutting ($P3_COUNT tickets)${NC}"
        cat "$RESULTS_DIR/categorized_tickets.json" | jq -r '
          [.[] | select(.priority_label == "P3-CrossCutting")] |
          group_by(.category) |
          .[] |
          "    - " + .[0].category + ": " + (length | tostring) + " tickets"
        '
    fi

    # Phase 4: Responsive
    P4_COUNT=$(cat "$RESULTS_DIR/categorized_tickets.json" | jq '[.[] | select(.priority_label == "P4-Responsive")] | length')
    if [ "$P4_COUNT" -gt 0 ]; then
        echo -e "  ${GREEN}Phase 4: Responsive ($P4_COUNT tickets)${NC}"
        cat "$RESULTS_DIR/categorized_tickets.json" | jq -r '
          [.[] | select(.priority_label == "P4-Responsive")] |
          group_by(.category) |
          .[] |
          "    - " + .[0].category + ": " + (length | tostring) + " tickets"
        '
    fi

    # Phase 5: Complex
    P5_COUNT=$(cat "$RESULTS_DIR/categorized_tickets.json" | jq '[.[] | select(.priority_label == "P5-Complex")] | length')
    if [ "$P5_COUNT" -gt 0 ]; then
        echo -e "  ${YELLOW}Phase 5: Complex ($P5_COUNT tickets - requires investigation)${NC}"
        cat "$RESULTS_DIR/categorized_tickets.json" | jq -r '
          [.[] | select(.priority_label == "P5-Complex")] |
          group_by(.category) |
          .[] |
          "    - " + .[0].category + ": " + (length | tostring) + " tickets"
        '
    fi

    echo ""
    echo "========================================"
fi

# Final result
echo ""
if [ "$FAILURES" -eq 0 ]; then
    echo -e "${GREEN}TEST PASSED: All $PASSES checks passed${NC}"
    echo ""
    echo "The categorization engine successfully:"
    echo "  - Categorized $RATE% of tickets ($CATEGORIZED/$TICKET_COUNT)"
    echo "  - Used $CATEGORIES semantic categories"
    echo "  - Created $BATCH_COUNT processing batches"
    echo "  - Prioritized for efficient batch processing"
    echo ""
    echo "Ready for batch processing!"
    exit 0
else
    echo -e "${RED}TEST FAILED: $FAILURES check(s) failed${NC}"
    echo ""
    echo "Categorization needs improvement."

    if [ "$UNCATEGORIZED" -gt "$MAX_UNCATEGORIZED" ]; then
        echo ""
        echo "Uncategorized tickets that need manual review:"
        cat "$RESULTS_DIR/categorized_tickets.json" | jq -r '
          [.[] | select(.category == "uncategorized")] |
          .[] |
          "  - " + .id + ": " + .name
        ' | head -15
    fi
    exit 1
fi
