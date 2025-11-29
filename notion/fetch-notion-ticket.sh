#!/bin/bash

# Script to fetch Notion ticket details from the Tickets database
# Usage: ./fetch-notion-ticket.sh TICK-940

# Tickets database ID
TICKETS_DATABASE_ID="1abc197b3ae7808fa454dd0c0e96ca6f"

# Check if ticket ID is provided
if [ -z "$1" ]; then
    echo "Usage: $0 TICKET-ID"
    echo "Example: $0 TICK-940"
    exit 1
fi

TICKET_ID="$1"

# Extract the number from the ticket ID (e.g., "TICK-940" -> "940")
TICKET_NUMBER=$(echo "$TICKET_ID" | sed 's/TICK-//')

# Check if NOTION_API_KEY is set, if not try to load from bash_profile
if [ -z "$NOTION_API_KEY" ]; then
    if [ -f "$HOME/.bash_profile" ]; then
        source "$HOME/.bash_profile"
    fi

    if [ -z "$NOTION_API_KEY" ]; then
        echo "Error: NOTION_API_KEY environment variable is not set"
        echo "Set it with: export NOTION_API_KEY='your-api-key'"
        exit 1
    fi
fi

echo "Searching for ticket: $TICKET_ID (number: $TICKET_NUMBER) in Tickets database"
echo "----------------------------------------"

# Query the tickets database with filter for the specific ticket number
# The ID property is a unique_id type, so we filter by the number
DATABASE_QUERY=$(curl -s -X POST "https://api.notion.com/v1/databases/$TICKETS_DATABASE_ID/query" \
  -H "Authorization: Bearer $NOTION_API_KEY" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d "{
    \"filter\": {
      \"property\": \"ID\",
      \"unique_id\": {
        \"equals\": $TICKET_NUMBER
      }
    }
  }")

# Extract page ID from database query results
PAGE_ID=$(echo "$DATABASE_QUERY" | jq -r '.results[0].id // empty' | tr -d '-')

if [ -z "$PAGE_ID" ]; then
    echo "Error: Ticket not found in Tickets database"
    echo "Database ID: $TICKETS_DATABASE_ID"
    echo "Response: $DATABASE_QUERY"
    exit 1
fi

echo "Found page ID: $PAGE_ID"
echo ""

# Fetch page details
PAGE_DETAILS=$(curl -s -X GET "https://api.notion.com/v1/pages/$PAGE_ID" \
  -H "Authorization: Bearer $NOTION_API_KEY" \
  -H "Notion-Version: 2022-06-28")

# Fetch page content (blocks)
PAGE_CONTENT=$(curl -s -X GET "https://api.notion.com/v1/blocks/$PAGE_ID/children" \
  -H "Authorization: Bearer $NOTION_API_KEY" \
  -H "Notion-Version: 2022-06-28")

echo "TICKET DETAILS:"
echo "----------------------------------------"
echo "$PAGE_DETAILS" | jq -r '
  "ID: " + (.properties.ID.unique_id.prefix // "") + "-" + (.properties.ID.unique_id.number // 0 | tostring),
  "Title: " + (.properties.Name.title[0].plain_text // .properties.title.title[0].plain_text // "N/A"),
  "Status: " + (.properties["Ticket Status"].status.name // "N/A"),
  "Type: " + (.properties["Ticket Type"].select.name // "N/A"),
  "URL: " + .url
'

# Get current status
CURRENT_STATUS=$(echo "$PAGE_DETAILS" | jq -r '.properties["Ticket Status"].status.name // "N/A"')

# Update status to "In Progress" and set Checkout Time if it's not already in a completed state
if [[ "$CURRENT_STATUS" != "Done" && "$CURRENT_STATUS" != "Complete" && "$CURRENT_STATUS" != "In Progress" ]]; then
    echo ""
    echo "Updating status to 'In Progress' and setting Checkout Time..."

    # Get current timestamp in ISO 8601 format
    CHECKOUT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

    UPDATE_RESPONSE=$(curl -s -X PATCH "https://api.notion.com/v1/pages/$PAGE_ID" \
      -H "Authorization: Bearer $NOTION_API_KEY" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      -d "{
        \"properties\": {
          \"Ticket Status\": {
            \"status\": {
              \"name\": \"In Progress\"
            }
          },
          \"Checkout Time\": {
            \"date\": {
              \"start\": \"$CHECKOUT_TIME\"
            }
          }
        }
      }")

    # Check if update was successful
    UPDATED_STATUS=$(echo "$UPDATE_RESPONSE" | jq -r '.properties["Ticket Status"].status.name // "error"')

    if [ "$UPDATED_STATUS" == "In Progress" ]; then
        echo "✓ Status updated to 'In Progress'"
        echo "✓ Checkout Time set to $CHECKOUT_TIME"
    else
        echo "⚠ Warning: Failed to update status"
        echo "Response: $UPDATE_RESPONSE"
    fi
