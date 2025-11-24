#!/bin/bash

# Add .clinerules to Existing Shopify Store
# Adds Claude Code optimization rules to an existing Shopify project
# Usage: ./add-clinerules-to-project.sh [path-to-store]

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Determine target directory
if [ -z "$1" ]; then
    TARGET_DIR=$(pwd)
    echo -e "${YELLOW}No path provided, using current directory: $TARGET_DIR${NC}"
else
    TARGET_DIR="$1"
    echo -e "${YELLOW}Using specified directory: $TARGET_DIR${NC}"
fi

# Check if directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo -e "${RED}Error: Directory does not exist: $TARGET_DIR${NC}"
    exit 1
fi

cd "$TARGET_DIR"

# Check if this looks like a Shopify theme
if [ ! -d "sections" ] && [ ! -d "templates" ]; then
    echo -e "${RED}Warning: This doesn't look like a Shopify theme directory${NC}"
    echo "Expected to find 'sections' or 'templates' folders."
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if .clinerules already exists
if [ -f ".clinerules" ]; then
    echo -e "${YELLOW}.clinerules already exists${NC}"
    read -p "Overwrite? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# Create .clinerules
echo -e "${GREEN}Creating .clinerules...${NC}"
cat > .clinerules << 'CLINERULES'
# Shopify Theme Development Rules for Claude Code

## Project Context
This is a Shopify theme project using Liquid templates, modern CSS, and vanilla JavaScript.

## File Structure
- /sections/ - Reusable Shopify sections
- /snippets/ - Smaller reusable components  
- /templates/ - Page templates (JSON or Liquid)
- /assets/ - CSS, JS, images
- /config/ - Theme settings (settings_schema.json, settings_data.json)
- /locales/ - Translation files
- /layout/ - Theme layouts (theme.liquid)

## Development Workflow
1. ALWAYS use `pnpm run dev` for local development (NEVER `shopify theme dev` on GitHub-connected themes)
2. Create feature branches off main/site-refresh for each ticket
3. Test locally before committing
4. Commit with clear messages including ticket numbers (TICK-###)

## Liquid Template Rules
- Use {% schema %} blocks for section settings
- ALWAYS include "presets" in schema for sections to appear in customizer
- Use semantic HTML5 elements
- Follow Shopify's section/block pattern for flexibility
- Prefer {% render %} over {% include %} for snippets

## Schema Best Practices
- Include "presets" block (even if empty) for all sections
- Use straight ASCII quotes "" not Unicode quotes ""
- Provide sensible defaults for all settings
- Group related settings with "type": "header"
- Use descriptive IDs and labels
- Common setting types: text, textarea, richtext, html, checkbox, radio, select, range, color, image_picker, url, page, collection, product

## CSS Guidelines
- Use CSS custom properties for theme colors/spacing
- Mobile-first responsive design
- Prefer utility classes when appropriate
- Keep specificity low
- Use Shopify's {{ 'file.css' | asset_url | stylesheet_tag }} for loading styles

## JavaScript Guidelines  
- Vanilla JS preferred (avoid jQuery unless already in theme)
- Use ES6+ features
- Keep scripts modular and scoped
- Use Shopify's Ajax API for cart operations
- Load scripts with {{ 'file.js' | asset_url | script_tag }}
- Use theme.js for global functionality

## Shopify Liquid Objects & Filters
- Key objects: product, collection, cart, shop, customer, page, blog, article
- Common filters: money, img_url, url, link_to, default, date
- Cart API: /cart/add.js, /cart/change.js, /cart/clear.js, /cart.js

## Git Workflow
- Feature branches: fix-TICK-### or feature-TICK-###
- Clear commit messages with ticket numbers
- Push to GitHub for automatic Shopify dev theme sync (if connected)
- Never force push to main/production branches

## Common Pitfalls to Avoid
- ❌ Using `shopify theme dev` on GitHub-connected themes (causes sync conflicts)
- ❌ Editing directly in Shopify Theme Editor on GitHub-connected branches
- ❌ Forgetting "presets" in section schema (section won't appear in customizer)
- ❌ Using Unicode quotes "" in JSON schema (causes Invalid JSON errors)
- ❌ Not testing on localhost before pushing
- ❌ Using `shopify theme pull` on GitHub-connected themes (overwrites local work)
- ❌ Default values in URL-type schema fields (not allowed, causes validation errors)

## Testing Checklist
- [ ] Test on localhost with `pnpm run dev`
- [ ] Check mobile responsiveness (375px, 768px, 1024px+)
- [ ] Verify section appears in theme customizer
- [ ] Test with different content lengths
- [ ] Check browser console for errors
- [ ] Validate JSON schema syntax

## Deployment Notes
- GitHub-connected themes: Push to branch, auto-syncs to Shopify dev theme
- Manual themes: Use Shopify CLI to push
- Always test on dev/staging theme before production
CLINERULES

# Add to git if in a git repo
if [ -d ".git" ]; then
    echo -e "${YELLOW}Adding .clinerules to git...${NC}"
    git add .clinerules
    
    if git diff --cached --quiet; then
        echo -e "${YELLOW}No changes to commit (file unchanged)${NC}"
    else
        git commit -m "Add .clinerules for Claude Code optimization"
        echo -e "${GREEN}✓ Committed .clinerules${NC}"
    fi
else
    echo -e "${YELLOW}Not a git repository, skipping commit${NC}"
fi

echo -e "${GREEN}✓ .clinerules added successfully!${NC}"
echo ""
echo "Claude Code will now use these rules when working in this project."
echo "Start Claude Code: claude"
