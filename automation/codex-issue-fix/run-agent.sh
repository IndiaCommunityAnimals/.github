#!/usr/bin/env bash
# Shared controller for preparing an isolated repository and producing a
# reviewed, secret-scanned patch. Publishing is intentionally owned by a later
# workflow step that never exposes GitHub credentials to Codex.
set -euo pipefail

MODE="${1:-}"
REPOSITORY_ROOT="${REPOSITORY_ROOT:?}"

SCRATCH="${RUNNER_TEMP:?}/codex-issue-fix"
ISSUE_FILE="${SCRATCH}/issue.md"
PROMPT_FILE="${SCRATCH}/trusted-prompt.md"
AGENT_RESULT="${SCRATCH}/agent-result.json"
OUTPUT_SCHEMA="${SCRATCH}/agent-output.schema.json"
AGENT_WORK="${SCRATCH}/agent-work"
BASELINE_FILE="${SCRATCH}/baseline.sha"
PATCH_FILE="${SCRATCH}/agent.patch"
VALIDATION_SKILL="${AGENT_WORK}/.agents/skills/repository-validation/SKILL.md"

write_outputs() {
  local ready="$1"
  local reason="$2"
  {
    echo "${3}=${ready}"
    echo "stop_reason<<CODEX_STOP_REASON"
    echo "$reason"
    echo "CODEX_STOP_REASON"
  } >> "$GITHUB_OUTPUT"
}

is_common_protected_path() {
  local changed_file="$1"
  case "$changed_file" in
    .agents | .agents/* | .codex | .codex/* | .github | .github/* | AGENTS.md | .gitignore)
      return 0
      ;;
    .env | .env.* | */.env | */.env.*)
      [[ "$changed_file" != .env.example && "$changed_file" != */.env.example ]]
      return
      ;;
    *)
      return 1
      ;;
  esac
}

prepare_repository() {
  rm -rf -- "$AGENT_WORK"
  mkdir -p "$AGENT_WORK"
  git -C "$REPOSITORY_ROOT" archive HEAD | tar -x -C "$AGENT_WORK"
  git -C "$AGENT_WORK" init -q
  git -C "$AGENT_WORK" config user.name "codex-baseline"
  git -C "$AGENT_WORK" config user.email "codex-baseline@localhost"
  git -C "$AGENT_WORK" add --all
  git -C "$AGENT_WORK" commit -q -m "Codex isolated baseline"
  git -C "$AGENT_WORK" rev-parse HEAD > "$BASELINE_FILE"

  if [ ! -f "$VALIDATION_SKILL" ]; then
    write_outputs false \
      "Target repository is missing .agents/skills/repository-validation/SKILL.md" \
      prepared
    return
  fi

  local setup_script="${AGENT_WORK}/.agents/skills/repository-validation/scripts/setup.sh"
  if [ -e "$setup_script" ]; then
    if [ ! -x "$setup_script" ]; then
      write_outputs false "Repository validation setup.sh is not executable" prepared
      return
    fi
    if ! "$setup_script" "$AGENT_WORK"; then
      write_outputs false "Repository validation environment setup failed" prepared
      return
    fi
  fi

  if ! git -C "$AGENT_WORK" diff --quiet HEAD ||
    ! git -C "$AGENT_WORK" diff --cached --quiet HEAD; then
    write_outputs false "Repository validation setup modified tracked files" prepared
    return
  fi

  local untracked
  untracked="$(git -C "$AGENT_WORK" ls-files --others --exclude-standard)"
  if [ -n "$untracked" ]; then
    echo "::error::Validation setup created non-ignored files:"
    printf '%s\n' "$untracked"
    write_outputs false \
      "Repository validation setup created non-ignored files" prepared
    return
  fi

  write_outputs true "Repository validation environment is ready" prepared
}

