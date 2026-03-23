---
name: code-review
description: Review pull requests against personalized coding standards. Use when asked to review a PR, check code changes, or /review-pr.
allowed-tools: Agent, Read, Glob, Grep, Edit, AskUserQuestion, Bash(brew:*), Bash(command:*), Bash(which:*), Bash(gh pr diff:*), Bash(gh pr view:*), Bash(gh pr checkout:*), Bash(gh pr comment:*), Bash(gh pr review:*), Bash(gh api:*), Bash(git diff:*), Bash(git log:*), Bash(git blame:*), Bash(git checkout:*), Bash(git fetch:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(gh pr list:*), Bash(gh search:*), Bash(gh auth:*), mcp__github__pull_request_read, mcp__github__pull_request_review_write, mcp__github__add_comment_to_pending_review, mcp__github__get_file_contents
---

# Personalized Code Review Skill

Review PRs and code changes against technotronic12's coding standards, extracted from real review patterns across windward-ltd repositories.

## Input Formats

Accept any of these:

1. **PR URL**: `https://github.com/windward-ltd/repo-name/pull/123`
2. **PR shorthand**: `repo-name#123` or `#123` (assumes current repo)
3. **Branch diff**: "review my changes" or "review current branch"
4. **File/folder path**: `/path/to/file.ts` or `/path/to/folder/`
5. **Re-review**: "re-review PR <url>", "review again <url>", "check if comments were fixed on <url>"

### Re-review Detection

Enter **re-review mode** when ANY of these are true:
- User explicitly says "re-review", "review again", "check if fixed", "check comments"
- PR has an existing `REQUEST_CHANGES` review by `technotronic12` (detected in Step 2)

## Workflow

### Step 0: Prerequisites Check

Run on first use to ensure the environment is ready. On subsequent runs, take the fast path — if `gh auth status` succeeds, skip directly to Step 1.

**Fast path (subsequent runs):**
1. Run `gh auth status`
2. If it succeeds → skip to Step 1
3. If it fails → run the full check below

**Full check (first run or fast path failure):**

1. **Check git:**
   - `command -v git`
   - If missing → stop with error: "git is required for code reviews"

2. **Check GitHub CLI:**
   - `command -v gh`
   - If missing → ask user for confirmation, then install: `brew install gh`
   - Verify: `gh --version`

3. **Check GitHub CLI authentication:**
   - `gh auth status`
   - If not authenticated → run `gh auth login` and guide user through the browser OAuth flow
   - Verify: `gh auth status` shows "Logged in to github.com"

4. **Check repo access:**
   - `gh api user --jq '.login'` → confirm user identity
   - `gh api orgs/windward-ltd --jq '.login'` → confirm org access

5. If all checks pass → proceed to Step 1
6. If any check fails after remediation → stop with clear error message

### Step 1: Parse Input & Fetch Changes

**For PR URL or shorthand:**
1. Extract owner, repo, and PR number
2. Fetch the diff:
   ```
   gh pr diff <number> --repo windward-ltd/<repo>
   ```
3. Get list of changed files:
   ```
   gh pr view <number> --repo windward-ltd/<repo> --json files
   ```
4. Get PR metadata (title, description, author, and branch name):
   ```
   gh pr view <number> --repo windward-ltd/<repo> --json title,body,author,headRefName
   ```
5. Get the current GitHub user:
   ```
   gh api user --jq '.login'
   ```
   Store as `currentUser`. Compare to `author.login` from step 4 — record `isOwnPR = (currentUser === author.login)`.
6. **Check for missing PR description:** If `body` is null, empty, or only whitespace, record a `MISSING_DESCRIPTION` flag. This will surface as a WARNING in the findings and in the GitHub review body (see Steps 6 and 7b).

**For "review my changes":**
1. Detect the base branch:
   ```
   git log --oneline main..HEAD
   ```
2. Get the diff:
   ```
   git diff main...HEAD
   ```
3. List changed files:
   ```
   git diff --name-only main...HEAD
   ```

**For file/folder path:**
1. Use `Read` or `Glob` to get file contents
2. Review the entire file(s)

### Step 2: Re-review Check (PR reviews only)

**Skip this step** if the input is a branch diff or file/folder path.

Determine if this is a re-review and, if so, gather previous comment data.

1. If user explicitly requested re-review (see Re-review Detection above), set `isReReview = true`
2. Otherwise, check for existing `REQUEST_CHANGES` review by `technotronic12`:
   ```
   gh api repos/windward-ltd/<repo>/pulls/<number>/reviews \
     --jq '[.[] | select(.user.login=="technotronic12" and .state=="CHANGES_REQUESTED")] | last'
   ```
3. If a `REQUEST_CHANGES` review exists, ask the user:
   > "This PR has a previous REQUEST_CHANGES review. Run a **re-review** (check if comments were fixed) or a **fresh review**?"
4. If not a re-review → **skip to Step 3**

#### Always: Check for pending (draft) review comments

Regardless of re-review mode, always check for any PENDING review by `technotronic12` — GitHub draft review comments are NOT returned by `/pulls/<number>/comments` and will be missed without this step:

```
gh api repos/windward-ltd/<repo>/pulls/<number>/reviews \
  --jq '[.[] | select(.user.login=="technotronic12" and .state=="PENDING")] | last'
```

If a PENDING review exists, fetch its comments:
```
gh api repos/windward-ltd/<repo>/pulls/<number>/reviews/<pending_review_id>/comments \
  --jq '.[] | {id, path, line, body}'
```

Include these pending comments as **already-noted findings** — do not re-post them, but factor them into your analysis to avoid redundancy and to learn what was already caught.

#### If re-review: Check Previous Comments

**Fetch the previous review and its inline comments:**
```
gh api repos/windward-ltd/<repo>/pulls/<number>/reviews/<review_id>/comments
```

Extract from each comment:
- `path` — file
- `original_line` / `line` — line number
- `body` — the comment text (parse out `[R-XX]` rule ID if present)
- `in_reply_to_id` — to detect threaded replies/resolutions

**For each previous comment, check if fixed or still open:**

1. Read the current version of the file at the commented location
2. Determine status:
   - **Fixed**: The flagged pattern is no longer present (code changed to address the comment)
   - **Still open**: The flagged pattern is still present in the current code
   - **Can't determine**: File was deleted or code moved significantly — flag for manual check

**Record results** as a list of `{ file, line, ruleId, commentBody, status: fixed | open | unknown }`.

**Narrow the diff scope** for remaining steps:
1. Get the review's `commit_id` (the commit the review was made against)
2. Fetch the diff from that commit to current HEAD:
   ```
   gh api repos/windward-ltd/<repo>/compare/<previous_commit>...<head_commit> --jq '.files[] | {filename, patch}'
   ```
   This ensures Steps 3-6 only analyze code changed since the last review, avoiding re-flagging issues from the previous review.

**MANDATORY:** Then continue to Steps 3–6 with the narrowed diff. Do NOT skip this — even if the narrowed diff looks small or mechanical, run the full rules analysis against every changed line. Visually skimming is not sufficient.

---

### Step 3: Detect Domain & Load Rules

**Always load first:**
- `./REVIEW-RULES-COMMON.md` — applies to all code

Then classify each changed file and load the domain-specific file(s):

```
BACKEND files (load REVIEW-RULES-BACKEND.md):
  - *.ts files (not *.tsx)
  - Paths containing: /services/, /dal/, /model/, /routes/, /schema/,
    /utils/, /helpers/, /validations/, /common/
  - Test files for the above: /tests/*.test.ts

FRONTEND files (load REVIEW-RULES-FRONTEND.md):
  - *.tsx files
  - Paths containing: /components/, /stores/, /hooks/
  - Test files for the above: /tests/*.test.tsx, *.test.tsx

BOTH: If PR has files from both domains, load both domain-specific files.

NEITHER: Config files (*.json, *.yaml, *.yml, *.md, Dockerfile, etc.)
  - Apply REVIEW-RULES-COMMON.md only; no domain-specific rules file needed
```

Read the appropriate rules file(s) from the skill directory:
- `./REVIEW-RULES-COMMON.md` ← always
- `./REVIEW-RULES-BACKEND.md` ← if backend files present
- `./REVIEW-RULES-FRONTEND.md` ← if frontend files present

### Step 3.5: Prefetch Shared Data

Prefetch all data that agents will need so they receive it inline — zero tool calls from subagents.

**a) Full source file contents:**
For each changed file, read the full file contents and store as `fileContents[file]`.

