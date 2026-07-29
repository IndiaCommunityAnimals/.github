#!/usr/bin/env bash
# Shared controller: isolate Codex, enforce profile-specific paths and checks,
# then apply one validated patch to the authenticated caller-repository checkout.
set -euo pipefail

ISSUE_NUMBER="${ISSUE_NUMBER:?}"
TARGET_BRANCH="${TARGET_BRANCH:?}"
FIX_BRANCH="${FIX_BRANCH:?}"
PROFILE="${PROFILE:?}"
REPOSITORY_ROOT="${REPOSITORY_ROOT:?}"
CODEX_AUTH_FILE="${CODEX_AUTH_FILE:?}"

SCRATCH="${RUNNER_TEMP:?}/codex-issue-fix"
ISSUE_FILE="${SCRATCH}/issue.md"
PROMPT_FILE="${SCRATCH}/trusted-prompt.md"
AGENT_SUMMARY="${SCRATCH}/agent-summary.md"
AGENT_WORK="${SCRATCH}/agent-work"
PATCH_FILE="${SCRATCH}/agent.patch"
GATE_LOG="${SCRATCH}/validation.log"

# These flags keep runner/user configuration from silently changing CI behavior
# and ensure the model edits only the disposable exported repository.
CODEX=(
  codex exec
  --sandbox workspace-write
  --ephemeral
  --ignore-user-config
  --ignore-rules
  --skip-git-repo-check
)

# Backend commands use only the isolated CI database. Other profiles do not
# receive an unrelated DATABASE_URL environment variable.
if [ "$PROFILE" = "backend" ]; then
  export DATABASE_URL="postgresql://cac:cac@127.0.0.1:5432/cac_test"
fi

# Validation does not need model credentials. Truncate the exact trusted path
# after Codex returns and again on unexpected controller exit as a safety net.
clear_codex_auth() {
  if [ -f "$CODEX_AUTH_FILE" ]; then
    : > "$CODEX_AUTH_FILE"
    chmod 600 "$CODEX_AUTH_FILE"
  fi
}
trap clear_codex_auth EXIT

# Expected no-change outcomes use step outputs so the workflow can leave a clear
# issue comment instead of failing with an opaque shell error.
write_outputs() {
  local did_fix="$1"
  local stop_reason="$2"
  {
    echo "did_fix=$did_fix"
    echo "stop_reason=$stop_reason"
  } >> "$GITHUB_OUTPUT"
}

# Reject control files, secrets, local environment files, and Terraform inputs
# before applying the profile-specific allowlist.
is_protected_path() {
  local changed_file="$1"
  case "$changed_file" in
    .github/* | AGENTS.md | .gitignore | \
      *.tfstate | *.tfstate.* | *.tfplan | */.terraform/*)
      return 0
      ;;
    .env | .env.* | */.env | */.env.*)
      # Placeholder-only examples are reviewable configuration contracts; every
      # real environment file and environment-specific variant stays protected.
      [[ "$changed_file" != .env.example && "$changed_file" != */.env.example ]]
      return
      ;;
    *.tfvars)
      # Shareable example inputs are allowed; real tfvars remain protected.
      [[ "$changed_file" != *.tfvars.example ]]
      return
      ;;
    *)
      return 1
      ;;
  esac
}

