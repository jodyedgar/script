# Necro Workflows

Common workflow patterns for using Necro effectively in different scenarios.

## Table of Contents

1. [New Project Setup](#new-project-setup)
2. [Daily Development](#daily-development)
3. [End of Sprint Cleanup](#end-of-sprint-cleanup)
4. [Before Major Refactor](#before-major-refactor)
5. [Handling Technical Debt](#handling-technical-debt)
6. [Team Onboarding](#team-onboarding)
7. [AI Assistant Integration](#ai-assistant-integration)

---

## New Project Setup

### Initial Setup

```bash
cd ~/path/to/new-project

# Initialize Necro
necro init

# Generate initial inventory
necro inventory

# Create initial architecture documentation
necro arch

# Add to git
git add .necro/ deprecated/ ARCHITECTURE.md
git commit -m "Initialize Necro project archaeology system"
```

### Add to Project Documentation

Update your README.md or CONTRIBUTING.md:

```markdown
## Project Maintenance

This project uses Necro for managing technical debt and deprecated files.

- Run `necro arch` before starting work to update documentation
- Files in `/deprecated/` should not be referenced
- See `ARCHITECTURE.md` for current active files
```

---

## Daily Development

### Starting Your Work Session

```bash
# Update architecture documentation
necro arch

# Review current structure
cat ARCHITECTURE.md

# If working with AI assistant, load ARCHITECTURE.md first
```

### During Development

When you replace or remove files:

```bash
# Deprecate old implementation
necro deprecate src/old-feature.js "Replaced by new implementation" src/new-feature.js

# Update architecture docs
necro arch

# Continue working...
```

### End of Day

```bash
# Quick cleanup check
necro inventory --days 7

# Commit your changes
git add .
git commit -m "Your changes"
```

---

## End of Sprint Cleanup

### Complete Cleanup Routine

```bash
cd ~/path/to/project

# 1. Generate comprehensive inventory
necro inventory

# 2. Review inventory file
cat PROJECT_INVENTORY_*.md

# 3. Interactive deprecation of identified zombies
necro deprecate

# 4. Clean old deprecated files (30+ days)
necro deprecate clean --days 30

# 5. Update architecture documentation
necro arch

# 6. Review deprecation log
necro deprecate log

# 7. Commit cleanup
git add deprecated/ ARCHITECTURE.md
git commit -m "End of sprint: Necro cleanup

- Deprecated X files
- Cleaned deprecated files older than 30 days
- Updated architecture documentation"
```

### Create Cleanup Report

```bash
# Generate sprint cleanup summary
{
  echo "# Sprint Cleanup Report - $(date +%Y-%m-%d)"
  echo ""
  echo "## Files Deprecated This Sprint"
  tail -n 50 deprecated/DEPRECATION_LOG.md
  echo ""
  echo "## Current Project State"
  necro inventory --days 7
} > sprint-cleanup-report.md
```

---

## Before Major Refactor

### Pre-Refactor Checklist

```bash
cd ~/path/to/project

# 1. Create snapshot of current state
necro inventory --output refactor-baseline-$(date +%Y%m%d).md
necro arch --output ARCHITECTURE-BEFORE-REFACTOR.md

# 2. Identify files to be replaced
grep -r "old-pattern" src/ > files-to-refactor.txt

# 3. Create deprecation list
# Edit files-to-refactor.txt to be one file per line

# 4. Document refactor plan
echo "# Refactor Plan" > REFACTOR-PLAN.md
echo "Files to be deprecated:" >> REFACTOR-PLAN.md
cat files-to-refactor.txt >> REFACTOR-PLAN.md
```

### During Refactor

```bash
# As you complete each file replacement:
necro deprecate old-file.js "Refactored to new pattern" new-file.js

# Update architecture after major changes:
necro arch
```

### Post-Refactor

```bash
# Update documentation
necro arch

# Generate comparison report
{
  echo "# Refactor Report"
  echo ""
  echo "## Files Deprecated"
  tail -n 100 deprecated/DEPRECATION_LOG.md
  echo ""
  echo "## New Architecture"
  cat ARCHITECTURE.md
} > refactor-complete-report.md

# Cleanup
rm ARCHITECTURE-BEFORE-REFACTOR.md
rm REFACTOR-PLAN.md
```

---

## Handling Technical Debt

### Quarterly Technical Debt Sprint

```bash
# Week 1: Identify
cd ~/path/to/project
necro inventory --days 90 > tech-debt-inventory.md

# Review and categorize:
# - Dead code (can deprecate immediately)
# - Needs refactoring (schedule for later)
# - Still in use (leave alone)

# Week 2-3: Execute
# Create batch deprecation list
cat > batch-deprecate.txt <<EOF
# Dead code identified in Q1 2025
src/legacy/old-api.js
src/legacy/unused-utils.js
components/deprecated-ui.jsx
EOF

necro deprecate batch batch-deprecate.txt "Q1 2025 technical debt cleanup"

# Week 4: Documentation
necro arch
necro inventory  # New baseline

# Create report
{
  echo "# Q1 2025 Technical Debt Report"
  echo ""
  echo "## Files Deprecated"
  echo "Total: $(grep -c "^###" deprecated/DEPRECATION_LOG.md)"
  echo ""
  echo "## Categories"
  echo "- Dead code: X files"
  echo "- Legacy implementations: Y files"
  echo "- Unused utilities: Z files"
} > Q1-2025-tech-debt-report.md
```

### Finding Technical Debt

```bash
# Find old files (not modified in 90+ days)
necro inventory --days 90

# Find suspicious filenames
find . -type f \( \
  -name "*-old.*" -o \
  -name "*-backup.*" -o \
  -name "*.bak" -o \
  -name "*-copy.*" -o \
  -name "*-tmp.*" \
\) ! -path "*/node_modules/*" ! -path "*/deprecated/*"

# Find TODO comments in code
grep -r "TODO.*remove\|TODO.*delete\|TODO.*deprecated" src/
```

---

## Team Onboarding

### For New Team Members

```bash
# 1. Clone repository
git clone <repo-url>
cd <project>

# 2. Review architecture
cat ARCHITECTURE.md

# 3. Review restart guide
cat RESTART.md

# 4. Check recent deprecations
necro deprecate log | tail -n 50

# 5. Generate current inventory
necro inventory
```

### For Team Leads

Create onboarding checklist:

```markdown
# Project Onboarding Checklist

## Day 1: Project Structure
- [ ] Read ARCHITECTURE.md
- [ ] Read RESTART.md
- [ ] Run `necro inventory` to see project scope
- [ ] Review `deprecated/DEPRECATION_LOG.md`

## Week 1: Necro Basics
- [ ] Run `necro arch` before starting work
- [ ] Practice: deprecate a test file with `necro deprecate`
- [ ] Review weekly cleanup routine (Fridays)

## Month 1: Best Practices
- [ ] Include Necro in your daily workflow
- [ ] Update ARCHITECTURE.md before major work
- [ ] Participate in weekly cleanup
```

---

## AI Assistant Integration

### Session Startup with Claude Code

```bash
# 1. Update architecture
cd ~/path/to/project
necro arch

# 2. Load ARCHITECTURE.md into Claude
# (Claude will automatically see the file)

# 3. Add to your prompt:
# "Before we begin: Only reference files listed in ARCHITECTURE.md.
#  Completely ignore the /deprecated/ directory - those files are
#  obsolete and should not be used under any circumstances."
```

### Mid-Session Architecture Update

```bash
# If you've made significant changes:
necro arch

# Then tell Claude:
# "I've updated ARCHITECTURE.md with current project state.
#  Please refresh your understanding of the active files."
```

### When Claude References Deprecated Files

```markdown
User: "Claude, you just referenced /deprecated/old-api.js - that file is deprecated.
      Check ARCHITECTURE.md for the current implementation."

Claude: "You're right, I apologize. Let me check ARCHITECTURE.md for the current
         implementation..."
```

### Weekly AI Session Prep

```bash
# Every Monday or before major AI work:
necro arch
necro inventory --days 7  # Review recent changes

# Then in your AI session:
# "Here's the current ARCHITECTURE.md. Please only reference these active files.
#  The /deprecated/ directory is off-limits."
```

---

## Tips and Best Practices

### Make It a Habit

- **Daily**: Run `necro arch` before AI sessions
- **Weekly**: Full cleanup routine (Fridays)
- **Monthly**: Review deprecation log and clean old files
- **Quarterly**: Technical debt sprint

### Commit Often

```bash
# After deprecations
git add deprecated/ DEPRECATION_LOG.md ARCHITECTURE.md
git commit -m "Deprecate old implementation"

# After cleanup
git add .
git commit -m "Weekly Necro cleanup"
```

### Use Descriptive Reasons

Good deprecation reasons:
- "Replaced by new implementation in src/v2/"
- "Feature removed in release 2.0"
- "Superseded by new design system"
- "Merged functionality into core module"

Poor deprecation reasons:
- "Old"
- "Not needed"
- "Cleanup"

### Document Replacements

Always provide replacement information:
```bash
necro deprecate old-api.js "Replaced by REST API" src/api/rest.js
```

### Review Before Deleting

Before running `necro deprecate clean`:
1. Review the deprecation log
2. Check that replacements are working
3. Confirm with team if unsure
4. Start with longer retention (60+ days) until confident

---

## Common Scenarios

### Scenario: Feature Flag Cleanup

```bash
# Feature flag removed, clean up old code
necro deprecate src/features/old-feature/ "Feature flag removed, using new implementation"
necro arch
```

### Scenario: Dependency Update

```bash
# Old package wrapper deprecated
necro deprecate src/utils/old-http-client.js "Updated to axios v2" src/utils/http-client.js
necro arch
```

### Scenario: Design System Migration

```bash
# Batch deprecate old components
cat > old-components.txt <<EOF
components/Button-old.jsx
components/Input-old.jsx
components/Modal-old.jsx
EOF

necro deprecate batch old-components.txt "Migrated to new design system"
necro arch
```

### Scenario: Monorepo Reorganization

```bash
# Files moved to packages/
necro inventory  # Identify moved files
necro deprecate batch moved-files.txt "Reorganized into monorepo structure"
necro arch
```

---

## Automation Ideas

### Git Hook for Auto-Update

Create `.git/hooks/post-merge`:

```bash
#!/bin/bash
# Auto-update architecture after git pull
if command -v necro >/dev/null 2>&1; then
    echo "Updating architecture documentation..."
    necro arch
fi
```

### CI/CD Integration

Add to your CI pipeline:

```yaml
# .github/workflows/necro-check.yml
name: Necro Check
on: [pull_request]
jobs:
  check-deprecated:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Check for deprecated imports
        run: |
          if grep -r "from.*deprecated/" src/; then
            echo "Error: PR contains imports from deprecated files"
            exit 1
          fi
```

### Weekly Cron Job

Add to crontab for automatic weekly cleanup:

```bash
# Run every Friday at 5 PM
0 17 * * 5 cd ~/path/to/project && necro inventory && necro arch
```

---

**Remember**: Necro is a tool to support your workflow, not replace your judgment. Use it to build better habits and keep your projects maintainable.