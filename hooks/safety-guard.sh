#!/bin/bash
# PreToolUse safety hook: blocks destructive commands, protects secrets, confirms risky git ops

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')

# --- Bash command guards ---
if [ "$TOOL_NAME" = "Bash" ]; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

  # DENY: destructive rm commands
  if echo "$COMMAND" | grep -qE '^rm\s+-rf\s+(/|~|\.)'; then
    jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: "Blocked: destructive rm -rf on root, home, or current directory"}}'
    exit 0
  fi

  # DENY: sudo
  if echo "$COMMAND" | grep -qE '(^|\s)sudo\s'; then
    jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: "Blocked: sudo commands are not allowed"}}'
    exit 0
  fi

  # ASK: git push (any variant)
  if echo "$COMMAND" | grep -qE '(^|\s)git\s+push'; then
    jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: "This will push to a remote repository — please confirm"}}'
    exit 0
  fi

  # ASK: git reset --hard
  if echo "$COMMAND" | grep -qE 'git\s+reset\s+--hard'; then
    jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: "git reset --hard will discard uncommitted changes — please confirm"}}'
    exit 0
  fi

  # ASK: git force push
  if echo "$COMMAND" | grep -qE 'git\s+push\s+.*--force'; then
    jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: "Blocked: force push is not allowed. Use --force-with-lease if absolutely necessary."}}'
    exit 0
  fi

  exit 0
fi

# --- File access guards (.env / secrets) ---
if [ "$TOOL_NAME" = "Read" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

  # DENY: .env files
  if echo "$FILE_PATH" | grep -qE '(^|/)\.env($|\.)'; then
    jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: "Blocked: .env files may contain secrets and should not be read or modified"}}'
    exit 0
  fi

  # DENY: secrets directories
  if echo "$FILE_PATH" | grep -qE '(^|/)secrets/'; then
    jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: "Blocked: secrets directory access is not allowed"}}'
    exit 0
  fi

  exit 0
fi

# All other tools: allow
exit 0
