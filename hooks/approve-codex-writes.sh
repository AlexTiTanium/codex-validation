#!/bin/bash
# Auto-approve tool calls that operate on the plugin's .claude/codex/ session directory.
# This prevents repeated permission prompts for every new session ID.

INPUT=$(cat) || INPUT=""
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || TOOL_NAME=""

# On parse failure, fall through to normal permissions
if [[ -z "$TOOL_NAME" ]]; then
  exit 0
fi

approve() {
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "Auto-approved: codex plugin session directory"
  }
}
EOF
  exit 0
}

# Reject commands containing shell chaining operators that could smuggle extra operations.
# Pipes are allowed since the plugin's codex commands use them (cat | codex exec | tee).
has_chaining() {
  local cmd="$1"
  # Match ;, &&, ||, $(), backticks — but not pipes
  if [[ "$cmd" == *";"* ]] || [[ "$cmd" == *"&&"* ]] || [[ "$cmd" == *"||"* ]] ||
     [[ "$cmd" == *'$('* ]] || [[ "$cmd" == *'`'* ]]; then
    return 0
  fi
  return 1
}

case "$TOOL_NAME" in
  Write|Edit)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || FILE_PATH=""
    if [[ "$FILE_PATH" == *".claude/codex/"* ]]; then
      approve
    fi
    ;;
  Bash)
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || COMMAND=""

    # Never auto-approve commands with shell chaining operators
    if has_chaining "$COMMAND"; then
      exit 0
    fi

    # Auto-approve: mkdir targeting .claude/codex/
    if [[ "$COMMAND" == "mkdir -p"*".claude/codex/"* ]]; then
      approve
    fi

    # Auto-approve: tee writing to .claude/codex/ (appears after a pipe in plugin commands)
    if [[ "$COMMAND" == *"| tee "*".claude/codex/"* ]] || [[ "$COMMAND" == "tee "*".claude/codex/"* ]]; then
      approve
    fi

    # Auto-approve: parse-jsonl.sh reading from .claude/codex/
    if [[ "$COMMAND" == *"parse-jsonl.sh "*".claude/codex/"* ]]; then
      approve
    fi

    # Auto-approve: codex exec invoked as a piped command or at command start
    if [[ "$COMMAND" == *"| codex exec "* ]] || [[ "$COMMAND" == "codex exec "* ]] ||
       [[ "$COMMAND" == "cat "*.claude/codex/*"| codex exec"* ]]; then
      approve
    fi
    ;;
esac

# Fall through — let the normal permission system handle everything else
exit 0
