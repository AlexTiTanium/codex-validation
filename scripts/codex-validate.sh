#!/usr/bin/env bash
# codex-validate.sh - Run Codex CLI for plan/code validation with JSONL streaming
#
# Usage:
#   codex-validate.sh plan PROMPT_FILE [OUTPUT_DIR]
#   codex-validate.sh resume "PROMPT" [OUTPUT_DIR]
#   codex-validate.sh review [--uncommitted|--base BRANCH|--commit SHA] "INSTRUCTIONS" [OUTPUT_DIR]
#   codex-validate.sh exec PROMPT_FILE [OUTPUT_DIR]
#
# Environment:
#   CODEX_BIN                - Override codex binary (default: codex)
#   CODEX_MODEL              - Override model (default: uses config.toml)
#   CODEX_REVIEW_MODEL       - Override model for review mode (default: CODEX_MODEL)
#   CODEX_WORKDIR            - Override working directory (default: current dir)
#   CODEX_REASONING_EFFORT   - Override reasoning effort (default: medium)
#   CODEX_EPHEMERAL          - Set to "true" to disable session persistence
#   CODEX_EXCHANGE_DIR       - Override exchange directory (default: $CODEX_WORKDIR/.claude/codex)
#   CODEX_SESSION_ID         - Override session ID for isolated subdirectory (default: auto-generated)
#
# Output:
#   All modes produce JSONL event streams via --json flag.
#   Use parse-jsonl.sh to extract structured output, progress, or errors.
#   Last line: ---CODEX_OUTPUT_FILE:/path/to/events.jsonl

set -euo pipefail

MODE="${1:?Usage: codex-validate.sh <plan|resume|review|exec> ...}"
shift

CODEX_BIN="${CODEX_BIN:-codex}"
CODEX_WORKDIR="${CODEX_WORKDIR:-$(pwd)}"
CODEX_REASONING_EFFORT="${CODEX_REASONING_EFFORT:-medium}"

# Exchange directory for prompt/output files (project-local, no permission prompts)
# Each invocation gets an isolated subdirectory to prevent parallel runs from clobbering
CODEX_SESSION_ID="${CODEX_SESSION_ID:-$(date +%s)-$$}"
CODEX_EXCHANGE_DIR="${CODEX_EXCHANGE_DIR:-${CODEX_WORKDIR}/.claude/codex/${CODEX_SESSION_ID}}"
mkdir -p "$CODEX_EXCHANGE_DIR"

# Resolve plugin directory for schema file
PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CODEX_OUTPUT_SCHEMA="${CODEX_OUTPUT_SCHEMA:-${PLUGIN_DIR}/skills/codex-validation/references/review-output-schema.json}"

# --- Pre-flight checks ---
if ! command -v "$CODEX_BIN" &>/dev/null; then
    echo "ERROR: Codex binary not found: $CODEX_BIN" >&2
    echo "Install via: brew install codex" >&2
    exit 127
fi

if [[ ! -f "${HOME}/.codex/config.toml" ]]; then
    echo "WARNING: No config found at ~/.codex/config.toml — using defaults" >&2
fi

