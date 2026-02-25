#!/usr/bin/env bash
# parse-jsonl.sh - Parse Codex JSONL event stream
#
# Usage:
#   parse-jsonl.sh <events.jsonl> --output    Extract final structured output
#   parse-jsonl.sh <events.jsonl> --progress  Summarize execution progress
#   parse-jsonl.sh <events.jsonl> --errors    Extract error events
#
# Requires: jq

set -euo pipefail

EVENTS_FILE="${1:?Usage: parse-jsonl.sh <events.jsonl> [--output|--progress|--errors]}"
MODE="${2:---output}"

if [[ ! -f "$EVENTS_FILE" ]]; then
    echo "ERROR: Events file not found: $EVENTS_FILE" >&2
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not found. Install via: brew install jq" >&2
    exit 127
fi

case "$MODE" in
    --output)
        # Extract the final agent_message from the last item.completed event
        # When --output-schema was used, the content is valid JSON
        # Otherwise, it's plain text
        CONTENT=$(jq -r '
            select(.type == "item.completed")
            | select(.item.type == "agent_message" or .item.type == "message")
            | .item.content // .item.text // empty
        ' "$EVENTS_FILE" | tail -1)

        if [[ -z "$CONTENT" ]]; then
            # Fallback: try extracting from turn.completed
            CONTENT=$(jq -r '
                select(.type == "turn.completed")
                | .response.output[-1].content // empty
            ' "$EVENTS_FILE" | tail -1)
        fi

        if [[ -z "$CONTENT" ]]; then
            echo "ERROR: No agent message found in events file" >&2
            exit 1
        fi

        # Try to parse as JSON (structured output) — if it fails, output as-is
        if echo "$CONTENT" | jq . &>/dev/null 2>&1; then
            echo "$CONTENT" | jq .
        else
            echo "$CONTENT"
        fi
        ;;

    --progress)
        # Summarize execution progress
        echo "=== Codex Execution Summary ==="

        # Count turns
        TURNS=$(jq -r 'select(.type == "turn.completed") | .type' "$EVENTS_FILE" | wc -l | tr -d ' ')
        echo "Turns: $TURNS"

        # Count tool calls / command executions
        COMMANDS=$(jq -r '
            select(.type == "item.completed")
            | select(.item.type == "command_execution" or .item.type == "tool_call" or .item.type == "mcp_tool_call")
            | .item.type
        ' "$EVENTS_FILE" | wc -l | tr -d ' ')
        echo "Tool calls: $COMMANDS"

        # List command executions
        EXEC_LIST=$(jq -r '
            select(.type == "item.completed")
            | select(.item.type == "command_execution")
            | .item.command // .item.name // "unknown"
        ' "$EVENTS_FILE" 2>/dev/null)
        if [[ -n "$EXEC_LIST" ]]; then
            echo ""
            echo "Commands executed:"
            echo "$EXEC_LIST" | while read -r cmd; do
                echo "  - $cmd"
            done
        fi

        # Token usage from turn.completed events
        INPUT_TOKENS=$(jq -r '
            select(.type == "turn.completed")
            | .usage.input_tokens // 0
        ' "$EVENTS_FILE" | paste -sd+ - | bc 2>/dev/null || echo "0")
        OUTPUT_TOKENS=$(jq -r '
            select(.type == "turn.completed")
            | .usage.output_tokens // 0
        ' "$EVENTS_FILE" | paste -sd+ - | bc 2>/dev/null || echo "0")
        CACHED_TOKENS=$(jq -r '
            select(.type == "turn.completed")
            | .usage.cached_input_tokens // 0
        ' "$EVENTS_FILE" | paste -sd+ - | bc 2>/dev/null || echo "0")

        echo ""
        echo "Token usage:"
        echo "  Input:  $INPUT_TOKENS (cached: $CACHED_TOKENS)"
        echo "  Output: $OUTPUT_TOKENS"

        # Check for errors
        ERRORS=$(jq -r 'select(.type == "turn.failed" or .type == "error") | .type' "$EVENTS_FILE" | wc -l | tr -d ' ')
        if [[ "$ERRORS" -gt 0 ]]; then
            echo ""
            echo "ERRORS: $ERRORS (use --errors for details)"
        fi
        ;;

    --errors)
        # Extract error events
        ERRORS=$(jq '
            select(.type == "turn.failed" or .type == "error")
        ' "$EVENTS_FILE")

        if [[ -z "$ERRORS" ]]; then
            echo "No errors found."
            exit 0
        fi

        echo "$ERRORS" | jq .
        ;;

    *)
        echo "Unknown mode: $MODE" >&2
        echo "Usage: parse-jsonl.sh <events.jsonl> [--output|--progress|--errors]" >&2
        exit 1
        ;;
esac
