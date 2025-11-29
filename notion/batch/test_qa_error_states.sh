#!/bin/bash

# Test: QA Process Error States
# Purpose: Identify tickets that cannot complete the QA workflow due to missing data
#
# Error conditions checked:
#   1. No Feedbucket media attached to ticket
#   2. No page URL for Chrome MCP to screenshot
#   3. Ticket missing required fields for QA
#   4. Both QA fields missing data
#   5. Feedbucket media type detection (PNG, JPG, Video)
#
# This test helps identify tickets that need manual intervention

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"

# Notion config
TICKETS_DATABASE_ID="1abc197b3ae7808fa454dd0c0e96ca6f"
HS_FIGMA_CLIENT_ID="1a7c197b-3ae7-8054-bdd6-ebd947ea8b33"

echo "========================================"
echo "TEST: QA Error States Detection"
echo "========================================"
echo ""
echo "Checking for tickets that cannot complete QA workflow"
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

# ============================================
# Fetch all backlog tickets for hs-figma
# ============================================
echo "Fetching backlog tickets for hs-figma..."

# Build filter for backlog tickets with hs-figma client
FILTER='{
  "and": [
    {
      "property": "Ticket Status",
      "status": {
        "equals": "Backlog"
      }
    },
    {
      "property": "Client",
      "relation": {
        "contains": "'"$HS_FIGMA_CLIENT_ID"'"
      }
    }
  ]
}'

# Fetch tickets
RESPONSE=$(curl -s -X POST "https://api.notion.com/v1/databases/$TICKETS_DATABASE_ID/query" \
  -H "Authorization: Bearer $NOTION_API_KEY" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d "{\"filter\": $FILTER, \"page_size\": 100}")

# Save response
echo "$RESPONSE" > "$RESULTS_DIR/qa_error_check_tickets.json"

TOTAL_TICKETS=$(echo "$RESPONSE" | jq '.results | length')
echo "Total backlog tickets: $TOTAL_TICKETS"
echo ""

# ============================================
# ERROR STATE 1: No Feedbucket Media
# ============================================
echo -e "${BLUE}Error State 1: Missing Feedbucket Media${NC}"
echo "Checking which tickets have no Feedbucket screenshot or video..."
echo ""

# Check each ticket for Feedbucket media in content
NO_FEEDBUCKET=0
NO_FEEDBUCKET_LIST=""

# Media type tracking
TICKETS_WITH_PNG=0
TICKETS_WITH_JPG=0
TICKETS_WITH_VIDEO=0
TICKETS_WITH_OTHER_IMAGE=0

PNG_TICKETS=""
JPG_TICKETS=""
VIDEO_TICKETS=""

# Get ticket IDs
TICKET_IDS=$(echo "$RESPONSE" | jq -r '.results[].id')

