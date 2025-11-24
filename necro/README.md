# Necro - Project Archaeology & Cleanup System

**Version 1.0.0**

Necro is a project archaeology and cleanup system for managing technical debt across all your projects. It prevents AI coding tools from getting confused by deprecated files and zombie code.

## The Problem

Modern projects accumulate zombie code:
- Old implementations sitting next to new ones
- Files named `component-old.js`, `backup-api.js`, `test-version.tsx`
- Forgotten experiments and prototypes
- Deprecated features that never got removed

This creates two major issues:

1. **For Developers**: Visual clutter, confusion about which files are current, accidental use of deprecated code

2. **For AI Assistants**: Claude, GitHub Copilot, and other AI tools see EVERYTHING in your codebase. They can't distinguish between active code and deprecated files, leading to:
   - Suggestions based on deprecated patterns
   - References to obsolete implementations
   - Confusion about project architecture
   - Mixing old and new approaches

## The Solution

Necro provides:

1. **Dated Deprecation Archive** - Files moved to `deprecated/YYYY-MM-DD/` with original directory structure preserved
2. **Clear Audit Trail** - Complete log of what was deprecated, when, why, and what replaced it
3. **Architecture Documentation** - Auto-generated `ARCHITECTURE.md` listing only active files
4. **AI-Friendly Boundaries** - Explicit documentation for AI assistants about what to ignore

## Directory Structure

```
Necro/
├── README.md                   # This file
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
```

## Quick Start

### Installation

1. Add Necro to your PATH:

```bash
echo 'export PATH="$PATH:$HOME/Dropbox/Scripts/Necro/bin"' >> ~/.zshrc
source ~/.zshrc
```

2. Verify installation:

```bash
necro version
```

### Your First Project

```bash
# Navigate to your project
cd ~/path/to/project

# Initialize Necro
necro init

# Generate inventory to see what's in your project
necro inventory

# Deprecate an old file
necro deprecate old-component.js "Replaced by new implementation"

# Update architecture documentation
necro arch
```

## Core Concepts

### 1. Project Archaeology

Necro helps you understand your project by scanning and documenting:
- Directory structure
- All source files by type
- Documentation
- Scripts
- Old files (30+ days unmodified)
- Suspicious filenames (backup, old, tmp, etc.)

**Command**: `necro inventory`

### 2. Deprecation Management

Instead of deleting files, move them to a dated archive:
- Files go to `deprecated/YYYY-MM-DD/original/path/`
- Full directory structure preserved
- Complete audit trail in DEPRECATION_LOG.md
- 30-day retention before safe deletion

**Command**: `necro deprecate`

### 3. Architecture Documentation

Generate `ARCHITECTURE.md` that lists only active, current files:
- Explicit instruction for AI assistants
- Clear boundaries between active and deprecated code
- Project structure and file listings
- Regular updates maintain accuracy

**Command**: `necro arch`

### 4. Claude Code Integration

Special instructions for AI assistants:
- Load ARCHITECTURE.md before sessions
- Ignore /deprecated/ directory completely
- Only reference files explicitly listed as active
- Clear, enforced boundaries

**See**: `docs/CLAUDE_RULES.md`

## Command Reference

### necro

Main CLI wrapper. Routes commands to appropriate scripts.

```bash
necro <command> [options]
```

**Commands**:
- `init` - Initialize Necro in current project
- `inventory` - Generate project inventory scan
- `deprecate` - Manage file deprecation
- `arch` - Generate/update ARCHITECTURE.md
- `test` - Run project tests
- `help` - Show help message
- `version` - Show version information

### necro init

Initialize Necro in the current project.

```bash
necro init [options]
```

**Creates**:
- `.necro/config.json` - Project configuration
- `deprecated/` - Directory for archived files
- `deprecated/DEPRECATION_LOG.md` - Audit trail
- `ARCHITECTURE.md` - Architecture documentation

**Options**:
- `--skip-git-hooks` - Don't install git hooks
- `--help` - Show help message

### necro inventory

Scan project and generate comprehensive inventory.

```bash
necro inventory [options]
```

**Generates**: `PROJECT_INVENTORY_YYYYMMDD_HHMMSS.md`

