#!/bin/bash
# quote-workflow.sh - Complete quote analysis workflow (Firestore-backed)
# Compares new tickets against completed git commits to identify duplicates
#
# Usage: ./quote-workflow.sh START_NUM END_NUM [--skip-fetch]
# Example: ./quote-workflow.sh 1506 1695
#
# Steps:
#   1. Extracts completed tickets from git history (30 days)
#   2. Identifies new tickets not in git
#   3. Fetches ticket details from Firestore (can be slow)
#   4. Compares and generates similarity report

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
SKIP_FETCH=false
START_NUM=""
END_NUM=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-fetch)
            SKIP_FETCH=true
            shift
            ;;
        *)
            if [ -z "$START_NUM" ]; then
                START_NUM=$1
            elif [ -z "$END_NUM" ]; then
                END_NUM=$1
            fi
            shift
            ;;
    esac
done

if [ -z "$START_NUM" ] || [ -z "$END_NUM" ]; then
    echo -e "${BOLD}Quote Analysis Workflow${NC}"
    echo ""
    echo "Usage: $0 START_NUM END_NUM [--skip-fetch]"
    echo ""
    echo "Examples:"
    echo "  $0 1506 1695              # Full analysis"
    echo "  $0 1506 1695 --skip-fetch # Skip fetch (use cached)"
    exit 1
fi

echo ""
echo -e "${BOLD}${BLUE}========================================${NC}"
echo -e "${BOLD}${BLUE}  QUOTE ANALYSIS WORKFLOW${NC}"
echo -e "${BOLD}${BLUE}  TICK-$START_NUM to TICK-$END_NUM${NC}"
echo -e "${BOLD}${BLUE}========================================${NC}"
echo ""

# Step 1: Run analyzer to identify completed vs new
echo -e "${CYAN}Step 1/3: Analyzing git history...${NC}"
"$SCRIPT_DIR/quote-analyzer.sh" "$START_NUM" "$END_NUM"
echo ""

# Step 2: Fetch from Firestore (unless skipped)
if [ "$SKIP_FETCH" = true ]; then
    echo -e "${YELLOW}Step 2/3: Skipping fetch (using cached data)${NC}"
else
    echo -e "${CYAN}Step 2/3: Fetching ticket details from Firestore...${NC}"
    echo ""
    "$SCRIPT_DIR/quote-batch-fetch.sh"
fi
echo ""

# Step 3: Compare and generate report
echo -e "${CYAN}Step 3/3: Comparing tickets and generating report...${NC}"
"$SCRIPT_DIR/quote-compare.sh"
echo ""

echo -e "${GREEN}${BOLD}========================================${NC}"
echo -e "${GREEN}${BOLD}  WORKFLOW COMPLETE${NC}"
echo -e "${GREEN}${BOLD}========================================${NC}"
echo ""
echo "Reports saved to: /tmp/quote-analysis/"
echo ""
echo "Key files:"
echo "  - quote-analysis-*.md     Initial git analysis"
echo "  - QUOTE-REPORT-*.md       Final similarity report"
echo ""
