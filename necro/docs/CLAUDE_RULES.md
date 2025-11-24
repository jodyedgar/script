# Claude Code Integration Guide

This guide shows how to integrate Necro with Claude Code and other AI coding assistants to prevent them from referencing deprecated files.

## The Problem

AI coding assistants can see your entire codebase, including:
- Old implementations in `/deprecated/`
- Zombie code that should be removed
- Outdated patterns and anti-patterns
- Backup files and temporary experiments

This causes AI assistants to:
- Reference obsolete files
- Suggest deprecated patterns
- Mix old and new implementations
- Create confusion about what's current

## The Solution: Necro + Claude Code

Necro creates `ARCHITECTURE.md` that explicitly lists only active, current files. By loading this document first and providing clear instructions, you can guide AI assistants to ignore deprecated code.

---

## Global Rules for Claude Code

### Create a Global Rule

If your Claude Code supports global rules or custom instructions, add this:

```markdown
# Necro Project Archaeology

When working on projects that use Necro (indicated by presence of ARCHITECTURE.md and /deprecated/ directory):

1. **ALWAYS** read ARCHITECTURE.md first before making suggestions
2. **NEVER** reference files in /deprecated/ directory
3. **ONLY** use files explicitly listed in ARCHITECTURE.md
4. If uncertain whether a file is active, ask the user
5. If you catch yourself referencing a deprecated file, immediately stop and apologize

The /deprecated/ directory contains obsolete code maintained only for historical reference (30 days). These files should be completely ignored.
```

---

## Session Startup Checklist

For each new Claude Code session on a Necro-enabled project:

### 1. Update Architecture Documentation

```bash
cd ~/path/to/project
necro arch
```

### 2. Open ARCHITECTURE.md

Claude Code will automatically see the file in your project.

### 3. Start Session with Clear Instructions

Begin your conversation with:

```markdown
I'm working on a project that uses Necro for managing deprecated files.

IMPORTANT RULES:
- Only reference files listed in ARCHITECTURE.md
- Completely ignore the /deprecated/ directory
- Those files are obsolete and should not be used
- If you're unsure if a file is active, check ARCHITECTURE.md or ask me

Let's start by reviewing ARCHITECTURE.md to understand the current project structure.
```

---

## Project-Specific Prompts

### Starting a Feature

```markdown
I need to add [feature description].

Before we start:
1. Review ARCHITECTURE.md for current project structure
2. Only use active files (not in /deprecated/)
3. Follow existing patterns from active code

Let me know what you see as the current architecture.
```

### Debugging

```markdown
I'm debugging an issue with [feature].

Important context:
- This project uses Necro for deprecated file management
- Check ARCHITECTURE.md for current implementations
- Do NOT look at /deprecated/ - those are old implementations
- The issue is likely in the current active code

Where should we start investigating?
```

### Code Review

```markdown
Please review this code.

Context:
- Project uses Necro for file management
- Check ARCHITECTURE.md for current patterns
- Flag any references to /deprecated/ directory
- Suggest improvements based on current active code only

Here's the code: [paste code]
```

### Refactoring

```markdown
I want to refactor [component/feature].

Setup:
1. Review ARCHITECTURE.md for current structure
2. Identify current implementation (not deprecated versions)
3. Suggest refactoring based on current patterns
4. After refactoring, I'll deprecate old files with Necro

Let's start by understanding the current implementation.
```

---

## Handling Common Issues

### Issue 1: Claude References Deprecated File

**What happened:**
```markdown
Claude: "Looking at /deprecated/2025-01-15/old-api.js..."
```

**Your response:**
```markdown
Stop - that file is in /deprecated/ and should not be used.
Check ARCHITECTURE.md for the current API implementation.
The deprecated directory contains obsolete code only.
```

**Claude should say:**
```markdown
You're absolutely right, I apologize. Let me check ARCHITECTURE.md
for the current API implementation instead...
```

### Issue 2: Claude Suggests Deprecated Pattern

**What happened:**
```markdown
Claude: "You should use the old-style API calls like in legacy-component.js"
```

**Your response:**
```markdown
Is legacy-component.js in ARCHITECTURE.md? If not, it's likely deprecated.
Please only suggest patterns from files listed in ARCHITECTURE.md.
```

### Issue 3: Claude Can't Find Implementation

**What happened:**
```markdown
Claude: "I can't find the implementation of [feature]"
```

**Your response:**
```markdown
Check ARCHITECTURE.md for current files. If it's not listed there,
it might be deprecated. Let me run `necro arch` to update the
documentation, then we can search in the active files only.
```

---

## Best Practices for AI Sessions

### Do This

- ✅ Load ARCHITECTURE.md at session start
- ✅ Explicitly state the /deprecated/ rule upfront
- ✅ Run `necro arch` before long sessions
- ✅ Correct Claude immediately if it references deprecated files
- ✅ Ask Claude to confirm it's only using active files
- ✅ Update architecture after major changes

### Don't Do This

- ❌ Assume Claude will know to ignore /deprecated/
- ❌ Let Claude reference deprecated files without correction
- ❌ Work with stale ARCHITECTURE.md
- ❌ Mix old and new implementations
- ❌ Trust Claude's memory of previous deprecated files