**b) Git history per file:**
For each changed file (skip new files):
```
git log --oneline -20 -- <file>
```
Store as `gitHistory[file]`.

**c) Git blame on modified ranges:**
For each changed file (skip new files):
1. Parse diff hunk headers to extract modified line ranges (`@@ -old,count +new,count @@`)
2. For each modified range:
   ```
   git blame -L <start>,<end> <file>
   ```
Store as `gitBlame[file]`.

**d) Recent merged PRs and their comments:**
For each changed **production** file (skip test/mock files, `__mocks__/`, `*.test.*`, `*.mock.*`):
```
gh pr list --repo windward-ltd/{repo} --state merged --search "<filename>" --limit 3 --json number,title
```
For each found PR:
```
gh api repos/windward-ltd/{repo}/pulls/<number>/comments --jq '.[] | {path, line, body, user: .user.login}'
```
Store as `prComments[file]`.

**e) CLAUDE.md files:**
Find and read CLAUDE.md in:
- Repository root
- Directories of changed files (e.g. if `src/services/user.service.ts` changed, check `src/services/CLAUDE.md` and `src/CLAUDE.md`)
Store as `claudeMdFiles[]`.

**f) Rules files (already loaded in Step 3):**
Store the contents read in Step 3 as `rulesCommon`, `rulesBackend` (if applicable), `rulesFrontend` (if applicable).

