#!/bin/bash
# quote-analyzer.sh - Compare new tickets against completed work to flag duplicates
# Usage: ./quote-analyzer.sh START_NUM END_NUM
# Example: ./quote-analyzer.sh 1506 1695

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="/Users/jodyedgar/Dropbox/wwwroot/store.figma.com/shopify-the-figma-store/horizon"
OUTPUT_DIR="/tmp/quote-analysis"
COMMITS_FILE="$OUTPUT_DIR/completed_commits.txt"
COMPLETED_TICKETS_FILE="$OUTPUT_DIR/completed_tickets.txt"
REPORT_FILE="$OUTPUT_DIR/quote-analysis-$(date +%Y%m%d-%H%M%S).md"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Validate arguments
if [ $# -lt 2 ]; then
    echo -e "${RED}Usage: $0 START_NUM END_NUM${NC}"
    echo "Example: $0 1506 1695"
    exit 1
fi

START_NUM=$1
END_NUM=$2

echo -e "${BLUE}=== Quote Analyzer ===${NC}"
echo "Analyzing tickets TICK-$START_NUM through TICK-$END_NUM"
echo ""

# Step 1: Extract completed tickets from git
echo -e "${YELLOW}Step 1: Extracting completed tickets from git history (last 30 days)...${NC}"
git -C "$PROJECT_DIR" log --since="30 days ago" --pretty=format:"%s" | grep -E '^TICK-' > "$COMMITS_FILE" 2>/dev/null || true
git -C "$PROJECT_DIR" log --since="30 days ago" --pretty=format:"%s" | grep -oE 'TICK-[0-9]+' | sort -t'-' -k2 -n | uniq > "$COMPLETED_TICKETS_FILE"

COMPLETED_COUNT=$(wc -l < "$COMPLETED_TICKETS_FILE" | tr -d ' ')
echo -e "${GREEN}Found $COMPLETED_COUNT completed tickets in git history${NC}"
echo ""

# Step 2: Initialize report
echo -e "${YELLOW}Step 2: Generating analysis report...${NC}"

cat > "$REPORT_FILE" << 'HEADER'
# Quote Analysis Report

**Generated:** REPORT_DATE
**Range Analyzed:** TICK-START_NUM to TICK-END_NUM

## Summary

This report compares new tickets against completed work from the last 30 days to identify potential duplicates that should not be billed.

---

## Legend

- **ALREADY COMPLETED** - Exact ticket number found in git commits (DO NOT BILL)
- **POTENTIALLY SIMILAR** - Keywords match completed work (REVIEW CAREFULLY)
- **NEW WORK** - No matches found (BILLABLE)

---

## Analysis Results

HEADER

# Replace placeholders
sed -i '' "s/REPORT_DATE/$(date '+%Y-%m-%d %H:%M:%S')/" "$REPORT_FILE"
sed -i '' "s/START_NUM/$START_NUM/" "$REPORT_FILE"
sed -i '' "s/END_NUM/$END_NUM/" "$REPORT_FILE"

# Counters
ALREADY_COMPLETED=0
POTENTIALLY_SIMILAR=0
NEW_WORK=0
SKIPPED=0

# Keywords to match for semantic comparison
KEYWORDS="padding|margin|spacing|font|size|mobile|desktop|hover|button|cart|bag|checkout|header|footer|nav|menu|filter|sort|grid|layout|breadcrumb|PDP|product|collection|hero|animation|FAQ|contact|newsletter|color|opacity|width|height"

echo "" >> "$REPORT_FILE"
echo "### Already Completed (DO NOT BILL)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "| Ticket | Matching Commit |" >> "$REPORT_FILE"
echo "|--------|-----------------|" >> "$REPORT_FILE"

# Step 3: Analyze each ticket
for NUM in $(seq $START_NUM $END_NUM); do
    TICKET="TICK-$NUM"

    # Check if exact match in completed tickets
    if grep -q "^$TICKET$" "$COMPLETED_TICKETS_FILE" 2>/dev/null; then
        # Get the commit message for this ticket
        COMMIT_MSG=$(grep "^$TICKET" "$COMMITS_FILE" | head -1)
        echo "| $TICKET | $COMMIT_MSG |" >> "$REPORT_FILE"
        ((ALREADY_COMPLETED++))
    fi
done

# Now check for tickets NOT in completed list
echo "" >> "$REPORT_FILE"
echo "### Tickets to Fetch from Notion" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "The following tickets were not found in git history and need to be fetched from Notion for comparison:" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

NOT_COMPLETED_FILE="$OUTPUT_DIR/not_completed.txt"
> "$NOT_COMPLETED_FILE"

for NUM in $(seq $START_NUM $END_NUM); do
    TICKET="TICK-$NUM"
    if ! grep -q "^$TICKET$" "$COMPLETED_TICKETS_FILE" 2>/dev/null; then
        echo "$TICKET" >> "$NOT_COMPLETED_FILE"
    fi
done

NOT_COMPLETED_COUNT=$(wc -l < "$NOT_COMPLETED_FILE" | tr -d ' ')
echo "**$NOT_COMPLETED_COUNT tickets** need Notion lookup for semantic comparison." >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "Run the following to fetch and analyze these tickets:" >> "$REPORT_FILE"
echo '```bash' >> "$REPORT_FILE"
echo "cat $NOT_COMPLETED_FILE" >> "$REPORT_FILE"
echo '```' >> "$REPORT_FILE"

# Summary
TOTAL=$((END_NUM - START_NUM + 1))
echo "" >> "$REPORT_FILE"
echo "---" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "## Quick Summary" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "| Category | Count |" >> "$REPORT_FILE"
echo "|----------|-------|" >> "$REPORT_FILE"
echo "| Total tickets in range | $TOTAL |" >> "$REPORT_FILE"
echo "| Already completed (exact match) | $ALREADY_COMPLETED |" >> "$REPORT_FILE"
echo "| Need Notion lookup | $NOT_COMPLETED_COUNT |" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "### Completed Tickets Reference" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "All tickets completed in the last 30 days:" >> "$REPORT_FILE"
echo '```' >> "$REPORT_FILE"
cat "$COMPLETED_TICKETS_FILE" >> "$REPORT_FILE"
echo '```' >> "$REPORT_FILE"

echo ""
echo -e "${GREEN}=== Analysis Complete ===${NC}"
echo ""
echo -e "Report saved to: ${BLUE}$REPORT_FILE${NC}"
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "  Total tickets in range: $TOTAL"
echo "  Already completed: $ALREADY_COMPLETED"
echo "  Need Notion lookup: $NOT_COMPLETED_COUNT"
echo ""
echo -e "${BLUE}Next step: Review the report and fetch ticket details from Notion${NC}"