**Scans**:
- Directory structure (3 levels)
- All documentation (.md files)
- JavaScript/TypeScript files
- Shell scripts (.sh)
- PowerShell scripts (.ps1)
- Files not modified in N days
- Suspicious filenames
- Package.json scripts
- Git status and untracked files

**Options**:
- `--days N` - Find files older than N days (default: 30)
- `--output FILE` - Custom output filename
- `--help` - Show help message

### necro deprecate

Manage file deprecation with multiple modes.

```bash
necro deprecate [mode] [options]
```

**Modes**:

1. **Interactive** (default):
   ```bash
   necro deprecate
   # or
   necro deprecate interactive
   ```
   Prompts for file path, reason, and replacement.

2. **Single file**:
   ```bash
   necro deprecate <file> [reason] [replacement]
   ```
   Deprecate one file with optional reason and replacement.

3. **Batch**:
   ```bash
   necro deprecate batch <file-list> [reason]
   ```
   Read file paths from text file (one per line).

4. **Clean**:
   ```bash
   necro deprecate clean [--days N]
   ```
   Remove deprecated files older than N days (default: 30).

5. **Log**:
   ```bash
   necro deprecate log
   ```
   Show deprecation log.

**Options**:
- `--days N` - For clean mode, days to keep (default: 30)
- `--help` - Show help message

**Behavior**:
- Moves files to `deprecated/YYYY-MM-DD/original/path/`
- Preserves directory structure
- Logs to `DEPRECATION_LOG.md`
- Includes date, reason, replacement, deletion date

### necro arch

Generate/update ARCHITECTURE.md with current project state.

```bash
necro arch [options]
```

**Generates sections**:
- Header with timestamp
- Warning for AI assistants
- Project structure
- Active source directories
- Core application files
- Scripts
- Documentation
- Package.json scripts
- Git information
- Deprecated section warning
- Usage instructions

**Options**:
- `--output FILE` - Custom output filename (default: ARCHITECTURE.md)
- `--help` - Show help message

### necro test

Run project-specific tests (placeholder for now).

```bash
necro test [options]
```

**Options**:
- `--help` - Show help message

## Workflow Examples

### Daily Development

```bash
# Start of day
cd ~/path/to/project
necro arch              # Update architecture docs

# Work on feature...

# Deprecate old implementation
necro deprecate src/old-feature.js "Replaced by new implementation"

# Update docs
necro arch
```

### Weekly Cleanup (Recommended: Fridays)

```bash
# 1. Generate inventory
necro inventory

# 2. Review and deprecate zombies
necro deprecate

# 3. Clean old deprecated files (30+ days)
necro deprecate clean --days 30

# 4. Update architecture
necro arch

# 5. Commit changes
git add deprecated/ ARCHITECTURE.md
git commit -m "Weekly Necro cleanup"
```

### Before Debugging with Claude

```bash
# Update architecture documentation
necro arch

# Start Claude session and say:
# "This project uses Necro. Only reference files in ARCHITECTURE.md.
#  Completely ignore /deprecated/ directory."
```

### End of Sprint

```bash
# Comprehensive cleanup
necro inventory --days 7
necro deprecate batch sprint-cleanup-list.txt "End of sprint cleanup"
necro deprecate clean --days 30
necro arch

# Generate report
{
  echo "# Sprint Cleanup Report"
  tail -n 50 deprecated/DEPRECATION_LOG.md
} > sprint-cleanup-report.md
```

## Claude Code Integration

Necro is designed to work seamlessly with Claude Code and other AI assistants.

### Session Startup

1. **Update architecture**:
   ```bash
   necro arch
   ```

2. **Start session with**:
   ```markdown
   This project uses Necro for deprecated file management.

   IMPORTANT RULES:
   - Only reference files listed in ARCHITECTURE.md
   - Completely ignore the /deprecated/ directory
   - Those files are obsolete and should not be used

   Please review ARCHITECTURE.md before we begin.
   ```

3. **If Claude references deprecated files**:
   ```markdown
   Stop - that file is in /deprecated/ and should not be used.
   Check ARCHITECTURE.md for the current implementation.
   ```

