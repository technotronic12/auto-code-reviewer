# Auto Code Reviewer

A Claude Code plugin that automatically reviews your commits against 57 coding standards. Includes a post-commit hook that triggers a background review after every `git commit`.

## What's Included

- **Code Review Skill** — review PRs, branches, or files on demand (`/auto-code-reviewer:code-reviewer`)
- **Post-Commit Hook** — automatically spawns a background review agent after every commit
- **57 Rules** across 3 rule sets:
  - **Common** (C-01 to C-17): Types, naming, code cleanup, error handling, testing
  - **Backend** (R-01 to R-22): Node.js/TypeScript services, architecture, DAL patterns
  - **Frontend** (R-01 to R-18): React components, MobX stores, Material-UI patterns

## Install

### From the `technotronic-tools` marketplace

1. Add the marketplace in Claude Code:
   ```
   /plugin
   ```
   → Add marketplace → `technotronic12/auto-code-reviewer`

2. Install the plugin:
   ```
   /plugin install auto-code-reviewer@technotronic-tools
   ```

### From the `windward-tools` marketplace (Windward team)

```
/plugin install auto-code-reviewer@windward-tools
```

## Usage

### Automatic (post-commit hook)

Just commit as usual. The plugin detects `git commit` and spawns a background review agent that:
1. Runs `git diff HEAD~1` to get the changes
2. Loads the appropriate rules (common + backend/frontend)
3. Applies rules to changed files
4. Returns a summary of findings

### Manual review

```
review PR https://github.com/org/repo/pull/123
review PR repo-name#123
review my changes
review this file
```

### Re-review (check if comments were fixed)

```
re-review PR https://github.com/org/repo/pull/123
check if comments were fixed on #123
```

## How It Works

The skill uses **2 parallel analysis agents**:

1. **Rules Agent** — two-pass analysis (structure/architecture, then naming/conventions) against all loaded rules
2. **Analysis Agent** — Anthropic-style deep analysis: CLAUDE.md compliance, bug scanning, git history context, previous PR comment compliance

Both agents receive prefetched data (full file contents, git history, git blame, previous PR comments) so they need zero tool calls — everything is provided inline.

Findings are deduplicated, merged, and presented grouped by file and sorted by severity.

## Updating Rules

Edit the rule files in `skills/code-reviewer/`:
- `REVIEW-RULES-COMMON.md` — rules for all code
- `REVIEW-RULES-BACKEND.md` — backend-specific rules
- `REVIEW-RULES-FRONTEND.md` — frontend-specific rules

Bump the version in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, then push.

Users get updates via `/plugin update`.

## File Structure

```
auto-code-reviewer/
├── .claude-plugin/
│   ├── plugin.json              # Plugin manifest
│   └── marketplace.json         # Marketplace registry
├── skills/
│   └── code-reviewer/
│       ├── SKILL.md             # Complete review workflow
│       ├── REVIEW-RULES.md      # Rules index
│       ├── REVIEW-RULES-COMMON.md
│       ├── REVIEW-RULES-BACKEND.md
│       └── REVIEW-RULES-FRONTEND.md
├── hooks/
│   ├── hooks.json               # PostToolUse hook definition
│   └── post-commit-review.sh    # Hook script
└── README.md
```

## License

MIT