case "$MODE" in
    plan)
        # Plan validation: read-only sandbox, JSONL streaming, session saved for iteration
        PROMPT_FILE="${1:?Missing prompt file path}"
        if [[ ! -f "$PROMPT_FILE" ]]; then
            echo "ERROR: Prompt file not found: $PROMPT_FILE" >&2
            exit 1
        fi

        EVENTS_FILE="${CODEX_EXCHANGE_DIR}/events-plan.jsonl"

        # Build flags as array (not string) for proper word splitting
        EXEC_FLAGS=()
        [[ -n "${CODEX_MODEL:-}" ]] && EXEC_FLAGS+=(-m "$CODEX_MODEL")
        [[ "$CODEX_WORKDIR" != "$(pwd)" ]] && EXEC_FLAGS+=(-C "$CODEX_WORKDIR")
        EXEC_FLAGS+=(-c "model_reasoning_effort=\"$CODEX_REASONING_EFFORT\"")
        [[ -f "$CODEX_OUTPUT_SCHEMA" ]] && EXEC_FLAGS+=(--output-schema "$CODEX_OUTPUT_SCHEMA")

        cat "$PROMPT_FILE" | "$CODEX_BIN" exec \
            --json \
            --sandbox read-only \
            "${EXEC_FLAGS[@]}" \
            - | tee "$EVENTS_FILE"

        echo "---CODEX_OUTPUT_FILE:${EVENTS_FILE}"
        ;;

    resume)
        # Resume last session for iteration rounds (with JSONL streaming)
        PROMPT="${1:?Missing prompt argument}"
        EVENTS_FILE="${CODEX_EXCHANGE_DIR}/events-resume-$(date +%s).jsonl"

        # resume does not support -C; use cd (--last is cwd-filtered)
        cd "$CODEX_WORKDIR"

        # Check sessions exist
        if [[ ! -d "${HOME}/.codex/sessions" ]] || [[ -z "$(ls -A "${HOME}/.codex/sessions/" 2>/dev/null)" ]]; then
            echo "ERROR: No codex sessions found. Run plan mode first to create a session." >&2
            exit 1
        fi

        RESUME_FLAGS=()
        [[ -n "${CODEX_MODEL:-}" ]] && RESUME_FLAGS+=(-m "$CODEX_MODEL")
        RESUME_FLAGS+=(-c "model_reasoning_effort=\"$CODEX_REASONING_EFFORT\"")

        set +e
        "$CODEX_BIN" exec resume --last \
            --json \
            "${RESUME_FLAGS[@]}" \
            "$PROMPT" 2>&1 | tee "$EVENTS_FILE"
        PIPE_STATUS=("${PIPESTATUS[@]}")
        set -e

        echo "---CODEX_OUTPUT_FILE:${EVENTS_FILE}"

        if [[ ${PIPE_STATUS[0]} -ne 0 ]]; then
            echo "---CODEX_ERROR: codex exited with code ${PIPE_STATUS[0]}" >&2
            exit "${PIPE_STATUS[0]}"
        fi
        if [[ ${PIPE_STATUS[1]} -ne 0 ]]; then
            echo "---CODEX_ERROR: tee failed with code ${PIPE_STATUS[1]} (output file may be incomplete)" >&2
        fi
        ;;

    review)
        # Code review mode using built-in review subcommand (with JSONL streaming)
        REVIEW_SPECIFIC_FLAGS=()
        INSTRUCTIONS=""

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --uncommitted) REVIEW_SPECIFIC_FLAGS+=(--uncommitted); shift ;;
                --base) REVIEW_SPECIFIC_FLAGS+=(--base "$2"); shift 2 ;;
                --commit) REVIEW_SPECIFIC_FLAGS+=(--commit "$2"); shift 2 ;;
                --title) REVIEW_SPECIFIC_FLAGS+=(--title "$2"); shift 2 ;;
                *)
                    if [[ -z "$INSTRUCTIONS" ]]; then
                        INSTRUCTIONS="$1"
                    fi
                    shift
                    ;;
            esac
        done

        EVENTS_FILE="${CODEX_EXCHANGE_DIR}/events-review.jsonl"

        # Build review-compatible flags
        REVIEW_FLAGS=()
        REVIEW_MODEL="${CODEX_REVIEW_MODEL:-${CODEX_MODEL:-}}"
        [[ -n "$REVIEW_MODEL" ]] && REVIEW_FLAGS+=(-m "$REVIEW_MODEL")
        REVIEW_FLAGS+=(-c "model_reasoning_effort=\"$CODEX_REASONING_EFFORT\"")
        [[ "${CODEX_EPHEMERAL:-}" == "true" ]] && REVIEW_FLAGS+=(--ephemeral)

        # review does not support -C; use cd
        cd "$CODEX_WORKDIR"

        set +e
        "$CODEX_BIN" exec review \
            --json \
            "${REVIEW_FLAGS[@]}" \
            ${REVIEW_SPECIFIC_FLAGS[@]+"${REVIEW_SPECIFIC_FLAGS[@]}"} \
            "$INSTRUCTIONS" 2>&1 | tee "$EVENTS_FILE"
        PIPE_STATUS=("${PIPESTATUS[@]}")
        set -e

        echo "---CODEX_OUTPUT_FILE:${EVENTS_FILE}"

        if [[ ${PIPE_STATUS[0]} -ne 0 ]]; then
            echo "---CODEX_ERROR: codex exited with code ${PIPE_STATUS[0]}" >&2
            exit "${PIPE_STATUS[0]}"
        fi
        if [[ ${PIPE_STATUS[1]} -ne 0 ]]; then
            echo "---CODEX_ERROR: tee failed with code ${PIPE_STATUS[1]} (output file may be incomplete)" >&2
        fi
        ;;

    exec)
        # Generic one-shot exec mode (ephemeral, JSONL streaming)
        PROMPT_FILE="${1:?Missing prompt file path}"
        if [[ ! -f "$PROMPT_FILE" ]]; then
            echo "ERROR: Prompt file not found: $PROMPT_FILE" >&2
            exit 1
        fi

        EVENTS_FILE="${CODEX_EXCHANGE_DIR}/events-exec.jsonl"

        # Build exec-compatible flags
        EXEC_FLAGS=()
        [[ -n "${CODEX_MODEL:-}" ]] && EXEC_FLAGS+=(-m "$CODEX_MODEL")
        [[ "$CODEX_WORKDIR" != "$(pwd)" ]] && EXEC_FLAGS+=(-C "$CODEX_WORKDIR")
        EXEC_FLAGS+=(-c "model_reasoning_effort=\"$CODEX_REASONING_EFFORT\"")
        [[ -f "$CODEX_OUTPUT_SCHEMA" ]] && EXEC_FLAGS+=(--output-schema "$CODEX_OUTPUT_SCHEMA")

        cat "$PROMPT_FILE" | "$CODEX_BIN" exec \
            --json \
            --sandbox read-only \
            --ephemeral \
            "${EXEC_FLAGS[@]}" \
            - | tee "$EVENTS_FILE"

        echo "---CODEX_OUTPUT_FILE:${EVENTS_FILE}"
        ;;

    *)
        echo "Unknown mode: $MODE" >&2
        echo "Usage: codex-validate.sh <plan|resume|review|exec> ..." >&2
        exit 1
        ;;
esac
