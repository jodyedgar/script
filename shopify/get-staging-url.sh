#!/bin/bash

# Generate Shopify staging/preview URL
# Usage:
#   ./get-staging-url.sh                      # Auto-detect from git branch
#   ./get-staging-url.sh --theme-id 12345     # Specific theme ID
#   ./get-staging-url.sh --branch feature-x   # From branch config
#   ./get-staging-url.sh --store mystore      # Specific store
#
# Outputs a preview URL that can be used for QA verification.

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Defaults
THEME_ID=""
BRANCH=""
STORE=""
PAGE_PATH="/"
COPY_TO_CLIPBOARD=false
OUTPUT_FORMAT="url"  # url, markdown, json, notion

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Generate Shopify staging preview URL."
    echo ""
    echo "Options:"
    echo "  --theme-id, -t ID       Shopify theme ID for preview"
    echo "  --branch, -b BRANCH     Get theme ID from git branch config"
    echo "  --store, -s STORE       Store domain (e.g., store.myshopify.com)"
    echo "  --page, -p PATH         Page path to preview (default: /)"
    echo "  --copy, -c              Copy URL to clipboard"
    echo "  --format, -f FORMAT     Output format: url, markdown, json, notion"
    echo "  --help, -h              Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                           # Auto-detect from current branch"
    echo "  $0 --theme-id 181781889340"
    echo "  $0 --page /collections/all"
    echo "  $0 --format markdown --copy"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --theme-id|-t)
            THEME_ID="$2"
            shift 2
            ;;
        --branch|-b)
            BRANCH="$2"
            shift 2
            ;;
        --store|-s)
            STORE="$2"
            shift 2
            ;;
        --page|-p)
            PAGE_PATH="$2"
            shift 2
            ;;
        --copy|-c)
            COPY_TO_CLIPBOARD=true
            shift
            ;;
        --format|-f)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --help|-h)
            show_usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_usage
            ;;
    esac
done

# Auto-detect store from current directory
if [ -z "$STORE" ]; then
    # Try to get from shopify theme config
    if [ -f ".shopify/shop" ]; then
        STORE=$(cat .shopify/shop 2>/dev/null || true)
    fi

    # Try from directory name pattern
    if [ -z "$STORE" ]; then
        CURRENT_DIR=$(basename "$(pwd)")
        if [[ "$CURRENT_DIR" == *".myshopify.com"* ]]; then
            STORE="$CURRENT_DIR"
        fi
    fi

    # Try parent directories
    if [ -z "$STORE" ]; then
        PARENT_DIR=$(basename "$(dirname "$(pwd)")")
        if [[ "$PARENT_DIR" == *".myshopify.com"* ]] || [[ "$PARENT_DIR" == *"store."* ]]; then
            STORE="$PARENT_DIR"
        fi
    fi

    # Default for Figma store
    if [ -z "$STORE" ]; then
        # Check if we're in the figma store project
        if [[ "$(pwd)" == *"figma"* ]] || [[ "$(pwd)" == *"horizon"* ]]; then
            STORE="the-figma-store.myshopify.com"
        fi
    fi
fi

if [ -z "$STORE" ]; then
    echo -e "${RED}Error: Could not detect store. Use --store option.${NC}"
    exit 1
fi

# Auto-detect theme ID from git branch
if [ -z "$THEME_ID" ]; then
    # Get current branch
    if [ -z "$BRANCH" ]; then
        BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    fi

    if [ -n "$BRANCH" ]; then
        # Check git config for theme ID
        THEME_ID=$(git config "branch.$BRANCH.themeId" 2>/dev/null || true)
    fi

    # Try to get from shopify CLI
    if [ -z "$THEME_ID" ]; then
        if command -v shopify &> /dev/null; then
            # Get development theme ID
            THEME_ID=$(shopify theme list --json 2>/dev/null | jq -r '.[] | select(.role == "development" or .role == "unpublished") | .id' | head -1 || true)
        fi
    fi
fi

if [ -z "$THEME_ID" ]; then
    echo -e "${YELLOW}Warning: No theme ID found. Showing live store URL.${NC}"
    echo "Set theme ID with: git config branch.$(git rev-parse --abbrev-ref HEAD).themeId YOUR_THEME_ID"
    echo ""
fi

# Build the preview URL
if [ -n "$THEME_ID" ]; then
    # Preview URL with theme ID
    PREVIEW_URL="https://${STORE}${PAGE_PATH}?preview_theme_id=${THEME_ID}"
else
    # Live store URL
    PREVIEW_URL="https://${STORE}${PAGE_PATH}"
fi

# Output based on format
case "$OUTPUT_FORMAT" in
    url)
        echo "$PREVIEW_URL"
        ;;
    markdown)
        echo "[Preview: ${STORE}](${PREVIEW_URL})"
        ;;
    json)
        jq -n \
            --arg store "$STORE" \
            --arg theme_id "$THEME_ID" \
            --arg branch "$BRANCH" \
            --arg page "$PAGE_PATH" \
            --arg url "$PREVIEW_URL" \
            '{store: $store, theme_id: $theme_id, branch: $branch, page: $page, preview_url: $url}'
        ;;
    notion)
        # Format for Notion rich text
        echo "🔗 [Staging Preview](${PREVIEW_URL})"
        echo ""
        echo "Store: ${STORE}"
        echo "Theme ID: ${THEME_ID:-'(live)'}"
        echo "Branch: ${BRANCH:-'(unknown)'}"
        ;;
    *)
        echo -e "${RED}Unknown format: $OUTPUT_FORMAT${NC}"
        exit 1
        ;;
esac

# Copy to clipboard if requested
if [ "$COPY_TO_CLIPBOARD" = true ]; then
    if command -v pbcopy &> /dev/null; then
        echo -n "$PREVIEW_URL" | pbcopy
        echo -e "${GREEN}✓ Copied to clipboard${NC}" >&2
    elif command -v xclip &> /dev/null; then
        echo -n "$PREVIEW_URL" | xclip -selection clipboard
        echo -e "${GREEN}✓ Copied to clipboard${NC}" >&2
    else
        echo -e "${YELLOW}Clipboard not available${NC}" >&2
    fi
fi