**Parallelization:** Steps (a) through (e) are independent — run as many in parallel as possible. Specifically:
- File reads (a) can all be parallel
- Git history (b) and git blame (c) can run in parallel per file
- PR comment fetches (d) can run in parallel per file
- CLAUDE.md discovery (e) can run alongside everything else

### Step 4: Launch Parallel Analysis Agents

Launch **2 agents in parallel** using the `Agent` tool. Both agents receive all prefetched data inline — zero tool calls needed from subagents. All agents return findings inside a fenced ` ```json-findings ` code block for deterministic parsing.

**Important:** Both Agent calls MUST be made in a single message to ensure they run concurrently.

**Data passed to both agents** (from Steps 1, 3, and 3.5):
- Diff + changed files list
- Full file contents (`fileContents[file]`)
- Git history per file (`gitHistory[file]`)
- Git blame per file (`gitBlame[file]`)
- Previous PR comments per file (`prComments[file]`)
- CLAUDE.md files (`claudeMdFiles[]`)

#### Agent 1: Windward Rules Analysis (model: sonnet)

**Additionally receives:** Rules text (`rulesCommon` + `rulesBackend`/`rulesFrontend`)

**Prompt template** — substitute variables from Steps 1-3.5:

```
You are a code review agent. Analyze the following PR diff against coding rules. All data is provided inline — do NOT use any tools.

## Input
- Repo: windward-ltd/{repo}
- PR: #{number}
- Domain: {backend|frontend|full-stack}
- Changed files: {files list}
- Diff:
{full diff}

## Full File Contents
{for each file: "### <filepath>\n<fileContents[file]>"}

## Git History
{for each file: "### <filepath>\n<gitHistory[file]>"}

## Git Blame (modified ranges)
{for each file: "### <filepath>\n<gitBlame[file]>"}

## Previous PR Comments
{for each file: "### <filepath>\n<prComments[file]>" or "No previous PR comments found."}

## Rules
{rulesCommon text}
{rulesBackend text if applicable}
{rulesFrontend text if applicable}

## Analysis — Two-Pass

### Pass 1: Structure & Architecture
For each file in the diff:
1. Use the full file contents provided above (not just the diff) to understand context
2. Focus on changed lines — only flag issues on lines added or modified in the PR
3. Check architecture rules (R-01 through R-10, C-04 through C-08, C-13, C-14): structure, decomposition, layer separation, file placement, error handling
4. New file placement check: For every new file in the PR, ask: "does this file belong in this directory?" Apply R-09.

### Pass 2: Naming & Conventions (line-by-line on declarations)
For each file, scan every `const`, `let`, `function`, `interface`, `type`, and `class` declaration on changed lines:
5. Check naming rules (C-01, C-03, C-10, C-11, C-16, C-17, R-11, R-12, R-13, R-22): no abbreviations, descriptive names, correct casing, proper types, file suffixes, schema naming
6. For test files specifically: audit each `const` declaration for mock prefix, descriptive name, type match. Also check C-15 (it.each limits).
7. Record findings with: rule ID, severity, file path, line number, issue description, code snippet, suggested fix

### Constraints
- Do NOT use any tools — all data is provided above
- Do NOT flag issues on unchanged code
- Do NOT flag the same issue multiple times on adjacent lines — consolidate
- Do NOT flag issues that are clearly intentional patterns in the codebase
- Cross-file consistency: When you find a pattern violation in one file, scan ALL other changed files for the same pattern
- Reuse existing mocks: If a test imports from a shared mock provider, flag any file that redefines the same mock locally

### Enrichment from Git History & PR Comments
Use the provided git history, blame, and previous PR comments to enrich your findings:
- **High churn**: If a file/function appears >3 times in git history within recent commits, bump severity of findings in that area
- **Recurring feedback**: If previous PR comments flagged the same pattern you're flagging, mention it in the finding description (e.g. "This was also flagged in PR #XX by <reviewer>")
- **Regressions**: If git history shows a pattern was previously fixed but is now reintroduced, flag as CRITICAL

### Missing negative test detection
When the diff adds or modifies a test file, for each new test case:
1. Check if the test name contains a conditional signal: "when X provided", "should X when Y", "with X", "if X exists"
2. If yes, scan the surrounding describe block for a counterpart test covering the opposite case
3. If no counterpart exists, flag as WARNING

