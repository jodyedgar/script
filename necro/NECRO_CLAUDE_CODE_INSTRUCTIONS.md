# NECRO SETUP - Instructions for Claude Code

## 📍 Location
Work in directory: `~/Dropbox/Scripts/Necro/`

## 🎯 Your Mission
Implement the complete Necro (project archaeology & cleanup) system according to the specifications in `NECRO_IMPLEMENTATION_GUIDE.md`.

## 📋 Quick Start

### 1. Read the Implementation Guide First
The file `NECRO_IMPLEMENTATION_GUIDE.md` contains the complete specification. Read it thoroughly before implementing.

### 2. Create Directory Structure
```bash
cd ~/Dropbox/Scripts/Necro
mkdir -p bin templates docs lib tests
```

### 3. Implementation Order

Implement in this exact order:

1. **lib/common.sh** - Shared functions and utilities
2. **bin/necro** - Main CLI wrapper
3. **bin/necro-init** - Project initializer
4. **bin/necro-inventory** - Project scanner
5. **bin/necro-deprecate** - Deprecation manager
6. **bin/necro-architecture** - Architecture doc generator
7. **bin/necro-test** - Test runner (placeholder)
8. **templates/*.template** - All template files
9. **docs/*.md** - All documentation files
10. **README.md** - Main Necro documentation

### 4. Make Scripts Executable
```bash
chmod +x bin/*
chmod +x lib/*
```

### 5. Test Each Component
Test each script as you build it:
```bash
./bin/necro --help
./bin/necro version
./bin/necro-init --help
# etc...
```

## 🔑 Key Requirements

### All Scripts Must:
- Source `lib/common.sh` for shared functions
- Use `#!/bin/bash` shebang
- Have a `--help` option
- Handle errors gracefully
- Use consistent color coding (from common.sh)
- Work on both macOS and Linux

### Color Usage:
- RED: Errors
- GREEN: Success
- YELLOW: Warnings/Prompts
- BLUE: Info/Paths
- PURPLE: Banners/Headers

### Behavior Standards:
- Never delete files, always move to `deprecated/YYYY-MM-DD/`
- Log all deprecations to `deprecated/DEPRECATION_LOG.md`
- Create full directory structure when moving files
- Confirm before destructive operations
- Provide clear, actionable error messages

## 📝 Script Specifications

### necro (Main CLI)
- Routes commands to appropriate scripts
- Shows help and version
- Supports: init, inventory, deprecate, arch, test, help, version
- Location: `bin/necro`

### necro-init
Initializes Necro in current project.

**Creates:**
- `.necro/config.json`
- `deprecated/` directory
- `deprecated/DEPRECATION_LOG.md`
- `ARCHITECTURE.md` from template

**Usage:**
```bash
necro init [--skip-git-hooks]
```

### necro-inventory
Scans project and generates timestamped inventory file.

**Output:** `PROJECT_INVENTORY_YYYYMMDD_HHMMSS.md`

**Scans:**
- Directory structure
- All source files by type
- Documentation
- Scripts (.sh, .ps1)
- Files not modified in N days (default: 30)
- Suspicious filenames (-old, -backup, .bak, -copy, -test, -tmp)
- Package.json scripts
- Git status

**Usage:**
```bash
necro inventory [--days N] [--output FILE]
```

### necro-deprecate
Manages file deprecation.

**Modes:**
1. Interactive: `necro deprecate` or `necro deprecate interactive`
2. Single file: `necro deprecate <file> [reason] [replacement]`
3. Batch: `necro deprecate batch <file-list> [reason]`
4. Clean: `necro deprecate clean [--days N]`
5. Log: `necro deprecate log`

**Behavior:**
- Moves to `deprecated/YYYY-MM-DD/original/path/`
- Preserves directory structure
- Logs to DEPRECATION_LOG.md
- Includes deprecation date, reason, replacement, deletion date

**Usage:**
```bash
necro deprecate                          # Interactive
necro deprecate old.js "replaced"        # Single file
necro deprecate batch list.txt "reason"  # Batch
necro deprecate clean --days 30          # Clean old
necro deprecate log                      # Show log
```

### necro-architecture
Generates/updates ARCHITECTURE.md.

**Sections:**
- Header with timestamp
- AI assistant warning
- Project structure (tree)
- Active directories and files
- Scripts
- Documentation
- Package.json scripts
- Git info
- Deprecated section warning
- Usage instructions

**Usage:**
```bash
necro arch [--output FILE]
```

### necro-test
Runs project tests (placeholder).

**Usage:**
```bash
necro test
```

## 📄 Templates to Create

### templates/ARCHITECTURE.md.template
```markdown
# Architecture - Current Active Files

**Last Updated:** {DATE}

> ⚠️ **Important for AI Assistants**: Only reference files listed in this document.
> Files in `/deprecated/` should be completely ignored.

---

## Project Structure

{STRUCTURE}

## Active Files

{FILES}

---

## ⛔ DO NOT USE - Deprecated

All files in `/deprecated/` are obsolete and should NOT be referenced.

Check `deprecated/DEPRECATION_LOG.md` for details on replacements.
```

### templates/DEPRECATED.md.template
```markdown
# Deprecated Files

## YYYY-MM-DD - [Feature/Component Name]

- **Files Deprecated:**
  - `path/to/file1.js`
  
- **Reason:** Brief explanation

- **Replacement:** New implementation location

- **Can Delete After:** YYYY-MM-DD
```

### templates/RESTART.md.template
```markdown
## Necro Cleanup System

Before debugging or major work:
1. Run `necro arch` to update ARCHITECTURE.md
2. Load ARCHITECTURE.md into Claude
3. Tell Claude: "Only reference files in ARCHITECTURE.md, ignore /deprecated/"

Weekly maintenance (Fridays):
- Run `necro inventory`
- Run `necro deprecate` to clean up zombies
- Run `necro deprecate clean` to remove old files (30+ days)
- Run `necro arch` to update documentation
```

## 📚 Documentation Files

### README.md
Main Necro documentation with:
- Purpose and overview
- Directory structure diagram
- Installation instructions (PATH setup)
- Quick start guide
- Core concepts explanation
- Complete command reference
- Workflow examples
- Claude Code integration guide
- Success metrics
- Troubleshooting

### docs/GETTING_STARTED.md
Step-by-step tutorial:
- Installation and PATH setup
- First project setup walkthrough
- Daily development workflow
- Weekly maintenance routine
- Claude Code integration
- Troubleshooting common issues

### docs/WORKFLOWS.md
Common workflow patterns:
- New project setup
- Daily development routine
- End of sprint cleanup
- Before major refactor
- Handling technical debt
- Team onboarding process

### docs/CLAUDE_RULES.md
AI integration guide:
- Global rules for Claude Code
- Session startup checklist
- Project-specific prompts
- Debugging with Claude
- Best practices
- Example prompts and workflows

## ✅ Testing Checklist

After implementation, verify:

```bash
cd ~/Dropbox/Scripts/Necro

# Test main CLI
./bin/necro --help              # Shows help
./bin/necro version             # Shows version
./bin/necro invalid             # Shows error + help

# Test in a project directory
cd ~/Dropbox/wwwroot/shopify-apps/hills-sync-app/

# Test init
necro init                      # Creates structure
ls -la .necro deprecated ARCHITECTURE.md

# Test inventory
necro inventory                 # Creates inventory file
cat PROJECT_INVENTORY_*.md      # Verify content

# Test deprecate
touch test-old-file.txt
necro deprecate test-old-file.txt "test" # Deprecates file
ls -la deprecated/$(date +%Y-%m-%d)/    # File is there
necro deprecate log                      # Shows log entry

# Test architecture
necro arch                      # Creates/updates ARCHITECTURE.md
cat ARCHITECTURE.md             # Verify content

# Cleanup test
rm -rf .necro deprecated ARCHITECTURE.md PROJECT_INVENTORY_*.md
```

## 🎯 Success Criteria

The implementation is complete when:

1. ✅ All 6 scripts exist and are executable
2. ✅ All templates are created
3. ✅ All documentation is written
4. ✅ `necro --help` shows clear usage
5. ✅ `necro init` creates all required files
6. ✅ `necro inventory` generates comprehensive scan
7. ✅ `necro deprecate` manages file moves correctly
8. ✅ `necro arch` generates proper documentation
9. ✅ All scripts handle errors gracefully
10. ✅ Colors display correctly

## 🚀 Post-Implementation

Tell the user to:

1. Add to PATH:
```bash
echo 'export PATH="$PATH:$HOME/Dropbox/Scripts/Necro/bin"' >> ~/.zshrc
source ~/.zshrc
```

2. Verify installation:
```bash
necro version
```

3. Try it in a project:
```bash
cd ~/path/to/project
necro init
necro inventory
```

## 💡 Implementation Tips

- Start with common.sh - other scripts depend on it
- Test each script individually before moving to next
- Use the implementation guide for detailed specs
- Keep scripts under 500 lines each
- Comment complex logic
- Use functions for reusable code
- Handle missing tools gracefully (e.g., tree, jq)
- Support both macOS and Linux date/stat commands

## 📖 Reference

Full specifications are in `NECRO_IMPLEMENTATION_GUIDE.md` - read it before implementing each component.

---

**Ready? Start with `lib/common.sh` and work through the implementation order above.**
