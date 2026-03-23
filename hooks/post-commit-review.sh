#!/bin/bash
# Post-commit hook: detects git commit and injects review instruction as context

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RULES_DIR="$SCRIPT_DIR/../skills/code-reviewer"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if echo "$COMMAND" | grep -qE 'git commit '; then
  read -r -d '' CONTEXT <<ENDCONTEXT
POST-COMMIT REVIEW REQUIRED: A commit was just made. You MUST spawn a BACKGROUND subagent (using the Agent tool with run_in_background: true and subagent_type: "general-purpose") to review the last commit. The subagent should: 1) Run git diff HEAD~1 to get the changes, 2) Read ${RULES_DIR}/REVIEW-RULES-COMMON.md and the appropriate backend/frontend rules from ${RULES_DIR}/, 3) Apply those rules to the changed files, 4) Return a summary of findings. After spawning the background agent, continue with the users work without waiting. When the agent completes, present the findings to the user.
ENDCONTEXT
  jq -n --arg ctx "$CONTEXT" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
  exit 0
fi

exit 0