elif [ "$CURRENT_STATUS" == "In Progress" ]; then
    echo ""
    echo "✓ Status already 'In Progress'"

    # Still update Checkout Time
    CHECKOUT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

    UPDATE_RESPONSE=$(curl -s -X PATCH "https://api.notion.com/v1/pages/$PAGE_ID" \
      -H "Authorization: Bearer $NOTION_API_KEY" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      -d "{
        \"properties\": {
          \"Checkout Time\": {
            \"date\": {
              \"start\": \"$CHECKOUT_TIME\"
            }
          }
        }
      }")

    echo "✓ Checkout Time updated to $CHECKOUT_TIME"
elif [ "$CURRENT_STATUS" == "Done" ] || [ "$CURRENT_STATUS" == "Complete" ]; then
    echo ""
    echo "ℹ Status is '$CURRENT_STATUS' - not updating"
fi

echo ""
echo "DESCRIPTION/CONTENT:"
echo "----------------------------------------"
echo "$PAGE_CONTENT" | jq -r '.results[] |
  if .type == "paragraph" then
    .paragraph.rich_text[].plain_text // ""
  elif .type == "heading_1" then
    "\n## " + (.heading_1.rich_text[].plain_text // "")
  elif .type == "heading_2" then
    "\n### " + (.heading_2.rich_text[].plain_text // "")
  elif .type == "heading_3" then
    "\n#### " + (.heading_3.rich_text[].plain_text // "")
  elif .type == "bulleted_list_item" then
    "- " + (.bulleted_list_item.rich_text[].plain_text // "")
  elif .type == "numbered_list_item" then
    "• " + (.numbered_list_item.rich_text[].plain_text // "")
  elif .type == "to_do" then
    "[" + (if .to_do.checked then "x" else " " end) + "] " + (.to_do.rich_text[].plain_text // "")
  elif .type == "code" then
    "\n```\n" + (.code.rich_text[].plain_text // "") + "\n```"
  elif .type == "image" then
    "[IMAGE: " + (.image.external.url // .image.file.url // "unknown") + "]"
  elif .type == "embed" then
    "[EMBED: " + (.embed.url // "unknown") + "]"
  elif .type == "bookmark" then
    "[BOOKMARK: " + (.bookmark.url // "unknown") + "]"
  elif .type == "link_preview" then
    "[LINK PREVIEW: " + (.link_preview.url // "unknown") + "]"
  elif .type == "video" then
    "[VIDEO: " + (.video.external.url // .video.file.url // "unknown") + "]"
  elif .type == "file" then
    "[FILE: " + (.file.external.url // .file.file.url // "unknown") + "]"
  elif .type == "pdf" then
    "[PDF: " + (.pdf.external.url // .pdf.file.url // "unknown") + "]"
  elif .type == "audio" then
    "[AUDIO: " + (.audio.external.url // .audio.file.url // "unknown") + "]"
  elif .type == "divider" then
    "\n---\n"
  elif .type == "callout" then
    "💡 " + (.callout.rich_text[].plain_text // "")
  elif .type == "quote" then
    "> " + (.quote.rich_text[].plain_text // "")
  elif .type == "toggle" then
    "▶ " + (.toggle.rich_text[].plain_text // "")
  else
    ""
  end
'

# Extract ALL referenced links from the content
echo ""
echo "REFERENCED LINKS:"
echo "----------------------------------------"

# Extract links from various block types
BLOCK_LINKS=$(echo "$PAGE_CONTENT" | jq -r '
  .results[] |
  if .type == "bookmark" then
    .bookmark.url // empty
  elif .type == "link_preview" then
    .link_preview.url // empty
  elif .type == "embed" then
    .embed.url // empty
  elif .type == "video" then
    .video.external.url // .video.file.url // empty
  elif .type == "file" then
    .file.external.url // .file.file.url // empty
  elif .type == "pdf" then
    .pdf.external.url // .pdf.file.url // empty
  else
    empty
  end
' | grep -v '^$' || true)

# Extract inline links from rich_text in all text-containing blocks
INLINE_LINKS=$(echo "$PAGE_CONTENT" | jq -r '
  .results[] |
  (
    .paragraph.rich_text //
    .heading_1.rich_text //
    .heading_2.rich_text //
    .heading_3.rich_text //
    .bulleted_list_item.rich_text //
    .numbered_list_item.rich_text //
    .to_do.rich_text //
    .callout.rich_text //
    .quote.rich_text //
    .toggle.rich_text //
    []
  )[] |
  select(.text.link != null) |
  .text.link.url
' 2>/dev/null | grep -v '^$' || true)

# Combine and deduplicate all links
ALL_LINKS=$(echo -e "$BLOCK_LINKS\n$INLINE_LINKS" | grep -v '^$' | sort -u || true)

if [ -n "$ALL_LINKS" ]; then
    echo "$ALL_LINKS" | while read -r link_url; do
        if [ -n "$link_url" ]; then
            # Categorize links for easier reading
            if echo "$link_url" | grep -qi "github.com"; then
                echo "🔗 [GitHub] $link_url"
            elif echo "$link_url" | grep -qi "shopify"; then
                echo "🛍️  [Shopify] $link_url"
            elif echo "$link_url" | grep -qi "figma.com"; then
                echo "🎨 [Figma] $link_url"
            elif echo "$link_url" | grep -qi "notion.so\|notion.site"; then
                echo "📝 [Notion] $link_url"
            elif echo "$link_url" | grep -qi "loom.com"; then
                echo "🎬 [Loom] $link_url"
            elif echo "$link_url" | grep -qi "youtube.com\|youtu.be"; then
                echo "📺 [YouTube] $link_url"
            elif echo "$link_url" | grep -qi "docs.google\|drive.google"; then
                echo "📄 [Google] $link_url"
            else
                echo "🔗 $link_url"
            fi
        fi
    done
else
    echo "(No links found)"
fi

# Extract and display images separately for better visibility
echo ""
IMAGES=$(echo "$PAGE_CONTENT" | jq -r '.results[] | select(.type == "image") | .image.external.url // .image.file.url // empty')
FEEDBUCKET_IMAGES=$(echo "$IMAGES" | grep -i "feedbucket" || true)

if [ -n "$IMAGES" ]; then
    echo "ATTACHED IMAGES:"
    echo "----------------------------------------"
    echo "$IMAGES" | while read -r img_url; do
        if [ -n "$img_url" ]; then
            if echo "$img_url" | grep -qi "feedbucket"; then
                echo "📸 [FEEDBUCKET] $img_url"
            else
                echo "🖼️  $img_url"
            fi
        fi
    done
fi

# Highlight Feedbucket images specifically for Claude Code
if [ -n "$FEEDBUCKET_IMAGES" ]; then
    echo ""
    echo "🎯 FEEDBUCKET SCREENSHOTS (for Claude Code to analyze):"
    echo "----------------------------------------"

    # Create temp directory for this ticket's images
    IMG_DIR="/tmp/notion-$TICKET_ID-images"
    mkdir -p "$IMG_DIR"

    IMG_COUNT=0
    echo "$FEEDBUCKET_IMAGES" | while read -r fb_url; do
        if [ -n "$fb_url" ]; then
            IMG_COUNT=$((IMG_COUNT + 1))
            # Extract filename from URL or generate one
            FILENAME=$(basename "$fb_url" | cut -d'?' -f1)
            if [ -z "$FILENAME" ] || [ "$FILENAME" = "/" ]; then
                FILENAME="screenshot_$IMG_COUNT.png"
            fi
            IMG_PATH="$IMG_DIR/$FILENAME"

            echo "Downloading: $fb_url"
            if curl -sL "$fb_url" -o "$IMG_PATH" 2>/dev/null; then
                echo "  ✓ Saved to: $IMG_PATH"
            else
                echo "  ⚠ Failed to download"
                echo "  URL: $fb_url"
            fi
        fi
    done

    echo ""
    echo "📁 Images saved to: $IMG_DIR"
    echo ""
    echo "Claude Code can view these with: Read $IMG_DIR/<filename>"
    ls -la "$IMG_DIR" 2>/dev/null | grep -v "^total" | grep -v "^d"
fi

echo ""
echo "----------------------------------------"
echo "Raw JSON saved to: /tmp/notion-$TICKET_ID.json"
echo "$PAGE_DETAILS" > "/tmp/notion-$TICKET_ID-details.json"
echo "$PAGE_CONTENT" > "/tmp/notion-$TICKET_ID-content.json"
