#!/bin/bash

# Shopify Store Setup Script
# Sets up a new Shopify store with Git, pnpm, and Claude Code integration
# Usage: ./setup-shopify-store.sh <store-name>

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if store name provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: Store name required${NC}"
    echo "Usage: ./setup-shopify-store.sh <store-name>"
    exit 1
fi

STORE_NAME="$1"
STORE_DIR="$HOME/Dropbox/wwwroot/$STORE_NAME"

echo -e "${GREEN}Setting up Shopify store: $STORE_NAME${NC}"

# Step 1: Create project directory
echo -e "${YELLOW}Creating project directory...${NC}"
mkdir -p "$STORE_DIR"
cd "$STORE_DIR"

# Step 2: Initialize Git
echo -e "${YELLOW}Initializing Git repository...${NC}"
git init

# Step 3: Create .gitignore
echo -e "${YELLOW}Creating .gitignore...${NC}"
cat > .gitignore << 'GITIGNORE'
# Shopify CLI
.shopify/
*.log

# Dependencies
node_modules/
.pnpm-store/

# Environment
.env
.env.local

# OS Files
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/
*.swp
*.swo
GITIGNORE

# Step 4: Create .clinerules for Claude Code
echo -e "${YELLOW}Creating .clinerules for Claude Code...${NC}"
cat > .clinerules << 'CLINERULES'
# Shopify Theme Development Rules for Claude Code

## Project Context
This is a Shopify theme project using Liquid templates, modern CSS, and vanilla JavaScript.

## File Structure
- /sections/ - Reusable Shopify sections
- /snippets/ - Smaller reusable components  
- /templates/ - Page templates
- /assets/ - CSS, JS, images
- /config/ - Theme settings
- /locales/ - Translations

## Development Workflow
1. Clone repository and create feature branch for each ticket
2. Make code changes locally
3. Commit and push to GitHub
4. GitHub syncs automatically with Shopify
5. Preview changes on Shopify store
6. Make theme settings adjustments in Shopify admin if needed
7. Git rebase local copy before next code changes
8. Commit with clear messages including ticket numbers

## Liquid Template Rules
- Use {% schema %} blocks for section settings
- ALWAYS include "presets" in schema for sections to appear in customizer
- Use semantic HTML5 elements
- Follow Shopify's section/block pattern for flexibility

## Schema Best Practices
- Include "presets" block (even if empty) for all sections
- Use straight ASCII quotes "" not Unicode quotes ""
- Provide sensible defaults for all settings
- Group related settings with headers

## CSS Guidelines
- Use CSS custom properties for theme colors/spacing
- Mobile-first responsive design
- Prefer utility classes when appropriate
- Keep specificity low

## JavaScript Guidelines  
- Vanilla JS preferred (avoid jQuery)
- Use ES6+ features
- Keep scripts modular and scoped
- Use Shopify's Ajax API for cart operations

## Git Workflow
- Feature branches: fix-TICK-### or feature-TICK-###
- Clear commit messages with ticket numbers
- Push to GitHub for automatic Shopify dev theme sync

## Common Pitfalls to Avoid
- ❌ Editing directly in Shopify Theme Editor on GitHub branches
- ❌ Forgetting "presets" in section schema
- ❌ Using Unicode quotes in JSON schema
- ❌ Not rebasing before making new code changes
CLINERULES

# Step 5: Create README
echo -e "${YELLOW}Creating README.md...${NC}"
cat > README.md << README
# $STORE_NAME

Shopify theme for $STORE_NAME

## Development Workflow

1. Clone repository: \`git clone <repo-url> $STORE_NAME\`
2. Create feature branch: \`git checkout -b fix-TICK-###\`
3. Make code changes locally
4. Commit: \`git add . && git commit -m "Fix: description TICK-###"\`
5. Push: \`git push origin fix-TICK-###\`
6. GitHub syncs automatically with Shopify
7. Preview on Shopify store and adjust theme settings if needed
8. Before next changes: \`git pull --rebase origin main\`

## Important Notes

- ✅ GitHub is connected to Shopify and syncs automatically
- ✅ Make theme setting changes in Shopify admin after code is pushed
- ❌ NEVER edit directly in Shopify Theme Editor on GitHub branches
- ✅ Always rebase before starting new code changes

## Scripts Location

Automation scripts are in \`~/Dropbox/scripts/\`
README

# Step 6: Initial commit
echo -e "${YELLOW}Creating initial commit...${NC}"
git add .
git commit -m "Initial setup: Git and Claude Code integration"

echo -e "${GREEN}✓ Setup complete!${NC}"
echo ""
echo "Next steps:"
echo "1. cd $STORE_DIR"
echo "2. Connect to GitHub: git remote add origin <repo-url>"
echo "3. Push: git push -u origin main"
echo "4. Connect GitHub to Shopify theme in Shopify admin"
echo "5. Start developing - changes push to GitHub and sync to Shopify"
