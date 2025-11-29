#!/bin/bash

# Ticket Categorization Engine
# Categorizes tickets based on rules and generates prioritized batches
#
# Usage: ./categorize_tickets.sh [--input tickets.json] [--output categorized.json]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_FILE="$SCRIPT_DIR/categorization_rules.json"
INPUT_FILE="${1:-$SCRIPT_DIR/fixtures/tickets.json}"
OUTPUT_DIR="$SCRIPT_DIR/results"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================"
echo "Ticket Categorization Engine"
echo "========================================"
echo ""

mkdir -p "$OUTPUT_DIR"

# Load categorization rules
if [ ! -f "$RULES_FILE" ]; then
    echo "Error: Rules file not found: $RULES_FILE"
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file not found: $INPUT_FILE"
    exit 1
fi

TICKET_COUNT=$(cat "$INPUT_FILE" | jq 'length')
echo "Processing $TICKET_COUNT tickets..."
echo ""

# Create categorization script using jq
# This applies keyword matching from the rules
cat > /tmp/categorize.jq << 'JQSCRIPT'
# Load rules
def categorize_ticket(name; rules):
  name | ascii_downcase |
  if test("header|nav|menu|search|logo|announcement") then "header-nav"
  elif test("footer|newsletter|copyright|social") then "footer"
  elif test("homepage|hero|cascade|crosslink|landing") then "homepage"
  elif test("pdp|product|variant|size|add to bag|add to cart|sold out|inventory|swatch|cta") then "pdp"
  elif test("cart|bag|checkout|discount|empty bag") then "cart"
  elif test("collection|filter|sort|shop all|featured") then "collection"
  elif test("breadcrumb") then "breadcrumb"
  elif test("modal|dropdown|quick add|popup|overlay|size guide") then "modals"
  elif test("icon|svg|blurry|arrow|chevron") then "icons-images"
  elif test("spacing|padding|margin|gap|width|height|position") then "spacing-layout"
  elif test("font|text|typography") then "typography"
  elif test("about|contact|policy|privacy|terms|404|login|register|account") then "pages"
  elif test("mobile|responsive|tablet|viewport|touch|swipe") then "mobile"
  elif test("animation|hover|transition|fade|flash|effect") then "animation"
  elif test("image|photo|picture") then "icons-images"
  elif test("button|link|underline") then "pdp"
  elif test("grid|layout") then "collection"
  else "uncategorized"
  end;

def priority_base(category):
  if category == "breadcrumb" or category == "icons-images" then 1
  elif category == "header-nav" or category == "footer" or category == "homepage" or category == "pdp" or category == "cart" or category == "collection" or category == "pages" then 2
  elif category == "modals" or category == "spacing-layout" or category == "typography" or category == "animation" then 3
  elif category == "mobile" then 4
  else 5
  end;

def complexity_modifier(complexity):
  if complexity == "Quick Fix" then -1
  elif complexity == "Small Task" then 0
  elif complexity == "Medium Task" then 1
  else 2
  end;

def priority_label(priority):
  if priority <= 1 then "P1-QuickWins"
  elif priority == 2 then "P2-Structural"
  elif priority == 3 then "P3-CrossCutting"
  elif priority == 4 then "P4-Responsive"
  else "P5-Complex"
  end;

