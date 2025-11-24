# Necro System - Implementation Guide for Claude Code

## 🎯 Overview

You are setting up **Necro**, a project archaeology and cleanup system for managing technical debt across all Sunbowl Systems projects. This system prevents AI coding tools from getting confused by deprecated files and zombie code.

## 📁 Target Directory Structure

Create this structure at: `~/Dropbox/Scripts/Necro/`

```
Necro/
├── README.md                   # Main documentation
├── bin/                        # Executable scripts
│   ├── necro                  # Main CLI wrapper
│   ├── necro-init             # Initialize Necro in a project
│   ├── necro-inventory        # Generate project inventory
│   ├── necro-deprecate        # Manage deprecations
│   ├── necro-architecture     # Update architecture docs
│   └── necro-test             # Test runner
├── templates/                  # Project templates
│   ├── ARCHITECTURE.md.template
│   ├── DEPRECATED.md.template
│   └── RESTART.md.template
├── docs/                       # Documentation
│   ├── GETTING_STARTED.md
│   ├── WORKFLOWS.md
│   └── CLAUDE_RULES.md
├── lib/                        # Shared libraries
│   └── common.sh              # Common bash functions
└── tests/                      # Test utilities
    └── test-runner.sh
```

## 🚀 Implementation Instructions

### Phase 1: Core CLI Structure

1. **Create `bin/necro`** - Main CLI entry point
   - Version: 1.0.0
   - Routes commands to appropriate scripts
   - Shows help and usage information
   - Colorful banner and output

2. **Create shared library `lib/common.sh`**
   - Color definitions (RED, GREEN, YELLOW, BLUE, PURPLE, NC)
   - Common functions:
     - `log_info()` - Info message
     - `log_success()` - Success message
     - `log_error()` - Error message
     - `log_warning()` - Warning message
     - `confirm()` - Yes/no prompt
     - `get_project_root()` - Find project root (looks for package.json, .git, etc)

### Phase 2: Core Commands

#### `bin/necro-init`
Initialize Necro in the current project directory.

**Creates:**
- `.necro/` directory with config
- `.necro/config.json` with project settings
- `deprecated/` directory
- `deprecated/DEPRECATION_LOG.md`
- `ARCHITECTURE.md` (from template)
- Adds entries to `RESTART.md` if it exists

**Options:**
- `--skip-git-hooks` - Don't install git hooks
- `--help` - Show help

#### `bin/necro-inventory`
Scan project and generate comprehensive inventory.

**Output file:** `PROJECT_INVENTORY_YYYYMMDD_HHMMSS.md`

**Scans for:**
- Directory structure (3 levels deep, ignore node_modules, .git, dist, build, deprecated)
- All .md files with size, date, preview
- All .js/.ts/.jsx/.tsx files organized by directory
- All .ps1 PowerShell scripts
- All .sh shell scripts
- Files not modified in 30+ days
- Suspicious filenames: *-old.*, *-backup.*, *.bak, *-copy.*, *-test.*, *-tmp.*
- Package.json scripts if exists
- Git status and untracked files

**Options:**
- `--days N` - Find files older than N days (default: 30)
- `--output FILE` - Custom output filename
- `--help` - Show help

#### `bin/necro-deprecate`
Manage file deprecation with dated archive structure.

**Modes:**
1. **Interactive** (`necro deprecate` or `necro deprecate interactive`)
   - Prompt for file path
   - Prompt for reason
   - Prompt for replacement (optional)
   - Loop until 'done'

2. **Single file** (`necro deprecate <file> [reason] [replacement]`)
   - Deprecate one file with optional reason and replacement

