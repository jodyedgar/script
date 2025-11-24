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
  else
    ""
  end
'

echo ""
echo "----------------------------------------"
echo "Raw JSON saved to: /tmp/notion-$TICKET_ID.json"
echo "$PAGE_DETAILS" > "/tmp/notion-$TICKET_ID-details.json"
echo "$PAGE_CONTENT" > "/tmp/notion-$TICKET_ID-content.json"
