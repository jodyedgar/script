#!/bin/bash

# Extract Feedbucket image URL from a Notion ticket
# Usage: ./extract-feedbucket-image.sh TICK-### [--download] [--output FILE]
#
# Returns the Feedbucket image URL for use in QA Before workflow
# With --download, saves the image to a local file

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Notion config
TICKETS_DATABASE_ID="1abc197b3ae7808fa454dd0c0e96ca6f"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_usage() {
    echo "Usage: $0 TICKET-ID [OPTIONS]"
    echo ""
    echo "Extract Feedbucket image URL from a Notion ticket."
    echo ""
    echo "Options:"
    echo "  --download, -d       Download the image to local file"
    echo "  --output, -o FILE    Output file path (default: ./{ticket}-feedbucket.{ext})"
    echo "  --json, -j           Output as JSON"
    echo "  --help, -h           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 TICK-1234                           # Print URL only"
    echo "  $0 TICK-1234 --download                # Download to TICK-1234-feedbucket.png"
    echo "  $0 TICK-1234 -d -o ./before.png        # Download to specific file"
    echo "  $0 TICK-1234 --json                    # Output JSON with metadata"
    exit 1
}

# Parse arguments
TICKET_ID=""
DO_DOWNLOAD="false"
OUTPUT_FILE=""
OUTPUT_JSON="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        TICK-*|tick-*)
            TICKET_ID=$(echo "$1" | tr '[:lower:]' '[:upper:]')
            shift
            ;;
        --download|-d)
            DO_DOWNLOAD="true"
            shift
            ;;
        --output|-o)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --json|-j)
            OUTPUT_JSON="true"
            shift
            ;;
        --help|-h)
            show_usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}" >&2
            show_usage
            ;;
    esac
done

if [ -z "$TICKET_ID" ]; then
    echo -e "${RED}Error: TICKET-ID required${NC}" >&2
    show_usage
fi

# Load Notion credentials
if [ -f "$HOME/.bash_profile" ]; then
    source "$HOME/.bash_profile"
fi

if [ -z "$NOTION_API_KEY" ]; then
    echo -e "${RED}Error: NOTION_API_KEY not set${NC}" >&2
    exit 1
fi

TICKET_NUMBER=$(echo "$TICKET_ID" | sed 's/TICK-//')

# Look up page ID
DATABASE_QUERY=$(curl -s -X POST "https://api.notion.com/v1/databases/$TICKETS_DATABASE_ID/query" \
    -H "Authorization: Bearer $NOTION_API_KEY" \
    -H "Notion-Version: 2022-06-28" \
    -H "Content-Type: application/json" \
    -d "{\"filter\": {\"property\": \"ID\", \"unique_id\": {\"equals\": $TICKET_NUMBER}}}")

PAGE_ID=$(echo "$DATABASE_QUERY" | jq -r '.results[0].id // empty' | tr -d '-')

if [ -z "$PAGE_ID" ]; then
    if [ "$OUTPUT_JSON" = "true" ]; then
        echo '{"error": "Ticket not found", "ticket": "'"$TICKET_ID"'"}'
    else
        echo -e "${RED}Error: Ticket $TICKET_ID not found${NC}" >&2
    fi
    exit 1
fi

# Get page content blocks to find Feedbucket media
BLOCKS_RESPONSE=$(curl -s -X GET "https://api.notion.com/v1/blocks/$PAGE_ID/children?page_size=100" \
    -H "Authorization: Bearer $NOTION_API_KEY" \
    -H "Notion-Version: 2022-06-28")

# Look for image blocks with Feedbucket URLs
FEEDBUCKET_URL=$(echo "$BLOCKS_RESPONSE" | jq -r '
    .results[] |
    select(.type == "image" or .type == "file" or .type == "video") |
    if .type == "image" then
        (.image.external.url // .image.file.url)
    elif .type == "video" then
        (.video.external.url // .video.file.url)
    else
        (.file.external.url // .file.file.url)
    end
' | grep -i "feedbucket\|fb-media\|feedback" | head -1)

MEDIA_TYPE="image"

# If not found in blocks, check the Feedbucket Media property
if [ -z "$FEEDBUCKET_URL" ]; then
    PAGE_RESPONSE=$(curl -s -X GET "https://api.notion.com/v1/pages/$PAGE_ID" \
        -H "Authorization: Bearer $NOTION_API_KEY" \
        -H "Notion-Version: 2022-06-28")

    FEEDBUCKET_URL=$(echo "$PAGE_RESPONSE" | jq -r '
        .properties["Feedbucket Media"].files[0].external.url //
        .properties["Feedbucket Media"].files[0].file.url //
        .properties["Screenshot"].files[0].external.url //
        .properties["Screenshot"].files[0].file.url //
        empty
    ')
fi

# Check for video content
if echo "$FEEDBUCKET_URL" | grep -qi "\.mp4\|\.webm\|\.mov\|video"; then
    MEDIA_TYPE="video"
fi

if [ -z "$FEEDBUCKET_URL" ]; then
    if [ "$OUTPUT_JSON" = "true" ]; then
        echo '{"error": "No Feedbucket media found", "ticket": "'"$TICKET_ID"'", "page_id": "'"$PAGE_ID"'"}'
    else
        echo -e "${RED}Error: No Feedbucket media found in $TICKET_ID${NC}" >&2
    fi
    exit 1
fi

# Determine file extension from URL
EXT="png"
if echo "$FEEDBUCKET_URL" | grep -qi "\.jpg\|\.jpeg"; then
    EXT="jpg"
elif echo "$FEEDBUCKET_URL" | grep -qi "\.gif"; then
    EXT="gif"
elif echo "$FEEDBUCKET_URL" | grep -qi "\.webp"; then
    EXT="webp"
elif echo "$FEEDBUCKET_URL" | grep -qi "\.mp4"; then
    EXT="mp4"
elif echo "$FEEDBUCKET_URL" | grep -qi "\.webm"; then
    EXT="webm"
fi

# Download if requested
if [ "$DO_DOWNLOAD" = "true" ]; then
    if [ -z "$OUTPUT_FILE" ]; then
        OUTPUT_FILE="./${TICKET_ID}-feedbucket.${EXT}"
    fi

    curl -s -L -o "$OUTPUT_FILE" "$FEEDBUCKET_URL"

    if [ -f "$OUTPUT_FILE" ]; then
        FILE_SIZE=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE" 2>/dev/null)
        if [ "$OUTPUT_JSON" = "true" ]; then
            echo '{"success": true, "url": "'"$FEEDBUCKET_URL"'", "file": "'"$OUTPUT_FILE"'", "size": '"$FILE_SIZE"', "type": "'"$MEDIA_TYPE"'", "ticket": "'"$TICKET_ID"'"}'
        else
            echo -e "${GREEN}✓ Downloaded: $OUTPUT_FILE ($FILE_SIZE bytes)${NC}"
        fi
    else
        if [ "$OUTPUT_JSON" = "true" ]; then
            echo '{"error": "Download failed", "url": "'"$FEEDBUCKET_URL"'"}'
        else
            echo -e "${RED}Error: Download failed${NC}" >&2
        fi
        exit 1
    fi
else
    # Just output the URL
    if [ "$OUTPUT_JSON" = "true" ]; then
        echo '{"url": "'"$FEEDBUCKET_URL"'", "type": "'"$MEDIA_TYPE"'", "ticket": "'"$TICKET_ID"'", "page_id": "'"$PAGE_ID"'"}'
    else
        echo "$FEEDBUCKET_URL"
    fi
fi