3. **Batch** (`necro deprecate batch <file-list> [reason]`)
   - Read file paths from text file (one per line, # for comments)
   - Deprecate all with same reason

4. **Clean** (`necro deprecate clean [--days N]`)
   - Remove deprecated files older than N days (default: 30)
   - Prompt for confirmation before deleting each dated folder

5. **Log** (`necro deprecate log`)
   - Show deprecation log

**Behavior:**
- Moves files to `deprecated/YYYY-MM-DD/original/path/structure/`
- Logs to `deprecated/DEPRECATION_LOG.md` with:
  - Date deprecated
  - Original path
  - New location
  - Reason
  - Replacement (if any)
  - Can delete after date (30 days from deprecation)
- Creates full directory structure in deprecated folder

**Options:**
- `--days N` - For clean mode, days to keep (default: 30)
- `--help` - Show help

#### `bin/necro-architecture`
Generate/update ARCHITECTURE.md with current project state.

**Generates sections:**
1. Header with last updated timestamp
2. Warning for AI assistants to only use active files
3. Project structure (tree view)
4. Active source directories
5. Core application files (functions/, src/, etc)
6. Scripts (shell and PowerShell)
7. Documentation files (.md files, excluding ARCHITECTURE, README, RESTART, DEPRECATED)
8. Package.json scripts (if exists)
9. Git information (branch, recent commits)
10. "DO NOT USE - Deprecated" section pointing to deprecated/
11. Usage instructions

**Options:**
- `--output FILE` - Custom output filename (default: ARCHITECTURE.md)
- `--help` - Show help

#### `bin/necro-test`
Run project-specific tests (placeholder for now).

**Behavior:**
- Look for `.necro/config.json` test configuration
- If not configured, show message about setting up tests
- Run configured test commands

**Options:**
- `--help` - Show help

### Phase 3: Templates

#### `templates/ARCHITECTURE.md.template`
Template for project architecture documentation.

**Sections:**
- Project structure placeholder
- Active files placeholder
- Deprecated warning
- Usage instructions for humans and AI

#### `templates/DEPRECATED.md.template`
Optional running log of deprecations.

**Format:**
```markdown
# Deprecated Files

## YYYY-MM-DD - [Feature/Component Name]

- **Files Deprecated:**
  - `path/to/file1.js`
  - `path/to/file2.js`

- **Reason:** Brief explanation

- **Replacement:** New implementation location

- **Can Delete After:** YYYY-MM-DD
```

#### `templates/RESTART.md.template`
Template entries for project RESTART.md files.

**Includes:**
- Necro workflow reminders
- Commands to run before debugging
- Weekly maintenance schedule
- Claude Code integration tips

### Phase 4: Documentation

#### `README.md`
Main Necro documentation covering:
- Purpose and overview
- Directory structure
- Installation (PATH setup)
- Quick start guide
- Core concepts (archaeology, deprecation, architecture docs, Claude rules)
- Command reference
- Workflow examples (daily, weekly, before debugging)
- Claude Code integration
- Templates info
- Success metrics
- Troubleshooting

#### `docs/GETTING_STARTED.md`
Step-by-step guide for:
- Installation and PATH setup
- First project setup
- Daily workflow
- Weekly maintenance
- Claude Code integration
- Troubleshooting

#### `docs/WORKFLOWS.md`
Common workflow patterns:
- New project setup
- Daily development routine
- End of sprint cleanup
- Before major refactor
- Handling technical debt
- Team onboarding

#### `docs/CLAUDE_RULES.md`
Integration guide for AI coding tools:
- Global rules for Claude Code
- Project-specific prompts
- Session startup checklist
- Debugging with Claude
- Best practices
- Example prompts

### Phase 5: Implementation Details

#### Error Handling
All scripts should:
- Check if required tools exist (git, jq if used)
- Validate file paths before operations
- Use `set -e` for critical operations (but not in main scripts where we want to continue)
- Provide clear error messages
- Exit with appropriate codes (0 = success, 1 = error)

#### Output Formatting
- Use colors consistently:
  - RED: Errors
  - GREEN: Success
  - YELLOW: Warnings/prompts
  - BLUE: Info/paths
  - PURPLE: Banners/headers
- Keep output clean and scannable
- Use symbols: ✓ ✗ → ⚠️
- Show progress for long operations

#### File Operations
- Always preserve directory structure when moving to deprecated/
- Use `mkdir -p` to create nested directories
- Confirm before destructive operations
- Keep backups for 30 days minimum

#### Git Integration (Optional)
- Check if in git repo before git operations
- Don't fail if not in git repo
- Suggest git add for generated files

## 🎯 Key Principles

1. **Safety First**: Never delete files, always move to deprecated/
2. **Clear Audit Trail**: Log everything to DEPRECATION_LOG.md
3. **AI-Friendly**: Make it obvious what's active vs deprecated
4. **Cross-Project**: Work consistently across all project types
5. **Automation-Ready**: Easy to integrate with CI/CD and Notion workflows

## 📋 Testing Checklist

After implementation, test:
- [ ] `necro --help` shows usage
- [ ] `necro version` shows version
- [ ] `necro init` creates all directories and files
- [ ] `necro inventory` generates inventory file
- [ ] `necro deprecate interactive` prompts correctly
- [ ] `necro deprecate <file> "reason"` moves file to dated folder
- [ ] `necro deprecate log` shows deprecation log
- [ ] `necro deprecate clean` removes old files
- [ ] `necro arch` generates ARCHITECTURE.md
- [ ] All scripts have `--help` option
- [ ] Colors display correctly
- [ ] Errors are handled gracefully

## 🚀 Getting Started

1. Create the directory structure at `~/Dropbox/Scripts/Necro/`
2. Implement scripts in order: common.sh → necro → necro-* commands
3. Create templates
4. Write documentation
5. Make all scripts in bin/ executable: `chmod +x bin/*`
6. Test each command
7. Tell user to add to PATH: `export PATH="$PATH:$HOME/Dropbox/Scripts/Necro/bin"`

## 💡 Implementation Notes

- All scripts should source `lib/common.sh` for shared functions
- Use `#!/bin/bash` shebang (not /bin/sh)
- Support both macOS and Linux where possible
- Handle missing tools gracefully (e.g., `tree` command)
- Keep scripts under 500 lines each for maintainability
- Use clear variable names (NECRO_HOME, PROJECT_ROOT, etc)
- Comment complex logic
- Use functions for reusable code blocks

## 🎨 Example Output Formats

### necro init
```
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   NECRO - Initializing Project                           ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

Project: /path/to/project

✓ Created .necro/ directory
✓ Created deprecated/ directory
✓ Created ARCHITECTURE.md
✓ Created DEPRECATION_LOG.md
✓ Updated RESTART.md

✅ Necro initialized successfully!

Next steps:
  1. Run: necro inventory
  2. Review inventory and identify files to deprecate
  3. Run: necro deprecate
  4. Update architecture: necro arch
```

### necro deprecate interactive
```
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   NECRO - Interactive Deprecation                        ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

Enter file path to deprecate (or 'done' to finish):
> ./old-feature.md

Reason for deprecation:
> Replaced by new implementation

Replacement file path (press Enter if none):
> ./features/new-feature.md

✓ Deprecated: old-feature.md
  → deprecated/2025-11-23/old-feature.md

Enter file path to deprecate (or 'done' to finish):
> done

✅ Deprecation complete!
   Deprecated: 1 file
   Log: deprecated/DEPRECATION_LOG.md
```

## 🔧 Optional Enhancements (Future)

- Git hooks integration
- Notion API integration for automated tickets
- GitHub Actions workflow
- Dependency analysis (unused imports)
- Code complexity metrics
- Visual reports (HTML output)
- IDE plugins
- Team collaboration features

---

**This guide provides everything needed to implement Necro from scratch. Follow the phases in order and test thoroughly at each step.**