implement_issue() {
  : "${CODEX_AUTH_FILE:?}"
  local secret_scanner="${SECRET_SCANNER:?}"
  local baseline
  baseline="$(cat "$BASELINE_FILE")"

  clear_codex_auth() {
    if [ -f "$CODEX_AUTH_FILE" ]; then
      : > "$CODEX_AUTH_FILE"
      chmod 600 "$CODEX_AUTH_FILE"
    fi
  }
  trap clear_codex_auth EXIT

  local prompt
  prompt="$(cat "$PROMPT_FILE")

<github_issue>
$(cat "$ISSUE_FILE")
</github_issue>"

  : > "$AGENT_RESULT"
  local codex_exit=0
  (
    cd "$AGENT_WORK"
    env -u GH_TOKEN -u GITHUB_TOKEN codex exec \
      --sandbox workspace-write \
      --config 'approval_policy="never"' \
      --ignore-user-config \
      --ignore-rules \
      --skip-git-repo-check \
      --ephemeral \
      --output-schema "$OUTPUT_SCHEMA" \
      --output-last-message "$AGENT_RESULT" \
      "$prompt"
  ) > "${SCRATCH}/codex.log" 2>&1 || codex_exit=$?

  clear_codex_auth

  if [ "$codex_exit" -ne 0 ]; then
    write_outputs false "Codex agent execution failed" patch_ready
    return
  fi
  if ! jq -e '
    (.approach | type == "string") and
    (.files_changed | type == "array") and
    (.validation.status | IN("passed", "failed", "blocked")) and
    (.validation.commands | type == "array" and length > 0) and
    (.validation.failure_reason | type == "string") and
    (.validation.status == "passed" or (.validation.failure_reason | length > 0)) and
    (.risks | type == "array") and
    (.documentation | type == "string")
  ' "$AGENT_RESULT" >/dev/null; then
    write_outputs false "Codex returned an invalid structured result" patch_ready
    return
  fi

  git -C "$AGENT_WORK" add -N --all
  local changed_files=()
  while IFS= read -r -d '' changed_file; do
    changed_files+=("$changed_file")
  done < <(git -C "$AGENT_WORK" diff --name-only -z \
    --diff-filter=ACDMRTUXB "$baseline")

  if [ "${#changed_files[@]}" -eq 0 ]; then
    write_outputs false "Issue could not be implemented safely; Codex made no changes" \
      patch_ready
    return
  fi
  for changed_file in "${changed_files[@]}"; do
    if is_common_protected_path "$changed_file"; then
      echo "::error::Codex attempted to change protected path: $changed_file"
      write_outputs false "Rejected because Codex changed a protected path" patch_ready
      return
    fi
  done

  git -C "$AGENT_WORK" add --all
  git -C "$AGENT_WORK" commit -q -m "Codex candidate change"
  local candidate
  candidate="$(git -C "$AGENT_WORK" rev-parse HEAD)"

  local scan_exit=0
  "$secret_scanner" git --redact --no-banner --no-color \
    --log-opts="${baseline}..${candidate}" "$AGENT_WORK" || scan_exit=$?
  if [ "$scan_exit" -ne 0 ]; then
    if [ "$scan_exit" -eq 1 ]; then
      write_outputs false \
        "Secret scanning found a credential or sensitive value; no branch was published" \
        patch_ready
    else
      write_outputs false \
        "Secret scanning could not complete safely; no branch was published" \
        patch_ready
    fi
    return
  fi

  local result_scan_dir="${SCRATCH}/result-scan"
  rm -rf -- "$result_scan_dir"
  mkdir -p "$result_scan_dir"
  cp "$AGENT_RESULT" "${result_scan_dir}/agent-result.json"
  scan_exit=0
  "$secret_scanner" dir --redact --no-banner --no-color "$result_scan_dir" ||
    scan_exit=$?
  if [ "$scan_exit" -ne 0 ]; then
    if [ "$scan_exit" -eq 1 ]; then
      write_outputs false \
        "Secret scanning found a sensitive value in the Codex report; no branch was published" \
        patch_ready
    else
      write_outputs false \
        "Codex report secret scanning could not complete safely; no branch was published" \
        patch_ready
    fi
    return
  fi

  git -C "$AGENT_WORK" diff --binary "$baseline" "$candidate" > "$PATCH_FILE"
  if [ ! -s "$PATCH_FILE" ]; then
    write_outputs false "Codex changes produced an empty patch" patch_ready
    return
  fi

  write_outputs true "Candidate changes passed the common safety gates" patch_ready
}

case "$MODE" in
  prepare)
    prepare_repository
    ;;
  implement)
    implement_issue
    ;;
  *)
    echo "Usage: $0 prepare|implement" >&2
    exit 2
    ;;
esac