### Missing test file for changed production code
For each changed production file (.ts or .tsx):
- Derive expected test file path using windward conventions
- If no matching test file in the diff, flag as WARNING
- Skip: types.ts, constants.ts, config.ts, *.model.ts, index.ts, *.mock.ts, __mocks__/, src/tests/, *.queries.ts

## Output
Return findings as a fenced json-findings block:
\`\`\`json-findings
[
  {
    "source": "rules",
    "ruleId": "R-XX or C-XX",
    "severity": "CRITICAL|WARNING|INFO",
    "file": "path/to/file.ts",
    "line": 42,
    "description": "issue description",
    "snippet": "code snippet",
    "fix": "suggested fix or null",
    "autoFixable": true|false
  }
]
\`\`\`
```

#### Agent 2: Anthropic-style Analysis (model: sonnet)

Adapted from Anthropic's official code-review plugin approach — CLAUDE.md compliance, bug scanning, confidence scoring. Returns findings instead of posting.

**Prompt template** — substitute variables from Steps 1-3.5:

```
You are a code review analysis agent. Perform deep analysis of the PR for bugs, CLAUDE.md compliance, and contextual issues. All data is provided inline — do NOT use any tools.

## Input
- Repo: windward-ltd/{repo}
- PR: #{number}
- Changed files: {files list}
- Diff:
{full diff}

## Full File Contents
{for each file: "### <filepath>\n<fileContents[file]>"}

## CLAUDE.md Files
{for each claudeMdFile: "### <filepath>\n<content>"}

## Git History
{for each file: "### <filepath>\n<gitHistory[file]>"}

## Git Blame (modified ranges)
{for each file: "### <filepath>\n<gitBlame[file]>"}

## Previous PR Comments
{for each file: "### <filepath>\n<prComments[file]>" or "No previous PR comments found."}
{if re-review: "\n## Previous comment locations to skip:\n{list of file:line already tracked}"}

## Analysis — Five Passes

Perform these 5 analysis passes. For each finding, self-score confidence 0-100.

### Pass 1: CLAUDE.md Compliance Audit
Check if the changes comply with all CLAUDE.md guidance provided above:
- Coding standards violations
- Workflow violations
- Naming convention violations
- Architecture pattern violations
Flag only issues that are clearly in scope for the changed lines.

### Pass 2: Bug Scanning
Shallow scan for obvious bugs in changed lines only. Focus on large, impactful bugs:
- Null/undefined dereferences
- Off-by-one errors
- Race conditions
- Missing error handling that could crash
- Incorrect logic (wrong operator, missing condition)
- Security issues (injection, auth bypass)
Avoid nitpicks. Ignore likely false positives.

### Pass 3: History-Context Bugs
Use the provided git blame and history to identify bugs in light of historical context:
- Code that was previously fixed but is now reintroduced (regression)
- Changes to high-churn areas that may introduce instability
- Patterns that match previously reverted commits

### Pass 4: Previous PR Comment Compliance
Check if feedback from previous PRs (provided above) applies to current changes:
- Same reviewer flagged the same pattern before
- Feedback was given on a similar function/file
- A recurring issue that hasn't been addressed

### Pass 5: Code Comment Compliance
Check if changes comply with inline TODO/FIXME/NOTE/HACK/@deprecated guidance:
- Changes near a TODO/FIXME that don't address it
- Code that violates a NOTE or documented constraint
- Usage of @deprecated APIs

## Confidence Scoring
For each finding, self-score confidence 0-100:
- 0: False positive
- 25: Might be real, might not
- 50: Real but minor/nitpicky
- 75: Very likely real, important, directly impacts functionality
- 100: Definitely real, confirmed with evidence

**Self-filter: Only include findings with confidence >= 80.**

## False Positive Exclusions
Do NOT flag:
- Pre-existing issues not introduced in this PR
- Issues that linters or type-checkers would catch (CI handles these)
- Pedantic nitpicks not covered by CLAUDE.md
- Issues on lines with lint-ignore comments
- General code quality issues unless they violate CLAUDE.md
- Clearly intentional changes
- Issues on unmodified lines

## Constraints
- Do NOT use any tools — all data is provided above
- Only flag issues on changed lines in the diff
- Be precise: include exact file path, line number, and code snippet
- For each finding, include the evidence that supports it

## Output
Return findings as a fenced json-findings block:
\`\`\`json-findings
[
  {
    "source": "analysis",
    "category": "claude-md|bug|history|prev-pr|code-comment",
    "severity": "CRITICAL|WARNING|INFO",
    "file": "path/to/file.ts",
    "line": 42,
    "description": "issue description",
    "snippet": "code snippet",
    "evidence": "what supports this finding",
    "confidence": 85,
    "fix": "suggested fix or null"
  }
]
\`\`\`
```

### Step 5: Consolidate & Filter

After both agents return, consolidate their findings:

