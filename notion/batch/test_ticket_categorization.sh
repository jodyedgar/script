#!/bin/bash

# Test: Ticket Categorization Failed State
# Purpose: Demonstrate that 75+ backlog tickets cannot be automatically
#          categorized into meaningful groups for batch processing
#
# Expected Result: FAIL - Unable to categorize tickets with >80% confidence
#
# This test validates that we NEED a categorization system before we can
# batch process the backlog effectively.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/fixtures"
RESULTS_DIR="$SCRIPT_DIR/results"

# Thresholds
MIN_TICKET_COUNT=75
REQUIRED_CATEGORIZATION_RATE=80  # 80% of tickets must be categorized
MIN_CATEGORIES=5                  # Need at least 5 distinct categories
MAX_UNCATEGORIZED=15              # Max 15 tickets can be "uncategorized"

echo "========================================"
echo "TEST: Ticket Categorization"
echo "========================================"
echo ""

# Create directories
mkdir -p "$DATA_DIR" "$RESULTS_DIR"

# Step 1: Fetch tickets from Notion
echo "Step 1: Fetching hs-figma backlog tickets from Notion..."

# Source credentials
if [ -f "$HOME/.bash_profile" ]; then
    source "$HOME/.bash_profile"
fi

if [ -z "$NOTION_API_KEY" ]; then
    echo -e "${RED}FAIL: NOTION_API_KEY not set${NC}"
    exit 1
fi

# Notion database and client IDs
TICKETS_DB="1abc197b3ae7808fa454dd0c0e96ca6f"
HSFIGMA_CLIENT_ID="1a7c197b-3ae7-8054-bdd6-ebd947ea8b33"

# Query backlog tickets for hs-figma
RESPONSE=$(curl -s -X POST "https://api.notion.com/v1/databases/$TICKETS_DB/query" \
  -H "Authorization: Bearer $NOTION_API_KEY" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d "{\"filter\": {\"and\": [{\"property\": \"Ticket Status\", \"status\": {\"equals\": \"Backlog\"}}, {\"property\": \"Client\", \"relation\": {\"contains\": \"$HSFIGMA_CLIENT_ID\"}}]}, \"page_size\": 100}")

# Save raw response
echo "$RESPONSE" > "$DATA_DIR/raw_tickets.json"

# Extract ticket count
TICKET_COUNT=$(echo "$RESPONSE" | jq '.results | length')
echo "  Found: $TICKET_COUNT tickets"

# Step 2: Validate we have enough tickets
echo ""
echo "Step 2: Validating ticket count..."
if [ "$TICKET_COUNT" -lt "$MIN_TICKET_COUNT" ]; then
    echo -e "${YELLOW}WARNING: Only $TICKET_COUNT tickets (need $MIN_TICKET_COUNT)${NC}"
fi
echo "  ✓ Have $TICKET_COUNT tickets (threshold: $MIN_TICKET_COUNT)"

# Step 3: Extract structured data for categorization
echo ""
echo "Step 3: Extracting ticket data..."