See `docs/CLAUDE_RULES.md` for comprehensive AI integration guide.

## Templates

Necro includes templates for common project files:

### ARCHITECTURE.md Template
- Header with timestamp
- AI assistant warning
- Project structure
- Active files listing
- Deprecated directory warning

### DEPRECATED.md Template
- Structured deprecation entries
- Reason and replacement tracking
- Deletion date tracking

### RESTART.md Template
- Necro workflow reminders
- Commands to run before debugging
- Weekly maintenance schedule
- Claude Code integration tips

## Success Metrics

You'll know Necro is working when:

1. **Reduced Confusion** - Developers and AI know exactly which files are current
2. **Faster Onboarding** - New team members see clean, documented structure
3. **Better AI Sessions** - Claude/Copilot reference only active code
4. **Less Technical Debt** - Regular cleanup becomes routine
5. **Clear Audit Trail** - Always know why files were deprecated
6. **Confidence in Deletion** - 30-day retention means safe cleanup

## Best Practices

### Do This

- ✅ Run `necro arch` before AI sessions
- ✅ Deprecate files immediately when replacing them
- ✅ Include reason and replacement in deprecations
- ✅ Review deprecation log before permanent deletion
- ✅ Make weekly cleanup a team routine
- ✅ Load ARCHITECTURE.md at start of Claude sessions

### Don't Do This

- ❌ Delete files directly - use deprecation
- ❌ Leave deprecated files in source directories
- ❌ Use vague deprecation reasons ("old", "cleanup")
- ❌ Let deprecated files accumulate indefinitely
- ❌ Skip architecture updates
- ❌ Let AI assistants reference deprecated code

## Troubleshooting

### Command Not Found

Check your PATH:
```bash
echo $PATH | grep Necro
```

If not found, re-add to shell config:
```bash
echo 'export PATH="$PATH:$HOME/Dropbox/Scripts/Necro/bin"' >> ~/.zshrc
source ~/.zshrc
```

### Permission Denied

Make scripts executable:
```bash
chmod +x ~/Dropbox/Scripts/Necro/bin/*
```

### Tree Command Not Found

Install tree for better visualization:
```bash
# macOS
brew install tree

# Linux (Ubuntu/Debian)
sudo apt-get install tree
```

### Git Integration Issues

Necro works with or without git. Git warnings can be safely ignored if you don't use git.

## Documentation

- **Getting Started**: `docs/GETTING_STARTED.md` - Step-by-step tutorial
- **Workflows**: `docs/WORKFLOWS.md` - Common workflow patterns
- **Claude Rules**: `docs/CLAUDE_RULES.md` - AI assistant integration

## Project Structure in Your Projects

After running `necro init`, your project will have:

```
your-project/
├── .necro/
│   └── config.json           # Necro configuration
├── deprecated/               # Deprecated files archive
│   ├── DEPRECATION_LOG.md   # Audit trail
│   ├── 2025-01-15/          # Files deprecated Jan 15, 2025
│   ├── 2025-01-22/          # Files deprecated Jan 22, 2025
│   └── ...
├── ARCHITECTURE.md          # Current active files
└── [your source files]
```

## Contributing

Necro is maintained by Sunbowl Systems as an internal tool for managing project technical debt.

## Version History

- **1.0.0** (2025-11-23) - Initial release
  - Core CLI framework
  - Project initialization
  - Inventory generation
  - Deprecation management
  - Architecture documentation
  - Template system
  - Comprehensive documentation

## License

Internal use - Sunbowl Systems

---

## Getting Help

- Run `necro help` for command overview
- Run `necro <command> --help` for specific command help
- Read `docs/GETTING_STARTED.md` for tutorial
- Check `docs/WORKFLOWS.md` for examples
- See `docs/CLAUDE_RULES.md` for AI integration

## Philosophy

**"The best code is code you can trust. Clean up the past, document the present, prepare for the future."**

Necro helps you build trust in your codebase by:
- Making deprecated code explicit
- Providing clear boundaries
- Maintaining complete history
- Enabling confident cleanup
- Supporting AI-assisted development

Start using Necro today and take control of your project's technical debt!