# Each repository profile has an explicit review boundary. Adding a new stack
# requires a deliberate central change rather than accepting arbitrary paths.
is_allowed_path() {
  local changed_file="$1"
  case "$PROFILE" in
    infrastructure)
      case "$changed_file" in
        infra/* | README.md) return 0 ;;
      esac
      ;;
    frontend)
      case "$changed_file" in
        src/* | public/* | tests/* | package.json | package-lock.json | \
          README.md | .env.example | index.html | vite.config.* | tsconfig* | \
          tailwind.config.* | postcss.config.* | Dockerfile | nginx.conf | \
          env.js.template | docker-entrypoint.sh | scripts/*)
          return 0
          ;;
      esac
      ;;
    backend)
      case "$changed_file" in
        api/* | README.md | docs/*) return 0 ;;
      esac
      ;;
    *)
      echo "::error::Unknown repository profile: $PROFILE"
      return 1
      ;;
  esac
  return 1
}

# Validation runs outside the model process and is therefore an independent
# gate. Logs are retained for diagnostics but a failed gate never reaches Git.
validate_agent_work() {
  local failed=0
  : > "$GATE_LOG"

  case "$PROFILE" in
    infrastructure)
      echo "=== terraform fmt -check -recursive ===" >> "$GATE_LOG"
      (
        cd "$AGENT_WORK" &&
          terraform fmt -check -recursive -no-color -diff
      ) >> "$GATE_LOG" 2>&1 || failed=1

      echo "=== terraform validate: infra/environments/preprod ===" >> "$GATE_LOG"
      (
        cd "$AGENT_WORK/infra/environments/preprod" &&
          terraform init -backend=false -input=false -no-color &&
          terraform validate -no-color
      ) >> "$GATE_LOG" 2>&1 || failed=1

      if command -v tflint >/dev/null 2>&1; then
        echo "=== tflint --recursive ===" >> "$GATE_LOG"
        (
          cd "$AGENT_WORK" &&
            tflint --recursive --no-color
        ) >> "$GATE_LOG" 2>&1 || failed=1
      fi
      ;;
    frontend)
      echo "=== npm ci ===" >> "$GATE_LOG"
      (cd "$AGENT_WORK" && npm ci) >> "$GATE_LOG" 2>&1 || failed=1

      echo "=== npm test ===" >> "$GATE_LOG"
      (cd "$AGENT_WORK" && npm test) >> "$GATE_LOG" 2>&1 || failed=1

      echo "=== npm run audit:ci ===" >> "$GATE_LOG"
      (cd "$AGENT_WORK" && npm run audit:ci) >> "$GATE_LOG" 2>&1 || failed=1

      echo "=== npm run build ===" >> "$GATE_LOG"
      (cd "$AGENT_WORK" && npm run build) >> "$GATE_LOG" 2>&1 || failed=1
      ;;
    backend)
      echo "=== install backend requirements ===" >> "$GATE_LOG"
      python -m pip install -r "$AGENT_WORK/api/requirements.txt" \
        >> "$GATE_LOG" 2>&1 || failed=1

      echo "=== pytest -q ===" >> "$GATE_LOG"
      (
        cd "$AGENT_WORK/api" &&
          pytest -q
      ) >> "$GATE_LOG" 2>&1 || failed=1
      ;;
    *)
      echo "Unknown repository profile: $PROFILE" >> "$GATE_LOG"
      failed=1
      ;;
  esac

  return "$failed"
}

# Export tracked files without the caller checkout's Git credential, then create
# a disposable baseline commit so every model change is measurable.
rm -rf "$AGENT_WORK"
mkdir -p "$AGENT_WORK"
git -C "$REPOSITORY_ROOT" archive HEAD | tar -x -C "$AGENT_WORK"
git -C "$AGENT_WORK" init -q
git -C "$AGENT_WORK" config user.name "baseline"
git -C "$AGENT_WORK" config user.email "baseline@localhost"
git -C "$AGENT_WORK" add --all
git -C "$AGENT_WORK" commit -q -m "Agent work baseline"

# The issue is clearly delimited as untrusted data after all trusted policy and
# profile instructions have been assembled by the workflow.
PROMPT="$(cat "$PROMPT_FILE")

<github_issue>
$(cat "$ISSUE_FILE")
</github_issue>"

CODEX_EXIT=0
(
  cd "$AGENT_WORK" &&
    "${CODEX[@]}" --output-last-message "$AGENT_SUMMARY" "$PROMPT"
) 2>"${SCRATCH}/codex.log" || CODEX_EXIT=$?

# Remove usable Codex credentials before npm, pip, Terraform, or test commands
# inspect the agent-generated patch.
clear_codex_auth

if [ "$CODEX_EXIT" -ne 0 ]; then
  write_outputs false "Codex agent execution failed"
  exit 0
fi

if [ ! -s "$AGENT_SUMMARY" ]; then
  write_outputs false "Codex agent returned no implementation summary"
  exit 0
fi

# Include untracked files in the diff, then enforce both the global protection
# list and the selected repository profile's allowlist.
git -C "$AGENT_WORK" add -N --all
CHANGED_FILES=()
while IFS= read -r changed_file; do
  CHANGED_FILES+=("$changed_file")
done < <(git -C "$AGENT_WORK" diff --name-only --diff-filter=ACDMRTUXB HEAD)

if [ "${#CHANGED_FILES[@]}" -eq 0 ]; then
  write_outputs false "Issue could not be implemented safely; the agent made no changes"
  exit 0
fi

for changed_file in "${CHANGED_FILES[@]}"; do
  if is_protected_path "$changed_file" || ! is_allowed_path "$changed_file"; then
    echo "::error::Agent attempted to change protected path: $changed_file"
    write_outputs false "Rejected because the agent changed a protected path"
    exit 0
  fi
done

if ! validate_agent_work; then
  echo "::group::Repository validation failures"
  cat "$GATE_LOG"
  echo "::endgroup::"
  write_outputs false "Generated change failed repository validation gates"
  exit 0
fi

# Apply only the accepted binary-safe patch to the authenticated checkout, then
# create exactly one automation-owned commit and push with lease protection.
git -C "$AGENT_WORK" diff --binary HEAD > "$PATCH_FILE"
if [ ! -s "$PATCH_FILE" ]; then
  write_outputs false "Agent changes produced an empty patch"
  exit 0
fi

git -C "$REPOSITORY_ROOT" config user.name "github-actions[bot]"
git -C "$REPOSITORY_ROOT" config user.email \
  "41898282+github-actions[bot]@users.noreply.github.com"
git -C "$REPOSITORY_ROOT" checkout -B "$FIX_BRANCH" "origin/$TARGET_BRANCH"
git -C "$REPOSITORY_ROOT" apply --index "$PATCH_FILE"
git -C "$REPOSITORY_ROOT" commit -m "fix: address issue #${ISSUE_NUMBER}"
git -C "$REPOSITORY_ROOT" fetch origin \
  "$FIX_BRANCH:refs/remotes/origin/$FIX_BRANCH" 2>/dev/null || true
git -C "$REPOSITORY_ROOT" push --force-with-lease origin "$FIX_BRANCH"

write_outputs true "Validated changes were pushed for human review"