[.[] |
  . as $ticket |
  categorize_ticket(.name; null) as $category |
  priority_base($category) as $base |
  complexity_modifier(.complexity // "Small Task") as $mod |
  ([$base + $mod, 1] | max) as $priority |
  {
    id: .id,
    name: .name,
    type: .type,
    complexity: .complexity,
    category: $category,
    priority: $priority,
    priority_label: priority_label($priority),
    batch_key: ($category + "-" + priority_label($priority))
  }
] | sort_by(.priority, .category, .complexity)
JQSCRIPT

# Run categorization
echo "Applying categorization rules..."
cat "$INPUT_FILE" | jq -f /tmp/categorize.jq > "$OUTPUT_DIR/categorized_tickets.json"

# Generate statistics
echo ""
echo -e "${BLUE}Category Distribution:${NC}"
cat "$OUTPUT_DIR/categorized_tickets.json" | jq -r '
  group_by(.category) |
  map({category: .[0].category, count: length}) |
  sort_by(-.count) |
  .[] |
  "  \(.category): \(.count)"
'

echo ""
echo -e "${BLUE}Priority Distribution:${NC}"
cat "$OUTPUT_DIR/categorized_tickets.json" | jq -r '
  group_by(.priority_label) |
  map({priority: .[0].priority_label, count: length}) |
  sort_by(.priority) |
  .[] |
  "  \(.priority): \(.count)"
'

# Check uncategorized
UNCATEGORIZED=$(cat "$OUTPUT_DIR/categorized_tickets.json" | jq '[.[] | select(.category == "uncategorized")] | length')
echo ""
echo "Uncategorized tickets: $UNCATEGORIZED"

# Generate batches
echo ""
echo -e "${BLUE}Generating Processing Batches...${NC}"

cat "$OUTPUT_DIR/categorized_tickets.json" | jq '
  group_by(.batch_key) |
  map({
    batch_key: .[0].batch_key,
    category: .[0].category,
    priority_label: .[0].priority_label,
    ticket_count: length,
    tickets: [.[] | {id: .id, name: .name, complexity: .complexity}]
  }) |
  sort_by(.tickets[0].priority // 5)
' > "$OUTPUT_DIR/batches.json"

# Display batch summary
echo ""
cat "$OUTPUT_DIR/batches.json" | jq -r '.[] | "  [\(.priority_label)] \(.category): \(.ticket_count) tickets"'

# Generate batch processing plan
echo ""
echo -e "${GREEN}========================================"
echo "BATCH PROCESSING PLAN"
echo "========================================${NC}"

# P1 - Quick Wins first
echo ""
echo -e "${GREEN}Phase 1: Quick Wins (build momentum)${NC}"
cat "$OUTPUT_DIR/batches.json" | jq -r '
  [.[] | select(.priority_label == "P1-QuickWins")] |
  if length > 0 then
    .[] | "  - \(.category): \(.ticket_count) tickets"
  else
    "  (none)"
  end
'

# P2 - Structural by component
echo ""
echo -e "${GREEN}Phase 2: Structural (by component)${NC}"
cat "$OUTPUT_DIR/batches.json" | jq -r '
  [.[] | select(.priority_label == "P2-Structural")] |
  sort_by(.ticket_count) | reverse |
  if length > 0 then
    .[] | "  - \(.category): \(.ticket_count) tickets"
  else
    "  (none)"
  end
'

# P3 - Cross-cutting
echo ""
echo -e "${GREEN}Phase 3: Cross-cutting (spacing, typography)${NC}"
cat "$OUTPUT_DIR/batches.json" | jq -r '
  [.[] | select(.priority_label == "P3-CrossCutting")] |
  if length > 0 then
    .[] | "  - \(.category): \(.ticket_count) tickets"
  else
    "  (none)"
  end
'

# P4 - Responsive
echo ""
echo -e "${GREEN}Phase 4: Responsive (mobile fixes)${NC}"
cat "$OUTPUT_DIR/batches.json" | jq -r '
  [.[] | select(.priority_label == "P4-Responsive")] |
  if length > 0 then
    .[] | "  - \(.category): \(.ticket_count) tickets"
  else
    "  (none)"
  end
'

# P5 - Complex
echo ""
echo -e "${GREEN}Phase 5: Complex (requires investigation)${NC}"
cat "$OUTPUT_DIR/batches.json" | jq -r '
  [.[] | select(.priority_label == "P5-Complex")] |
  if length > 0 then
    .[] | "  - \(.category): \(.ticket_count) tickets"
  else
    "  (none)"
  end
'

echo ""
echo "========================================"
echo "Output files:"
echo "  - $OUTPUT_DIR/categorized_tickets.json"
echo "  - $OUTPUT_DIR/batches.json"
echo "========================================"

# Return stats for testing
CATEGORIZED=$((TICKET_COUNT - UNCATEGORIZED))
RATE=$((CATEGORIZED * 100 / TICKET_COUNT))
CATEGORIES=$(cat "$OUTPUT_DIR/categorized_tickets.json" | jq '[.[].category] | unique | length')

echo ""
echo "Summary:"
echo "  Total tickets: $TICKET_COUNT"
echo "  Categorized: $CATEGORIZED ($RATE%)"
echo "  Categories used: $CATEGORIES"
echo "  Uncategorized: $UNCATEGORIZED"
