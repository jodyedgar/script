# Sunbowl Systems Automation Scripts

Central location for all workflow automation scripts.

## 📁 Directory Structure
cat > ~/Dropbox/scripts/README.md << 'EOF'
# Sunbowl Systems Automation Scripts

Central location for all workflow automation scripts.

## 📁 Directory Structure
```
~/Dropbox/scripts/
├── notion/          # Notion ticket management
├── shopify/         # Shopify store setup & workflow
└── README.md        # This file
```

## 🎫 Notion Scripts

Located in `~/Dropbox/scripts/notion/`

### fetch-notion-ticket.sh
Retrieves ticket details from Notion database.

**Usage:**
```bash
~/Dropbox/scripts/notion/fetch-notion-ticket.sh TICK-###
```

### manage-notion-ticket.sh ⭐ NEW UNIFIED SCRIPT
Unified script to manage all ticket updates - replaces update-notion-ticket.sh and complete-notion-ticket.sh.

**Features:**
- Update ticket status
- Set GitHub PR URL
- Append formatted summaries/notes (supports markdown)
- All actions can be combined in a single command

**Usage:**
```bash
# Update status only
~/Dropbox/scripts/notion/manage-notion-ticket.sh TICK-### --status "Complete"

# Add PR URL
~/Dropbox/scripts/notion/manage-notion-ticket.sh TICK-### --pr-url https://github.com/org/repo/pull/123

# Complete ticket with summary
~/Dropbox/scripts/notion/manage-notion-ticket.sh TICK-### --status Complete --summary "Fixed the issue by updating CSS"

# Add notes without changing status
~/Dropbox/scripts/notion/manage-notion-ticket.sh TICK-### --notes "Working on feature X"

# Complete with everything
~/Dropbox/scripts/notion/manage-notion-ticket.sh TICK-### \
  --status Complete \
  --pr-url https://github.com/org/repo/pull/123 \
  --summary "## What was built
- Feature 1
- Feature 2

## Technical details
Fixed the authentication flow"
```

**Options:**
- `--status, -s` - Set ticket status (e.g., "Complete", "In Progress")
- `--pr-url, -p` - Set GitHub PR URL
- `--summary, --notes, -n` - Append content (supports markdown: ##, -, auto-emoji)

---

## 🛍️ Shopify Scripts

Located in `~/Dropbox/scripts/shopify/`

### setup-shopify-store.sh
Complete setup for NEW Shopify stores with Git and Claude Code integration.

**What it does:**
- Creates project directory structure
- Initializes Git repository with proper .gitignore
- Creates .clinerules for Claude Code optimization
- Generates README with workflow documentation
- Creates initial commit

**Usage:**
```bash
~/Dropbox/scripts/shopify/setup-shopify-store.sh <store-name>

# Example:
~/Dropbox/scripts/shopify/setup-shopify-store.sh newclient.myshopify.com
```

**After running:**
1. `cd ~/Dropbox/wwwroot/<store-name>`
2. Connect to GitHub: `git remote add origin <repo-url>`
3. Push: `git push -u origin main`
4. Connect GitHub to Shopify theme in admin
5. Start developing - push changes to GitHub, preview on Shopify

### add-clinerules-to-project.sh
Adds .clinerules to EXISTING Shopify projects that don't have it yet.

**What it does:**
- Detects if directory is a Shopify theme
- Creates comprehensive .clinerules file
- Commits to git if in a repository
- Provides safety checks before overwriting

**Usage:**
```bash
# Run from within the project directory:
~/Dropbox/scripts/shopify/add-clinerules-to-project.sh

# Or specify a path:
~/Dropbox/scripts/shopify/add-clinerules-to-project.sh ~/Dropbox/wwwroot/store.example.com
```

---

## 🚀 Quick Reference

### Starting a New Shopify Store
```bash
~/Dropbox/scripts/shopify/setup-shopify-store.sh <store-name>
cd ~/Dropbox/wwwroot/<store-name>
# Connect to GitHub, then start developing
```

### Adding Claude Code to Existing Store
```bash
cd ~/Dropbox/wwwroot/<store-name>
~/Dropbox/scripts/shopify/add-clinerules-to-project.sh
```

### Working on a Ticket
```bash
# Fetch ticket details
~/Dropbox/scripts/notion/fetch-notion-ticket.sh TICK-###

# Work on ticket...

# Update status
~/Dropbox/scripts/notion/manage-notion-ticket.sh TICK-### --status "In Progress"

# Complete ticket with PR and summary
~/Dropbox/scripts/notion/manage-notion-ticket.sh TICK-### \
  --status Complete \
  --pr-url https://github.com/org/repo/pull/123 \
  --summary "Fixed the issue by updating the component"
```

---

## 🔧 Adding Scripts to PATH (Optional)

To run scripts from anywhere without full paths:
```bash
echo 'export PATH="$HOME/Dropbox/scripts/notion:$HOME/Dropbox/scripts/shopify:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Then you can run:
```bash
setup-shopify-store.sh <store-name>
fetch-notion-ticket.sh TICK-###
```

---

## 📝 Notes

- All scripts have safety checks and colored output
- Scripts will prompt before overwriting existing files
- Use `--help` flag for detailed usage (where implemented)
- Scripts are designed to be idempotent (safe to run multiple times)

---

## 🆘 Troubleshooting

**Script won't run:**
```bash
chmod +x ~/Dropbox/scripts/shopify/script-name.sh
```

**Permission denied:**
- Check file permissions with `ls -la`
- Ensure you have write access to target directories

**Git errors:**
- Ensure you're in a git repository
- Check git status before running scripts

---

## 🤖 Claude Code Rules Management

### add-claude-rule
Quick script to add new Claude rule ideas to your global rules inbox.

**Usage:**
```bash
# Add a simple rule
add-claude-rule "Always check for existing API clients before creating new ones"

# Add detailed rule with pattern and proposed solution
add-claude-rule -p "Claude creates duplicate configs" -r "Search for config files before creating"

# Add with frequency
add-claude-rule -p "Missing error handling" -r "Add try/catch blocks" -f "3 times this week"

# Edit the inbox directly
add-claude-rule -e

# View current inbox
add-claude-rule -v

# View git history of rules changes
add-claude-rule -g
```

**Options:**
- `-p PATTERN` - Specify the pattern observed
- `-r RULE` - Specify the proposed rule
- `-f FREQUENCY` - How often this comes up
- `-e` - Edit the inbox file directly
- `-v` - View the current inbox
- `-g` - View rules with git log
- `-h` - Show help message

**Workflow:**
1. Notice a pattern as you work with Claude
2. Quickly capture it: `add-claude-rule "Your observation here"`
3. Script appends to `~/.claude/rules-inbox.md` with timestamp
4. Optionally commits to git
5. Review inbox weekly and promote useful rules to `~/.claude/rules.md`

**Files managed:**
- `~/.claude/rules.md` - Global rules Claude always reads
- `~/.claude/rules-inbox.md` - Pending rules to review
- `~/.claude/.git/` - Local git repo tracking rule changes

---

**Last updated:** November 8, 2025
