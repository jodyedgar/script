# Getting Started with Necro

This guide will walk you through setting up and using Necro in your projects.

## What is Necro?

Necro is a project archaeology and cleanup system that helps you:
- Track and manage deprecated files
- Generate project documentation for AI assistants
- Keep technical debt under control
- Prevent zombie code from confusing developers and AI tools

## Installation

### 1. Add Necro to Your PATH

Add the Necro bin directory to your PATH:

```bash
echo 'export PATH="$PATH:$HOME/Dropbox/Scripts/Necro/bin"' >> ~/.zshrc
source ~/.zshrc
```

For bash users:
```bash
echo 'export PATH="$PATH:$HOME/Dropbox/Scripts/Necro/bin"' >> ~/.bashrc
source ~/.bashrc
```

### 2. Verify Installation

```bash
necro version
```

You should see the Necro banner and version information.

## First Project Setup

Let's set up Necro in your first project.

### Step 1: Navigate to Your Project

```bash
cd ~/path/to/your/project
```

### Step 2: Initialize Necro

```bash
necro init
```

This creates:
- `.necro/` directory with configuration
- `deprecated/` directory for archived files
- `ARCHITECTURE.md` for active files documentation
- `deprecated/DEPRECATION_LOG.md` for tracking changes

### Step 3: Generate Project Inventory

```bash
necro inventory
```

This scans your project and creates a timestamped inventory file showing:
- Directory structure
- All source files
- Documentation
- Scripts
- Old files (30+ days)
- Suspicious filenames (backup, old, tmp, etc.)
- Git status

Review the inventory file to identify files that should be deprecated.

### Step 4: Deprecate Old Files

Start the interactive deprecation tool:

```bash
necro deprecate
```

Or deprecate a specific file:

```bash
necro deprecate path/to/old-file.js "Replaced by new implementation" path/to/new-file.js
```

Files are moved to `deprecated/YYYY-MM-DD/` maintaining their original directory structure.

### Step 5: Update Architecture Documentation

```bash
necro arch
```

This generates/updates `ARCHITECTURE.md` with current active files. Share this with your team and AI assistants.

## Daily Development Workflow

### Starting a Work Session

```bash
cd ~/path/to/project
necro arch              # Update architecture docs
cat ARCHITECTURE.md     # Review current structure
```

### When Using AI Assistants

1. Load `ARCHITECTURE.md` into your AI tool (Claude, GitHub Copilot, etc.)
2. Tell the AI: "Only reference files listed in ARCHITECTURE.md. Completely ignore the /deprecated/ directory."
3. The AI will now only work with active, current files

### Deprecating Files

When you replace or remove files:

```bash
necro deprecate old-component.tsx "Replaced by new design system"
necro arch  # Update documentation
```

## Weekly Maintenance Routine

Run these commands every Friday (or your preferred schedule):

```bash
# 1. Generate fresh inventory
necro inventory

# 2. Review and deprecate zombie files
necro deprecate

# 3. Clean up old deprecated files (30+ days)
necro deprecate clean --days 30

# 4. Update architecture documentation
necro arch

# 5. Commit changes
git add deprecated/ ARCHITECTURE.md
git commit -m "Weekly Necro cleanup"
```

## Working with Teams

### Onboarding New Team Members

Share these files with new team members:
- `ARCHITECTURE.md` - Current project structure
- `RESTART.md` - Project setup instructions
- `deprecated/DEPRECATION_LOG.md` - History of changes

### Code Reviews

Before reviewing code:
1. Run `necro arch` to ensure documentation is current
2. Check ARCHITECTURE.md to understand current structure
3. Verify changes don't reference deprecated files

### Pull Requests

Include in your PR checklist:
- [ ] Deprecated old files if replacing implementations
- [ ] Updated ARCHITECTURE.md with `necro arch`
- [ ] Added deprecation reasons to DEPRECATION_LOG.md

## Advanced Usage

### Batch Deprecation

Create a file with paths to deprecate (one per line):

```text
# cleanup-list.txt
old-feature/component1.js
old-feature/component2.js
old-feature/tests.js
```

Then run:

```bash
necro deprecate batch cleanup-list.txt "Removed old feature"
```

### Custom Output Locations

```bash
necro inventory --output reports/inventory-$(date +%Y%m%d).md
necro arch --output docs/ARCHITECTURE.md
```

### Custom Retention Period

```bash
necro deprecate clean --days 60  # Keep deprecated files for 60 days
```

## Troubleshooting

### Command Not Found

If `necro` command isn't found:
1. Check PATH: `echo $PATH` should include Necro/bin
2. Re-source your shell config: `source ~/.zshrc`
3. Verify installation: `ls ~/Dropbox/Scripts/Necro/bin/necro`

### Permission Denied

Make scripts executable:
```bash
chmod +x ~/Dropbox/Scripts/Necro/bin/*
```

### Git Integration Issues

Necro works with or without git. If you see git warnings but don't use git, these can be safely ignored.

### Tree Command Not Found

The `tree` command provides better visualization but is optional. Install it:

```bash
# macOS
brew install tree

# Linux (Ubuntu/Debian)
sudo apt-get install tree
```

## Next Steps

- Read [WORKFLOWS.md](WORKFLOWS.md) for common workflow patterns
- Read [CLAUDE_RULES.md](CLAUDE_RULES.md) for AI assistant integration
- Explore all commands with `necro help`

## Getting Help

- Run `necro help` for command overview
- Run `necro <command> --help` for specific command help
- Check the main README.md for detailed documentation
- Review example workflows in WORKFLOWS.md

---

**Remember**: The goal of Necro is to make your project cleaner and more maintainable. Start small, deprecate incrementally, and build the habit of regular cleanup.