for PAGE_ID in $TICKET_IDS; do
    # Get ticket name for display
    TICKET_NAME=$(echo "$RESPONSE" | jq -r --arg id "$PAGE_ID" '.results[] | select(.id == $id) | .properties.ID.unique_id.prefix + "-" + (.properties.ID.unique_id.number | tostring)')

    # Fetch page content blocks
    BLOCKS=$(curl -s -X GET "https://api.notion.com/v1/blocks/$PAGE_ID/children?page_size=100" \
      -H "Authorization: Bearer $NOTION_API_KEY" \
      -H "Notion-Version: 2022-06-28")

    # Extract all Feedbucket URLs from blocks
    FEEDBUCKET_URLS=$(echo "$BLOCKS" | jq -r '
        [.results[].image?.external?.url // "",
         .results[].image?.file?.url // "",
         .results[].video?.external?.url // "",
         .results[].video?.file?.url // "",
         .results[].embed?.url // ""]
        | map(select(. != "" and test("feedbucket|cdn.feedbucket"; "i")))
        | .[]' 2>/dev/null || echo "")

    # Also check Files & URLs property
    FILES_URLS_CONTENT=$(echo "$RESPONSE" | jq -r --arg id "$PAGE_ID" '.results[] | select(.id == $id) | .properties["Files & URLs"].files[]?.external?.url // ""' 2>/dev/null | grep -i "feedbucket" || echo "")

    # Combine all URLs
    ALL_FEEDBUCKET_URLS="$FEEDBUCKET_URLS"$'\n'"$FILES_URLS_CONTENT"

    # Count total Feedbucket media
    TOTAL_FEEDBUCKET=$(echo "$ALL_FEEDBUCKET_URLS" | grep -ci "feedbucket" 2>/dev/null || echo "0")
    TOTAL_FEEDBUCKET=$(echo "${TOTAL_FEEDBUCKET:-0}" | tr -d '[:space:]')
    [[ "$TOTAL_FEEDBUCKET" =~ ^[0-9]+$ ]] || TOTAL_FEEDBUCKET=0

    if [ "$TOTAL_FEEDBUCKET" -eq 0 ]; then
        NO_FEEDBUCKET=$((NO_FEEDBUCKET + 1))
        NO_FEEDBUCKET_LIST="$NO_FEEDBUCKET_LIST$TICKET_NAME\n"
    else
        # Detect media types
        HAS_PNG=$(echo "$ALL_FEEDBUCKET_URLS" | grep -ci "\.png" 2>/dev/null || echo "0")
        HAS_JPG=$(echo "$ALL_FEEDBUCKET_URLS" | grep -ciE "\.(jpg|jpeg)" 2>/dev/null || echo "0")
        HAS_VIDEO=$(echo "$ALL_FEEDBUCKET_URLS" | grep -ciE "\.(mp4|webm|mov|avi|mkv)" 2>/dev/null || echo "0")
        HAS_GIF=$(echo "$ALL_FEEDBUCKET_URLS" | grep -ci "\.gif" 2>/dev/null || echo "0")

        # Clean values
        HAS_PNG=$(echo "${HAS_PNG:-0}" | tr -d '[:space:]')
        HAS_JPG=$(echo "${HAS_JPG:-0}" | tr -d '[:space:]')
        HAS_VIDEO=$(echo "${HAS_VIDEO:-0}" | tr -d '[:space:]')
        HAS_GIF=$(echo "${HAS_GIF:-0}" | tr -d '[:space:]')

        [[ "$HAS_PNG" =~ ^[0-9]+$ ]] || HAS_PNG=0
        [[ "$HAS_JPG" =~ ^[0-9]+$ ]] || HAS_JPG=0
        [[ "$HAS_VIDEO" =~ ^[0-9]+$ ]] || HAS_VIDEO=0
        [[ "$HAS_GIF" =~ ^[0-9]+$ ]] || HAS_GIF=0

        if [ "$HAS_PNG" -gt 0 ]; then
            TICKETS_WITH_PNG=$((TICKETS_WITH_PNG + 1))
            PNG_TICKETS="$PNG_TICKETS$TICKET_NAME\n"
        fi
        if [ "$HAS_JPG" -gt 0 ]; then
            TICKETS_WITH_JPG=$((TICKETS_WITH_JPG + 1))
            JPG_TICKETS="$JPG_TICKETS$TICKET_NAME\n"
        fi
        if [ "$HAS_VIDEO" -gt 0 ]; then
            TICKETS_WITH_VIDEO=$((TICKETS_WITH_VIDEO + 1))
            VIDEO_TICKETS="$VIDEO_TICKETS$TICKET_NAME\n"
        fi
        if [ "$HAS_GIF" -gt 0 ]; then
            TICKETS_WITH_OTHER_IMAGE=$((TICKETS_WITH_OTHER_IMAGE + 1))
        fi
    fi
done

if [ "$NO_FEEDBUCKET" -gt 0 ]; then
    echo -e "  ${RED}! $NO_FEEDBUCKET tickets missing Feedbucket media${NC}"
    echo ""
    echo "  Affected tickets:"
    echo -e "$NO_FEEDBUCKET_LIST" | head -10 | sed 's/^/    - /'
    if [ "$NO_FEEDBUCKET" -gt 10 ]; then
        echo "    ... and $((NO_FEEDBUCKET - 10)) more"
    fi
    echo ""
    echo "  Impact: Cannot populate 'QA Before' field automatically"
    echo "  Resolution: Manual screenshot or skip QA Before for these tickets"
else
    echo -e "  ${GREEN}All tickets have Feedbucket media${NC}"
fi

# Save list to file
echo -e "$NO_FEEDBUCKET_LIST" > "$RESULTS_DIR/tickets_missing_feedbucket.txt"

echo ""

# ============================================
# ERROR STATE 2: No Page URL
# ============================================
echo -e "${BLUE}Error State 2: Missing Page URL${NC}"
echo "Checking which tickets have no Page URL for Chrome MCP..."
echo ""

NO_PAGE_URL=0
NO_PAGE_URL_LIST=""

for PAGE_ID in $TICKET_IDS; do
    TICKET_NAME=$(echo "$RESPONSE" | jq -r --arg id "$PAGE_ID" '.results[] | select(.id == $id) | .properties.ID.unique_id.prefix + "-" + (.properties.ID.unique_id.number | tostring)')

    # Check Page URL property
    PAGE_URL=$(echo "$RESPONSE" | jq -r --arg id "$PAGE_ID" '.results[] | select(.id == $id) | .properties["Page URL"].url // ""')

    if [ -z "$PAGE_URL" ] || [ "$PAGE_URL" = "null" ]; then
        NO_PAGE_URL=$((NO_PAGE_URL + 1))
        NO_PAGE_URL_LIST="$NO_PAGE_URL_LIST$TICKET_NAME\n"
    fi
done

if [ "$NO_PAGE_URL" -gt 0 ]; then
    echo -e "  ${RED}! $NO_PAGE_URL tickets missing Page URL${NC}"
    echo ""
    echo "  Affected tickets:"
    echo -e "$NO_PAGE_URL_LIST" | head -10 | sed 's/^/    - /'
    if [ "$NO_PAGE_URL" -gt 10 ]; then
        echo "    ... and $((NO_PAGE_URL - 10)) more"
    fi
    echo ""
    echo "  Impact: Cannot capture 'QA After' screenshot with Chrome MCP"
    echo "  Resolution: Add Page URL manually or derive from ticket content"
else
    echo -e "  ${GREEN}All tickets have Page URLs${NC}"
fi

# Save list to file
echo -e "$NO_PAGE_URL_LIST" > "$RESULTS_DIR/tickets_missing_page_url.txt"

echo ""

# ============================================
# ERROR STATE 3: No Shopify Theme ID
# ============================================
echo -e "${BLUE}Error State 3: Missing Shopify Theme ID${NC}"
echo "Checking which tickets have no Theme ID for staging preview..."
echo ""

NO_THEME_ID=0
NO_THEME_ID_LIST=""

for PAGE_ID in $TICKET_IDS; do
    TICKET_NAME=$(echo "$RESPONSE" | jq -r --arg id "$PAGE_ID" '.results[] | select(.id == $id) | .properties.ID.unique_id.prefix + "-" + (.properties.ID.unique_id.number | tostring)')

    # Check Shopify Theme ID property
    THEME_ID=$(echo "$RESPONSE" | jq -r --arg id "$PAGE_ID" '.results[] | select(.id == $id) | .properties["Shopify Theme ID"].number // ""')

    if [ -z "$THEME_ID" ] || [ "$THEME_ID" = "null" ]; then
        NO_THEME_ID=$((NO_THEME_ID + 1))
        NO_THEME_ID_LIST="$NO_THEME_ID_LIST$TICKET_NAME\n"
    fi
done

if [ "$NO_THEME_ID" -gt 0 ]; then
    echo -e "  ${YELLOW}! $NO_THEME_ID tickets missing Shopify Theme ID${NC}"
    echo ""
    echo "  Note: Theme ID may be inherited from client/project settings"
    echo "  Impact: Cannot generate staging preview URL automatically"
else
    echo -e "  ${GREEN}All tickets have Shopify Theme ID${NC}"
fi

# Save list to file
echo -e "$NO_THEME_ID_LIST" > "$RESULTS_DIR/tickets_missing_theme_id.txt"

echo ""

# ============================================
# ERROR STATE 4: Both QA Fields Missing Data
# ============================================
echo -e "${BLUE}Error State 4: Cannot Complete QA Workflow${NC}"
echo "Tickets missing BOTH Feedbucket image AND Page URL..."
echo ""

# Find intersection
BOTH_MISSING=0
BOTH_MISSING_LIST=""

NO_FB_ARRAY=$(echo -e "$NO_FEEDBUCKET_LIST" | grep -v "^$" | sort)
NO_URL_ARRAY=$(echo -e "$NO_PAGE_URL_LIST" | grep -v "^$" | sort)

# Find common tickets
if [ -n "$NO_FB_ARRAY" ] && [ -n "$NO_URL_ARRAY" ]; then
    BOTH_MISSING_LIST=$(comm -12 <(echo "$NO_FB_ARRAY") <(echo "$NO_URL_ARRAY"))
    BOTH_MISSING=$(echo "$BOTH_MISSING_LIST" | grep -c "TICK-" || echo "0")
fi

if [ "$BOTH_MISSING" -gt 0 ]; then
    echo -e "  ${RED}! $BOTH_MISSING tickets cannot complete ANY QA step${NC}"
    echo ""
    echo "  Affected tickets:"
    echo "$BOTH_MISSING_LIST" | head -10 | sed 's/^/    - /'
    echo ""
    echo "  Impact: Full manual QA required for these tickets"
    echo "  Resolution: Add Feedbucket image and Page URL before processing"
else
    echo -e "  ${GREEN}All tickets can complete at least partial QA${NC}"
fi

echo ""

# ============================================
# ERROR STATE 5: Feedbucket Media Types
# ============================================
echo -e "${BLUE}Error State 5: Feedbucket Media Type Analysis${NC}"
echo "Detecting media types (PNG, JPG, Video) for QA handling..."
echo ""

TICKETS_WITH_MEDIA=$((TOTAL_TICKETS - NO_FEEDBUCKET))

echo "  Media type breakdown:"
echo -e "    PNG images:    $TICKETS_WITH_PNG tickets"
echo -e "    JPG images:    $TICKETS_WITH_JPG tickets"
echo -e "    Video files:   $TICKETS_WITH_VIDEO tickets"
echo -e "    GIF/Other:     $TICKETS_WITH_OTHER_IMAGE tickets"
echo ""

# Save media type lists
echo -e "$PNG_TICKETS" > "$RESULTS_DIR/tickets_with_png.txt"
echo -e "$JPG_TICKETS" > "$RESULTS_DIR/tickets_with_jpg.txt"
echo -e "$VIDEO_TICKETS" > "$RESULTS_DIR/tickets_with_video.txt"

# Check for video handling requirements
if [ "$TICKETS_WITH_VIDEO" -gt 0 ]; then
    echo -e "  ${YELLOW}! $TICKETS_WITH_VIDEO tickets have VIDEO content${NC}"
    echo ""
    echo "  Video tickets require special handling:"
    echo -e "$VIDEO_TICKETS" | grep -v "^$" | head -10 | sed 's/^/    - /'
    if [ "$TICKETS_WITH_VIDEO" -gt 10 ]; then
        echo "    ... and $((TICKETS_WITH_VIDEO - 10)) more"
    fi
    echo ""
    echo "  Impact: Cannot use static image for 'QA Before' field"
    echo "  Options:"
    echo "    1. Extract first frame from video as thumbnail"
    echo "    2. Store video URL directly in QA Before field"
    echo "    3. Take manual screenshot of video at key moment"
    echo "    4. Flag for manual QA comparison"
    echo ""
    echo "  Recommendation: Process video tickets in separate batch"
else
    echo -e "  ${GREEN}No video content detected - all tickets use static images${NC}"
fi

echo ""

# Check for mixed media (tickets with both image and video)
MIXED_MEDIA=0
if [ "$TICKETS_WITH_VIDEO" -gt 0 ] && [ "$TICKETS_WITH_PNG" -gt 0 ] || [ "$TICKETS_WITH_JPG" -gt 0 ]; then
    # Check if any ticket appears in both lists
    VIDEO_LIST=$(echo -e "$VIDEO_TICKETS" | grep -v "^$" | sort)
    IMAGE_LIST=$(echo -e "$PNG_TICKETS$JPG_TICKETS" | grep -v "^$" | sort | uniq)
    if [ -n "$VIDEO_LIST" ] && [ -n "$IMAGE_LIST" ]; then
        MIXED_MEDIA=$(comm -12 <(echo "$VIDEO_LIST") <(echo "$IMAGE_LIST") | wc -l | tr -d '[:space:]')
    fi
fi

if [ "$MIXED_MEDIA" -gt 0 ]; then
    echo -e "  ${YELLOW}! $MIXED_MEDIA tickets have MIXED media (both image and video)${NC}"
    echo "  These tickets may need review to determine primary QA evidence"
fi

echo ""

# ============================================
# SUMMARY
# ============================================
echo "========================================"
echo "QA ERROR STATES SUMMARY"
echo "========================================"
echo ""

TOTAL_WITH_ISSUES=$((NO_FEEDBUCKET + NO_PAGE_URL))
QA_READY=$((TOTAL_TICKETS - NO_FEEDBUCKET))
QA_READY_PERCENT=0
if [ "$TOTAL_TICKETS" -gt 0 ]; then
    QA_READY_PERCENT=$((QA_READY * 100 / TOTAL_TICKETS))
fi

echo "Total tickets analyzed: $TOTAL_TICKETS"
echo ""
echo "Error breakdown:"
echo -e "  Missing Feedbucket media:  $NO_FEEDBUCKET tickets"
echo -e "  Missing Page URL:          $NO_PAGE_URL tickets"
echo -e "  Missing Theme ID:          $NO_THEME_ID tickets"
echo -e "  Cannot complete any QA:    $BOTH_MISSING tickets"
echo ""
echo "Media type breakdown:"
echo -e "  PNG images:    $TICKETS_WITH_PNG tickets"
echo -e "  JPG images:    $TICKETS_WITH_JPG tickets"
echo -e "  Video files:   $TICKETS_WITH_VIDEO tickets (requires special handling)"
echo -e "  GIF/Other:     $TICKETS_WITH_OTHER_IMAGE tickets"
echo ""
echo "QA-ready tickets: $QA_READY / $TOTAL_TICKETS ($QA_READY_PERCENT%)"
if [ "$TICKETS_WITH_VIDEO" -gt 0 ]; then
    echo -e "  ${YELLOW}Note: $TICKETS_WITH_VIDEO tickets with video need separate batch${NC}"
fi
echo ""

# Determine overall status
if [ "$NO_FEEDBUCKET" -eq 0 ] && [ "$NO_PAGE_URL" -eq 0 ]; then
    echo -e "${GREEN}TEST PASSED: All tickets ready for QA workflow${NC}"
    exit 0
elif [ "$BOTH_MISSING" -eq 0 ]; then
    echo -e "${YELLOW}TEST WARNING: Some tickets have partial QA data${NC}"
    echo ""
    echo "Recommendations:"
    echo "  1. Tickets without Feedbucket: Take manual 'before' screenshot"
    echo "  2. Tickets without Page URL: Add URL or skip 'after' screenshot"
    if [ "$TICKETS_WITH_VIDEO" -gt 0 ]; then
        echo "  3. Video tickets: Process in separate batch with manual QA"
    fi
    echo ""
    echo "Output files:"
    echo "  - $RESULTS_DIR/tickets_missing_feedbucket.txt"
    echo "  - $RESULTS_DIR/tickets_missing_page_url.txt"
    echo "  - $RESULTS_DIR/tickets_with_png.txt"
    echo "  - $RESULTS_DIR/tickets_with_jpg.txt"
    echo "  - $RESULTS_DIR/tickets_with_video.txt"
    exit 0
else
    echo -e "${RED}TEST FAILED: $BOTH_MISSING tickets cannot complete QA${NC}"
    echo ""
    echo "Action required:"
    echo "  Review tickets in $RESULTS_DIR/tickets_missing_*.txt"
    echo "  Add missing Feedbucket images and Page URLs before batch processing"
    exit 1
fi