# Extract ticket data
echo "$RESPONSE" | jq '[.results[] | {
  id: (.properties.ID.unique_id.prefix + "-" + (.properties.ID.unique_id.number | tostring)),
  name: (.properties.Name.title[0].plain_text // "Untitled"),
  type: (.properties["Ticket Type"].select.name // null),
  complexity: (.properties["Ticket Complexity"].select.name // null)
}]' > "$DATA_DIR/tickets.json"

echo "  Saved to: $DATA_DIR/tickets.json"

# Step 4: Attempt automatic categorization using existing metadata
echo ""
echo "Step 4: Attempting automatic categorization..."

# Strategy 1: Categorize by Ticket Type
echo ""
echo "  Strategy 1: Categorize by Ticket Type field"
TYPE_GROUPS=$(cat "$DATA_DIR/tickets.json" | jq -r 'group_by(.type) | map({category: .[0].type, count: length}) | .[] | "\(.category): \(.count)"')
echo "$TYPE_GROUPS" | sed 's/^/    /'

UNIQUE_TYPES=$(echo "$TYPE_GROUPS" | wc -l | tr -d ' ')
echo "  Result: $UNIQUE_TYPES unique type(s)"

if [ "$UNIQUE_TYPES" -lt "$MIN_CATEGORIES" ]; then
    echo -e "  ${RED}✗ FAIL: Not enough categories (need $MIN_CATEGORIES)${NC}"
fi

# Strategy 2: Categorize by Complexity
echo ""
echo "  Strategy 2: Categorize by Complexity field"
COMPLEXITY_GROUPS=$(cat "$DATA_DIR/tickets.json" | jq -r 'group_by(.complexity) | map({category: .[0].complexity, count: length}) | .[] | "\(.category): \(.count)"')
echo "$COMPLEXITY_GROUPS" | sed 's/^/    /'

UNIQUE_COMPLEXITY=$(echo "$COMPLEXITY_GROUPS" | wc -l | tr -d ' ')
echo "  Result: $UNIQUE_COMPLEXITY unique complexity level(s)"

if [ "$UNIQUE_COMPLEXITY" -lt "$MIN_CATEGORIES" ]; then
    echo -e "  ${RED}✗ FAIL: Not enough categories (need $MIN_CATEGORIES)${NC}"
fi

# Strategy 3: Keyword extraction from titles (naive approach)
echo ""
echo "  Strategy 3: Keyword extraction from ticket names"

# Common UI component keywords to look for
declare -a KEYWORDS=("header" "footer" "nav" "pdp" "cart" "bag" "mobile" "desktop" "spacing" "font" "button" "icon" "image" "grid" "collection" "homepage" "breadcrumb" "modal" "dropdown")

echo "" > "$RESULTS_DIR/keyword_matches.txt"
CATEGORIZED=0
UNCATEGORIZED=0

while read -r ticket; do
    name=$(echo "$ticket" | jq -r '.name' | tr '[:upper:]' '[:lower:]')
    id=$(echo "$ticket" | jq -r '.id')
    matched=false

    for keyword in "${KEYWORDS[@]}"; do
        if [[ "$name" == *"$keyword"* ]]; then
            echo "$id: $keyword" >> "$RESULTS_DIR/keyword_matches.txt"
            matched=true
            break
        fi
    done

    if [ "$matched" = true ]; then
        CATEGORIZED=$((CATEGORIZED + 1))
    else
        UNCATEGORIZED=$((UNCATEGORIZED + 1))
        echo "$id: UNCATEGORIZED - $name" >> "$RESULTS_DIR/uncategorized.txt"
    fi
done < <(cat "$DATA_DIR/tickets.json" | jq -c '.[]')

CATEGORIZATION_RATE=$((CATEGORIZED * 100 / TICKET_COUNT))

echo "    Categorized: $CATEGORIZED tickets"
echo "    Uncategorized: $UNCATEGORIZED tickets"
echo "    Rate: $CATEGORIZATION_RATE%"

# Show uncategorized tickets
echo ""
echo "  Uncategorized tickets:"
if [ -f "$RESULTS_DIR/uncategorized.txt" ]; then
    head -10 "$RESULTS_DIR/uncategorized.txt" | sed 's/^/    /'
    REMAINING=$((UNCATEGORIZED - 10))
    if [ "$REMAINING" -gt 0 ]; then
        echo "    ... and $REMAINING more"
    fi
fi

# Step 5: Evaluate categorization quality
echo ""
echo "========================================"
echo "RESULTS: Categorization Assessment"
echo "========================================"
echo ""

FAILURES=0

# Check 1: Do we have enough categories?
if [ "$UNIQUE_TYPES" -lt "$MIN_CATEGORIES" ]; then
    echo -e "${RED}✗ FAIL: Ticket Type provides only $UNIQUE_TYPES categories (need $MIN_CATEGORIES)${NC}"
    FAILURES=$((FAILURES + 1))
else
    echo -e "${GREEN}✓ PASS: Ticket Type categories${NC}"
fi

# Check 2: Is categorization rate high enough?
if [ "$CATEGORIZATION_RATE" -lt "$REQUIRED_CATEGORIZATION_RATE" ]; then
    echo -e "${RED}✗ FAIL: Keyword categorization rate is $CATEGORIZATION_RATE% (need $REQUIRED_CATEGORIZATION_RATE%)${NC}"
    FAILURES=$((FAILURES + 1))
else
    echo -e "${GREEN}✓ PASS: Categorization rate${NC}"
fi

# Check 3: Are too many tickets uncategorized?
if [ "$UNCATEGORIZED" -gt "$MAX_UNCATEGORIZED" ]; then
    echo -e "${RED}✗ FAIL: $UNCATEGORIZED tickets uncategorized (max $MAX_UNCATEGORIZED)${NC}"
    FAILURES=$((FAILURES + 1))
else
    echo -e "${GREEN}✓ PASS: Uncategorized count${NC}"
fi

echo ""
echo "========================================"

if [ "$FAILURES" -gt 0 ]; then
    echo -e "${RED}TEST FAILED: $FAILURES check(s) failed${NC}"
    echo ""
    echo "Conclusion: Cannot automatically categorize $TICKET_COUNT tickets"
    echo "for efficient batch processing."
    echo ""
    echo "Next Steps:"
    echo "  1. Define semantic categories (e.g., Header, PDP, Cart, Mobile)"
    echo "  2. Implement AI-assisted categorization using ticket descriptions"
    echo "  3. Build a categorization pipeline that achieves >80% accuracy"
    echo ""
    exit 1
else
    echo -e "${GREEN}TEST PASSED: All checks passed${NC}"
    exit 0
fi
