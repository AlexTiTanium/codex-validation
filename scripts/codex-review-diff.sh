#!/usr/bin/env bash
# codex-review-diff.sh - Run Codex code review on git changes with JSONL streaming
#
# Usage:
#   codex-review-diff.sh uncommitted [INSTRUCTIONS]
#   codex-review-diff.sh branch BASE_BRANCH [INSTRUCTIONS]
#   codex-review-diff.sh commit SHA [INSTRUCTIONS]
#
# Environment:
#   CODEX_BIN                - Override codex binary (default: codex)
#   CODEX_WORKDIR            - Override working directory (default: current dir)
#   CODEX_MODEL              - Override model (default: uses config.toml)
#   CODEX_REVIEW_MODEL       - Override model for reviews (default: CODEX_MODEL)
#   CODEX_REASONING_EFFORT   - Override reasoning effort (default: medium)
#   CODEX_EPHEMERAL          - Set to "true" to disable session persistence
#   CODEX_EXCHANGE_DIR       - Override exchange directory (default: $CODEX_WORKDIR/.claude/codex)
#   CODEX_SESSION_ID         - Override session ID for isolated subdirectory (default: auto-generated)
#
# Output:
#   JSONL event stream via --json flag. Use parse-jsonl.sh to extract results.
#   Last line: ---CODEX_OUTPUT_FILE:/path/to/events.jsonl

set -euo pipefail

MODE="${1:?Usage: codex-review-diff.sh <uncommitted|branch|commit> ...}"
shift

CODEX_BIN="${CODEX_BIN:-codex}"
CODEX_WORKDIR="${CODEX_WORKDIR:-$(pwd)}"
CODEX_REASONING_EFFORT="${CODEX_REASONING_EFFORT:-medium}"

# Exchange directory for output files (project-local, no permission prompts)
CODEX_SESSION_ID="${CODEX_SESSION_ID:-$(date +%s)-$$}"
CODEX_EXCHANGE_DIR="${CODEX_EXCHANGE_DIR:-${CODEX_WORKDIR}/.claude/codex/${CODEX_SESSION_ID}}"
mkdir -p "$CODEX_EXCHANGE_DIR"
EVENTS_FILE="${CODEX_EXCHANGE_DIR}/events-review.jsonl"

# --- Pre-flight checks ---
if ! command -v "$CODEX_BIN" &>/dev/null; then
    echo "ERROR: Codex binary not found: $CODEX_BIN" >&2
    echo "Install via: brew install codex" >&2
    exit 127
fi

# --- Build flags valid for `codex exec review` ---
REVIEW_FLAGS=()
REVIEW_MODEL="${CODEX_REVIEW_MODEL:-${CODEX_MODEL:-}}"
if [[ -n "$REVIEW_MODEL" ]]; then
    REVIEW_FLAGS+=(-m "$REVIEW_MODEL")
fi
REVIEW_FLAGS+=(-c "model_reasoning_effort=\"$CODEX_REASONING_EFFORT\"")
if [[ "${CODEX_EPHEMERAL:-}" == "true" ]]; then
    REVIEW_FLAGS+=(--ephemeral)
fi

# review does not support -C; use cd instead
cd "$CODEX_WORKDIR"

case "$MODE" in
    uncommitted)
        INSTRUCTIONS="${1:-Review these uncommitted changes for bugs, logic errors, and code quality issues.}"

        set +e
        "$CODEX_BIN" exec review --json "${REVIEW_FLAGS[@]}" --uncommitted "$INSTRUCTIONS" 2>&1 | tee "$EVENTS_FILE"
        PIPE_STATUS=("${PIPESTATUS[@]}")
        set -e
        ;;
    branch)
        BASE="${1:?Missing base branch}"
        shift
        INSTRUCTIONS="${1:-Review the changes on this branch for bugs, logic errors, and code quality issues.}"

        set +e
        "$CODEX_BIN" exec review --json "${REVIEW_FLAGS[@]}" --base "$BASE" "$INSTRUCTIONS" 2>&1 | tee "$EVENTS_FILE"
        PIPE_STATUS=("${PIPESTATUS[@]}")
        set -e
        ;;
    commit)
        SHA="${1:?Missing commit SHA}"
        shift
        INSTRUCTIONS="${1:-Review this commit for bugs, logic errors, and code quality issues.}"

        set +e
        "$CODEX_BIN" exec review --json "${REVIEW_FLAGS[@]}" --commit "$SHA" "$INSTRUCTIONS" 2>&1 | tee "$EVENTS_FILE"
        PIPE_STATUS=("${PIPESTATUS[@]}")
        set -e
        ;;
    *)
        echo "Unknown mode: $MODE" >&2
        exit 1
        ;;
esac

echo "---CODEX_OUTPUT_FILE:${EVENTS_FILE}"

if [[ ${PIPE_STATUS[0]} -ne 0 ]]; then
    echo "---CODEX_ERROR: codex exited with code ${PIPE_STATUS[0]}" >&2
    exit "${PIPE_STATUS[0]}"
fi
if [[ ${PIPE_STATUS[1]} -ne 0 ]]; then
    echo "---CODEX_ERROR: tee failed with code ${PIPE_STATUS[1]} (output file may be incomplete)" >&2
fi