1. **Parse** JSON findings from both agents (extract from ` ```json-findings ` blocks)
2. **Deduplicate** by (file, line ±1):
   - If both agents flag the same location → keep Agent 1's finding (has rule ID), append Agent 2's insight to the description
   - Agent 2-only findings → include as-is (no rule ID, just severity + description)
3. **Sort**: CRITICAL → WARNING → INFO
4. **Group** by file, count totals per severity and per source (Rules vs Analysis)

### Step 6: Present CLI Summary

Output in this format. **Always start with encouragement and a positive highlight from the PR**, then summarize what the PR does, then list findings.

**If re-review:** Use the heading `## Re-review: <PR title> (#<number>)` and prepend the Previous Comments Status section before the findings (see re-review format below).

```markdown
## Code Review: <PR title> (#<number>)

### Nice work
<Keep this short — 1 sentence max. Use technotronic12's tone: "nice!", "Wow what a change to the file :)", or similar.
Only include a specific code or feature example if something is genuinely smart or outstanding (e.g. a clever abstraction, great test coverage, a tricky problem solved cleanly). Otherwise, keep it general and brief.>

### What this PR does
<1-2 sentences max. Be concise and clear — summarize the purpose and scope in plain language. No fluff.>

**Domain:** Backend | Frontend | Full-stack
**Rules loaded:** REVIEW-RULES-COMMON.md + REVIEW-RULES-BACKEND.md | REVIEW-RULES-FRONTEND.md | Both
**Sources:** Rules (N) | Analysis (N)

### Findings
- X critical | Y warning | Z info

> **⚠️ No PR description** — Please add a PR description — it helps reviewers and future us to understand the intent and scope of the change.
> *(omit this block if `body` is present)*

---

### path/to/file.ts

**CRITICAL** [C-05] Line 42: Magic string in error throw
> `throw new Error('User not found');`
> Fix: Extract to constant

**WARNING** [R-20] Line 189: 3 positional parameters
> Fix: Extract to IncrementTypesUsageParams interface
> Note: This function was flagged in PR #14 review (adijesori) — still unaddressed

**WARNING** Line 42: Potential null dereference — `parsedInfo` may be undefined when `fieldsByTypeName` is empty
> Confidence: 85 | Source: Bug scan
> Fix: Add null check before accessing `parsedInfo.fieldsByTypeName`

**INFO** [R-XX] Line NN: <issue description>
> `<code snippet>`

---

### path/to/other-file.tsx

**WARNING** [R-XX] Line NN: <issue description>
> `<code snippet>`
> Fix: `<suggested replacement>`

---

### Clean files (no issues)
- path/to/clean-file.ts
- path/to/another-clean.ts
```

**Finding format notes:**
- **Agent 1 findings (rules)**: Tagged with `[R-XX]` or `[C-XX]` rule IDs. When Agent 2 found something on the same line, its insight is woven into the description as a `> Note:` line.
- **Agent 2-only findings (analysis)**: No rule ID tag — just severity + description. Include confidence score and source category (Bug scan, CLAUDE.md, History, etc.). Include fix suggestion if available.
- **Enriched findings**: When Agent 1 flags a rule violation and Agent 2 provides additional context (e.g. "this was flagged in PR #XX"), the context appears as a `> Note:` line on the Agent 1 finding.
- **Sources line**: Shows count of findings per source after deduplication — `Rules (N)` for Agent 1, `Analysis (N)` for Agent 2-only findings.

#### Re-review Output Format

When in re-review mode, use this format instead:

```markdown
## Re-review: <PR title> (#<number>)

### Previous Comments Status
- X/Y fixed | Z still open

| Status | File | Comment |
|--------|------|---------|
| Fixed | path/to/file.ts:42 | [R-12] Missing return type |
| Open | path/to/other.ts:15 | [R-07] Direct model access |
| Open | path/to/test.js:1 | [R-18] New .js file |

### Nice work
<same encouragement section as regular review>

### What this PR does
<same summary section as regular review>

**Domain:** Backend | Frontend | Full-stack
**Rules loaded:** REVIEW-RULES-COMMON.md + REVIEW-RULES-BACKEND.md | REVIEW-RULES-FRONTEND.md | Both
**Sources:** Rules (N) | Analysis (N)

### New Issues (since last review)
- X critical | Y warning | Z info

<same per-file findings format as regular review>

---

### Verdict
- All previous comments fixed + no new critical/warning → "All comments addressed! Approve PR?"
- Some comments still open → "X comments still open. Post update to GitHub?"
- New issues found → "Found N new issues. Post update to GitHub?"
```

### Step 7: Offer Next Actions (PR reviews only)

After presenting findings, use the `AskUserQuestion` tool to present a selection prompt. Configure it based on severity:

Before building the prompt, determine the "Apply fixes locally" description based on `isOwnPR`:
- **`isOwnPR = true`**: `"Edit files on your current branch — no checkout needed"`
- **`isOwnPR = false`**: `"Will checkout branch '<headRefName>', apply edits, then commit & push"`

- **Has CRITICAL or WARNING findings** — use this question config:
  ```
  question: "What would you like to do with this review?"
  header: "Next action"
  options:
    - label: "Post to GitHub"
      description: "Submit findings as a REQUEST_CHANGES review with inline comments"
    - label: "Apply fixes locally"
      description: <dynamic — see above>
    - label: "Nothing"
      description: "Dismiss — no action taken"
  ```

- **Only INFO findings or no findings** — use this question config:
  ```
  question: "What would you like to do with this review?"
  header: "Next action"
  options:
    - label: "Approve on GitHub"
      description: "Submit an APPROVE review to the PR"
    - label: "Apply fixes locally"
      description: <dynamic — see above>
    - label: "Nothing"
      description: "Dismiss — no action taken"
  ```

- **"Apply fixes locally" selected:** Enter the **Local Fix Mode** workflow (see `## Local Fix Mode` section below).
- **"Nothing" selected:** Do nothing. Stop here.
- **"Post to GitHub" / "Approve on GitHub" selected:** Proceed with GitHub posting as below.

**If posting to GitHub:**

Post **CRITICAL and WARNING** findings as **inline review comments** on the relevant lines. Post **INFO** findings in the review body under a `### Notes` section — they provide valuable context but are not actionable on specific lines.

#### Step 7a: Resolve exact line numbers from the diff (REQUIRED)

**Never estimate or guess line numbers.** Before building the JSON payload, resolve the exact new-file line number for each finding by parsing the diff:

```
For each diff hunk header: @@ -old_start,old_count +new_start,new_count @@
  new_line = new_start
  for each line in hunk body:
    if line starts with '-': skip (deleted, not in new file)
    if line starts with '+' or ' ' (context):
      if this is the line of interest → its new-file line number is new_line
      new_line++
```

Concretely: scan the saved diff output for the file, find the hunk containing the flagged code snippet, then count `+` and context lines from `new_start` until you reach the flagged line.

**If the flagged line cannot be found in the diff** (e.g. it falls in an unchanged region), do not include it as an inline comment — add it to the review body text instead.

#### Step 7b: Build and post the review

1. Write a JSON file with the review payload:
   ```json
   {
     "event": "<APPROVE, COMMENT, or REQUEST_CHANGES — see below>",
     "body": "> 🤖  This review was generated using an automated code review skill and manually reviewed by me before posting.\n\n## Code Review\n\n<if MISSING_DESCRIPTION flag is set, prepend: '⚠️ **No PR description** — Please add a PR description — it helps reviewers and future us to understand the intent and scope of the change.\n\n'><positive highlight from the PR — 1-2 sentences>\n\n**Summary:** <what this PR does — 2-3 sentences>\n\nX critical | Y warning | Z info — see inline comments.<if there are INFO findings, append: '\n\n---\n\n### Notes\n\n' followed by each INFO finding as a bullet point: '- **[R-XX]** <description>' (or without rule ID for analysis-only findings). INFO findings are valuable context but not actionable on specific lines, so they belong in the review body rather than as inline comments.>",
     "comments": [
       {
         "path": "path/to/file.ts",
         "line": <exact_new_file_line_number_from_step_7a>,
         "side": "RIGHT",
         "body": "**[R-XX]** <issue description>\n\n<code suggestion if applicable>"
       }
     ]
   }
   ```
2. Post using: `gh api repos/windward-ltd/<repo>/pulls/<number>/reviews --method POST --input <json_file>`
3. Set review event based on findings:
   - **Has CRITICAL or WARNING findings:** `REQUEST_CHANGES`
   - **Only INFO findings or no findings:** `APPROVE`
4. When multiple findings are on adjacent lines in the same file, consolidate into a single comment on the first line
5. **Do NOT include INFO findings as inline comments** — they go in the review body `### Notes` section only

**Comment format (CRITICAL and WARNING only):**
```
**[R-XX]** <issue description>

<code suggestion if applicable>
```

#### Re-review GitHub Posting

When in re-review mode, the review event and body adapt based on the verdict:

- **All previous comments fixed + no new critical/warning findings:**
  - Ask "All comments addressed! Approve PR?"
  - If yes → submit `APPROVE` review with body summarizing what was fixed and fixed/open counts
- **Some comments still open OR new critical/warning findings:**
  - Submit `REQUEST_CHANGES` with:
    - Review body: previous comments status (fixed/open counts) + new findings summary
    - Inline comments only for **new** findings (don't re-post old ones)
- **Only new INFO findings, all previous fixed:**
  - Submit `COMMENT` (not REQUEST_CHANGES) since INFO findings don't block

## Local Fix Mode

This mode is entered when the user selects "Apply fixes locally" in Step 7, or explicitly asks to "fix my changes" / "fix pr <number> locally". It applies the same rules analysis as the regular review but generates concrete corrected code for each finding and lets the user choose which fixes to apply directly to their files.

### Step L1: Parse Input & Fetch Changes

**Entered from Step 7 (after a review):** Diff and changed files are already in memory — reuse them. Branch based on `isOwnPR`:

- **`isOwnPR = true`** (reviewing your own PR or a branch diff):
  - Files are already checked out locally — proceed directly to L3.

- **`isOwnPR = false`** (reviewing someone else's PR):
  - Check out the PR branch using:
    ```
    gh pr checkout <number> --repo windward-ltd/<repo>
    ```
  - This fetches and checks out `headRefName` in one step.
  - After applying fixes in L5, commit and push:
    ```
    git add <edited files>
    git commit -m "<summary of fixes applied>"
    git push
    ```
  - Warn the user before committing: "About to commit and push fixes to `<headRefName>` — confirm?"
    Use `AskUserQuestion` with yes/no options before proceeding.

**Standalone trigger "fix my changes"** (branch diff):
```
git diff main...HEAD
git diff --name-only main...HEAD
```
Files are already checked out — proceed directly to L3.

**Standalone trigger "fix pr <number> locally"** (not from Step 7):
```
gh pr view <number> --repo windward-ltd/<repo> --json headRefName,author
gh api user --jq '.login'
```
Determine `isOwnPR` from the above, then follow the same branch logic as "Entered from Step 7" above.

### Step L2: Detect Domain & Load Rules

Same detection logic as Step 3 — always load `REVIEW-RULES-COMMON.md`, then domain-specific files based on changed file paths. If rules were already loaded (entered from Step 7), reuse them.

### Step L3: Analyze & Generate Fixes

Same analysis as Step 4, **plus**: for each finding, generate a concrete corrected code snippet.

Classify each finding as:

- **Auto-fixable**: Claude produces the exact replacement code
- **Manual**: Too architectural or contextual to safely auto-apply — describe what to change instead

**Fixability by rule:**

| Rules | Fixable? | Notes |
|-------|----------|-------|
| C-05 (magic strings), C-06 (no .js), C-04 (comments) | ✅ Auto | Direct text replacements |
| C-01, C-02, C-03, C-11 (naming/types) | ✅ Auto | Rename/extract with clear scope |
| R-11/R-07 (inline type → interface) | ✅ Auto | Add interface above function + update signature |
| R-12/R-06 (add return types) | ✅ Auto | Append return type to function signature |
| C-09 (extract to beforeEach), C-10 (mock prefix) | ✅ Auto | Test restructuring with clear pattern |
| R-01 (each step a function), R-02 (split functions) | ⚠️ Manual | Requires judgment on decomposition |
| R-06/R-07 (service layer, DAL) | ⚠️ Manual | Architectural — describe the change |
| R-15 (mock abstraction level) | ⚠️ Manual | Context-dependent |
| Agent 2 findings with clear fix suggestion | ✅ Auto | Apply the suggested fix |
| Agent 2 findings without fix (contextual) | ⚠️ Manual | Describe what to change |

If entered from Step 7, findings are already computed — skip re-analysis and go directly to generating fix snippets for each finding.

### Step L4: Present All Findings in Batch

Show each finding with a unified diff block. Use ` ```diff ` syntax so the terminal renders it with colour. For multi-line replacements, include enough context lines (unchanged lines prefixed with a space) to make the location unambiguous.

Output format:

````
## Local Fix Mode — <N> findings: X critical | Y warning | Z info

━━━ src/services/user.service.ts ━━━━━━━━━━━━━━━━━━━━━━━━━

#1  [CRITICAL] C-05 — Magic string, line 42

```diff
-throw new Error('User not found');
+export const USER_NOT_FOUND = 'User not found';
+throw new Error(USER_NOT_FOUND);
```

#2  [WARNING] R-12 — Missing return type, line 15

```diff
-async function getUser(id: string) {
+async function getUser(id: string): Promise<User | null> {
```

━━━ src/tests/user.service.test.ts ━━━━━━━━━━━━━━━━━━━━━━━━

#3  [CRITICAL] C-09 — Shared mock setup not in beforeEach, line 10

```diff
-it('test one', () => {
-  jest.spyOn(Service, 'get').mockResolvedValue(mockData);
-  ...
-});
-it('test two', () => {
-  jest.spyOn(Service, 'get').mockResolvedValue(mockData);
-  ...
-});
+beforeEach(() => {
+  jest.spyOn(Service, 'get').mockResolvedValue(mockData);
+});
+it('test one', () => { ... });
+it('test two', () => { ... });
```

#4  [WARNING] R-06 — Service layer coupling (manual fix needed)
    frontegg.service.ts imports BackofficeConfig from /routes/backoffice/types
    → move this import to the controller layer
    No auto-fix available for architectural changes.

#5  [WARNING] Potential null dereference, line 42 (confidence: 85)

```diff
-const fields = parsedInfo.fieldsByTypeName;
+const fields = parsedInfo?.fieldsByTypeName ?? {};
```

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
````

**Rules:**
- Only show findings that apply to the current diff (same filter as Step 5)
- Manual-only findings are shown with a plain text description — no diff block
- Number findings sequentially across all files (not per-file)
- Always include enough context lines in the diff to locate the change unambiguously
- Agent 2 findings with a clear fix suggestion → auto-fixable, shown with diff block
- Agent 2 findings without a fix (contextual observations) → manual, shown with plain text description

After presenting all findings, use `AskUserQuestion` to ask which to apply. **Build the options dynamically** based on the number of auto-fixable findings (N = count of auto-fixable):

- **N ≤ 3**: use `multiSelect: true` with one option per auto-fixable finding + "None":
  ```
  question: "Which fixes would you like to apply?"
  header: "Apply fixes"
  multiSelect: true
  options:
    - label: "#1 — <rule> <short description>"
      description: "<file>:<line>"
    - label: "#2 — <rule> <short description>"
      description: "<file>:<line>"
    - label: "#3 — <rule> <short description>"   ← only if N=3
      description: "<file>:<line>"
    - label: "None"
      description: "Skip all fixes"
  ```

- **N ≥ 4**: use single-select with broader choices:
  ```
  question: "Which fixes would you like to apply?"
  header: "Apply fixes"
  multiSelect: false
  options:
    - label: "All auto-fixable"
      description: "Apply all <N> auto-fixable findings"
    - label: "Select specific"
      description: "I'll type the numbers (e.g. 1,3)"
    - label: "None"
      description: "Skip all fixes"
  ```
  If "Select specific" is chosen, prompt: "Enter fix numbers (e.g. `1,3`):" and wait for text input.

Manual-only findings are never listed as selectable options — they are noted in the summary (L6) with instructions.

### Step L5: Apply Selected Fixes

From the user's selection:

1. **"None" / empty selection** → output "No fixes applied." and stop.
2. **"All auto-fixable"** → apply all auto-fixable findings (skip any manual ones).
3. **Specific numbers or multi-select choices** → apply only the selected finding numbers.

For each finding to apply:
- Read the full file to confirm the exact string from the diff is present
- Apply using the `Edit` tool (the `-` lines are `old_string`, the `+` lines are `new_string`)
- On success: output `✓ Applied fix #N to path/to/file.ts`
- On failure (string not found exactly): output `✗ #N — could not apply automatically, please edit manually`

Manual-only findings are always skipped with: `✗ #N — <rule> — manual fix required`

### Step L6: Summary

```
## Applied <applied> of <selected> fixes

✓ #1 — C-05 magic string extracted → src/services/user.service.ts
✓ #2 — R-12 return type added → src/services/user.service.ts
✓ #3 — C-09 mocks moved to beforeEach → src/tests/user.service.test.ts
✗ #4 — R-06 architectural fix — manual change required

Run your tests to verify: npm test -- src/tests/user.service.test.ts
```

Show the test command only for files that were actually edited, using windward test conventions (`npm test -- <path>`).

---

## Review Tone

Match technotronic12's review style:
- **Direct and concise** — short comments, no fluff
- **Question-based** — "why do you need this?" not "consider removing this"
- **Constructive** — always suggest a fix or alternative
- **Pragmatic** — flag important issues, skip trivial nitpicks
- **Encouraging when deserved** — "nice!" for good changes

Examples from real reviews:
| Situation | Style |
|-----------|-------|
| Unused code | "can we remove this?" |
| Missing types | "extract to an interface" |
| Long function | "seems that this function can be broken into smaller functions?" |
| Unclear code | "very unclear block of code" |
| Good change | "nice!" / "Wow what a change to the file :)" |
| Architecture concern | "I don't think X should be familiar with Y, this creates un-needed coupling" |
| Redundant test | "this test is redundant, you are testing the actual implementation which we didn't implement" |

## Edge Cases

- **Empty diff:** "No changes found to review."
- **Only config/docs files:** Review for formatting and consistency, note that no code rules apply.
- **Very large PR (>50 files):** Warn that the PR might be too large, then review anyway focusing on CRITICAL rules only.
- **Files outside windward patterns:** Apply general TypeScript/React best practices.

## Limitations

- Rules are based on windward-ltd patterns and may not apply to external/open-source code
- Architecture rules (service layer, DAL) are specific to the windward GraphQL service pattern
- React rules assume Material-UI 4.x and MobX (not Redux/Hooks-only patterns)