---

## Example Session Transcript

Here's a model conversation:

```markdown
User: I'm working on adding a new API endpoint. This project uses Necro
      for deprecated file management. Please review ARCHITECTURE.md and
      only reference active files. The /deprecated/ directory should be
      completely ignored.

Claude: I understand. Let me review ARCHITECTURE.md first to understand
        the current project structure...

        I can see the current API implementation is in src/api/rest.js
        and follows the REST pattern. The active routes are defined in
        src/routes/api.js. I'll only reference these active files.

        For your new endpoint, I suggest...

User: Perfect! Let's proceed with that approach.

[Later in the session]

User: Great work! Now I'll deprecate the old API files:

      necro deprecate src/api/legacy.js "Replaced by REST implementation"
      necro arch

      The architecture doc is now updated with the new structure.

Claude: Excellent! The project structure is now cleaner, and future sessions
        will only see the current REST implementation in ARCHITECTURE.md.
```

---

## Advanced Integration

### Custom Necro Commands in Session

You can ask Claude to remind you:

```markdown
User: What Necro commands should I run before ending this session?

Claude: Before ending, you should:
        1. `necro deprecate` - if we replaced any files
        2. `necro arch` - update architecture documentation
        3. `git add ARCHITECTURE.md deprecated/` - stage changes
```

### Architecture-First Development

Start every major task with:

```markdown
User: Let's build [feature]. First, review ARCHITECTURE.md and tell me
      the current structure relevant to this feature.

Claude: [Reviews ARCHITECTURE.md and summarizes current state]

User: Good. Only use those files. Let's proceed.
```

### Mid-Session Refresh

If you make major changes:

```bash
necro arch
```

Then tell Claude:

```markdown
I've updated ARCHITECTURE.md with the current state. Please refresh
your understanding of the project structure.
```

---

## Integration with Project Workflow

### In RESTART.md

Add this section to your project's RESTART.md:

```markdown
## Working with Claude Code

1. Run `necro arch` to update documentation
2. Start Claude session with:
   "This project uses Necro. Only reference files in ARCHITECTURE.md.
    Completely ignore /deprecated/ directory."
3. During session, if Claude references deprecated files, correct immediately
4. After session, run `necro arch` if you made major changes
```

### In Pull Request Template

```markdown
## AI Assistant Usage Checklist

If you used AI assistance (Claude, Copilot, etc.):
- [ ] Loaded ARCHITECTURE.md before starting
- [ ] Instructed AI to ignore /deprecated/ directory
- [ ] Verified AI only referenced active files
- [ ] Ran `necro arch` after major changes
- [ ] Deprecated old files with `necro deprecate`
```

---

## Success Metrics

You'll know the integration is working when:

1. Claude consistently checks ARCHITECTURE.md first
2. Claude never references /deprecated/ files
3. Claude's suggestions use current patterns only
4. You catch and correct deprecated references immediately
5. Your sessions are more productive with less confusion

---

## Troubleshooting

### Claude Keeps Forgetting the Rules

**Solution**: Add to your first message in EVERY session:
```markdown
CRITICAL: This project uses Necro. Only use files from ARCHITECTURE.md.
Never reference /deprecated/ directory. Acknowledge these rules.
```

Wait for Claude to acknowledge before proceeding.

### ARCHITECTURE.md Is Too Large

**Solution**: Update more frequently or split into sections:
```bash
necro arch --output docs/ARCHITECTURE.md
```

Then reference specific sections with Claude.

### Claude Questions a Deprecation

**Solution**: Show Claude the deprecation log:
```bash
necro deprecate log
```

Then explain: "See? This file was deprecated on [date] because [reason]."

---

## Training Your AI Assistant

Think of each session as training:

1. **First correction**: Claude learns the rule
2. **Second correction**: Claude reinforces the rule
3. **Third+ correction**: Rule becomes habit

Be consistent, be explicit, and Claude will learn to respect your project's architecture boundaries.

---

## Template Prompts

### Session Starter Template

```markdown
Project context: [project name] uses Necro for deprecated file management.

RULES FOR THIS SESSION:
1. Read ARCHITECTURE.md first
2. Only reference files listed there
3. Completely ignore /deprecated/ directory
4. If unsure about a file, ask me

TASK: [your task description]

Please acknowledge these rules and review ARCHITECTURE.md before we proceed.
```

### Mid-Session Template

```markdown
Before continuing, let's verify:
- Are you only using files from ARCHITECTURE.md?
- Have you referenced any files in /deprecated/?
- Do you need me to run `necro arch` to update the documentation?
```

### Session End Template

```markdown
Session complete! Before I close:
1. Did we create any files that should deprecate old ones?
2. Should I run `necro arch` to update documentation?
3. Anything you noticed in deprecated/ that we should address?
```

---

**Remember**: Claude Code is a powerful tool, but it needs clear boundaries. Necro provides those boundaries, and this guide helps you enforce them. With practice, working with Claude on Necro-enabled projects becomes second nature.