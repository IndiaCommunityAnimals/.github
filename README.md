# Organization-Wide Codex CI Automation: Setup & Bootstrap Guide

This guide provides a step-by-step walkthrough for bootstrapping the organization-wide Codex CI automation in a new or existing GitHub organization. It covers the complete setup of the central CI control plane, the publishing GitHub App, authentication secrets, and target repository onboarding.

> [!IMPORTANT]
> **Security & Boundary Model:**
> - This automation can draft code changes, run isolated validations, push fix commits, and open pull requests.
> - **It never merges code or deploys to any environment.**
> - Merging to protected branches strictly requires human review and repository CI passing.

---

## Architecture at a Glance

The automation divides responsibilities into a **Central Control Plane** (reusable workflows and prompts) and **Target Repositories** (event callers and repository-specific validation):

```text
┌──────────────────────────────────────────────────────────────────────────────────┐
│                             NEW_ORG/.github                                      │
│                                                                                  │
│   .github/workflows/reusable-codex-issue-fix.yml   (Reusable Issue -> PR)        │
│   .github/workflows/reusable-codex-review-fix.yml  (Reusable PR Review -> Fix)   │
│   automation/codex-issue-fix/                      (Verifier, Prompt, Schema)    │
│   automation/codex-review-fix/                     (Prompts, Review Loop)        │
│   .github/ISSUE_TEMPLATE/                          (Inherited Issue Forms)       │
│   AGENTS.md                                        (Organization Agent Policy)   │
└───────────────────────▲──────────────────────────────────▲───────────────────────┘
                        │ uses: reusable workflow          │ uses: reusable workflow
                        │ with: automation_ref             │ with: automation_ref
┌───────────────────────┴──────────────────────────────────┴───────────────────────┐
│                    Target Repository (e.g. infrastructure-sandbox)               │
│                                                                                  │
│   .github/workflows/codex-issue-fix.yml            (Local issues caller)         │
│   .github/workflows/codex-review-fix.yml           (Local pull_request caller)   │
│   .agents/skills/repository-validation/                                          │
│     ├── SKILL.md                                   (Mandatory validation gates)  │
│     └── scripts/setup.sh                           (Optional toolchain installer)│
│   AGENTS.md                                        (Local repo rules)            │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### Automation Flows

1. **Issue-to-PR Flow:**
   ```text
   Issue Form Submitted (with Target Branch)
     └─► Verifier checks syntax, headings & author permissions
           ├─► Contributor: tagged `codex-run-requested` ──► Maintainer labels `codex-run-approved`
           └─► Maintainer: automatically approved
                 └─► Disposable Linux Sandbox exports codebase
                       └─► Runs optional setup.sh (installs CLI tools)
                             └─► Codex implements solution & validates locally via SKILL.md
                                   └─► Gates: Protected path check + Gitleaks scan
                                         └─► GitHub App commits to `codex/issue-<ID>` branch
                                               ├─► Validation passed: review-ready PR + `codex-run-completed`
                                               └─► Validation incomplete: draft PR + `codex-run-validation-blocked`
   ```

2. **PR Review-Fix Loop Flow:**
   ```text
   Pull Request Opened / Synchronized (same repository only)
     └─► Reviewer agent inspects diff against AGENTS.md
           └─► Discovers actionable findings & initiates negotiation loop
                 └─► Fixer agent resolves findings & validates locally via SKILL.md
                       └─► Gates: Only cited files modified + deletion thresholds satisfied
                             └─► GitHub App pushes fix commit `[codex-autofix]`
                                   └─► App publishes or updates PR evidence comment
   ```

---

## Prerequisites & Setup Placeholders

Before starting, confirm you have:
1. **GitHub Organization Owner** or admin permissions to configure GitHub Apps, Actions, and Secrets.
2. A **trusted local workstation** with the Codex CLI installed to generate initial ChatGPT authentication.
3. Target repositories with **Issues** and **GitHub Actions** enabled.

Throughout this guide, replace these placeholders with your actual values:

| Placeholder | Meaning | Example |
|---|---|---|
| `NEW_ORG` | Your destination GitHub organization name | `IndiaCommunityAnimals` |
| `TARGET_REPO` | Target repository being onboarded | `community-animal-registry-infrastructure-sandbox` |
| `CENTRAL_SHA` | 40-character commit SHA or branch (`main`) of `NEW_ORG/.github` | `main` or `e1911f8...` |
| `APP_NAME` | Name of the GitHub App for publishing | `IndiaCommunityAnimals Codex Automation` |

---

## Phase 1: Set Up Central Control Plane (`NEW_ORG/.github`)

**Where to make this change:** Create a repository literally named `.github` under `NEW_ORG`.

> [!NOTE]
> The `.github` repository holds organization-wide defaults. It must be **public** (or **internal** in GitHub Enterprise Managed Users) for organization-default community files like issue templates to inherit automatically.

### Step 1.1: Copy Automation Files

Copy the following paths from the upstream template (`IndiaCommunityAnimals/.github`) into your `NEW_ORG/.github` repository:

```text
NEW_ORG/.github/
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug-template.yml
│   │   ├── config.yml
│   │   ├── feature-template.yml
│   │   ├── general-discussion-template.yml
│   │   └── technical-task-template.yml
│   └── workflows/
│       ├── reusable-codex-issue-fix.yml
│       └── reusable-codex-review-fix.yml
├── automation/
│   ├── codex-issue-fix/
│   │   ├── agent-output.schema.json
│   │   ├── prompts/base.md
│   │   ├── run-agent.sh
│   │   └── verify-issue.js
│   └── codex-review-fix/
│       ├── prompts/
│       │   ├── evidence-template.md
│       │   └── review.md
│       └── run-loop.sh
└── AGENTS.md
```

### Step 1.2: Customize Organization Names & Documentation

The reusable workflows are now generic by default:
- They dynamically check out the current organization's central repository using `repository: ${{ github.repository_owner }}/.github`.
- Git fix commits use the neutral author `codex-automation-bot[bot]`.

You only need to review and update organization names in policy and documentation files:
1. In `AGENTS.md` and `README.md`: Update organization names and links to match `NEW_ORG`.
2. (Optional) Run a search to verify any custom branding or policy references:
   ```bash
   grep -RInE 'IndiaCommunityAnimals|animal-automation' --exclude-dir=.git .
   ```

### Step 1.3: Configure Central Workflow Access

Ensure target repositories can call these reusable workflows:
1. Navigate to: `https://github.com/organizations/NEW_ORG/repositories` → click `.github`.
2. Go to **Settings** → **Actions** → **General**.
3. Under **Access**, select **Accessible from repositories in the 'NEW_ORG' organization**.

### Step 1.4: Commit and Note the Reference

Commit all files and push to `main`. If you use immutable SHA pinning for production supply-chain defense, note the commit SHA:
```bash
git rev-parse HEAD
# Output example: e1911f81ee4d53d7da9c7f1fe68de6de2efb6dab
```
*(You will use this `CENTRAL_SHA` or `main` when configuring target repositories).*

---

## Phase 2: Create & Configure the Publishing GitHub App
![alt text](image.png)
**Where to make this change:** GitHub Organization Settings → Developer Settings.

The GitHub App creates an ephemeral, authenticated identity used by GitHub Actions to push branches, commit fixes, and open PRs. Pushes made by an App token trigger normal repository CI checks (unlike standard `GITHUB_TOKEN` pushes).

### Step 2.1: Register the App
![alt text](image-1.png)
1. Go to: `https://github.com/organizations/NEW_ORG/settings/apps`.
2. Click **New GitHub App**.
3. Fill in the required fields:

| Field | Value | Notes |
|---|---|---|
| **GitHub App name** | `NEW_ORG Codex Automation` | Must be globally unique across GitHub |
| **Homepage URL** | `https://github.com/NEW_ORG/.github` | Links to central repo docs |
| **Callback URL** | *(Leave blank)* | Not used |
| **Webhook Active** | **Uncheck** *(Deactivate)* | No webhooks needed; Actions triggers workflows |
| **Where can this app be installed?** | **Only on this account** | Keeps the App private to your org |

### Step 2.2: Set Minimum Permissions
![alt text](image-2.png)
Under **Repository permissions**, configure exactly:

| Permission | Access | Why It Is Needed |
|---|---|---|
| **Contents** | **Read and write** | Create `codex/issue-*` branches and commit fix patches |
| **Pull requests** | **Read and write** | Create pull requests and publish review evidence comments |
| **Metadata** | **Read-only** | Automatically set by GitHub for all Apps |

> [!WARNING]
> Keep all other permissions set to **No access**. Do **not** grant *Workflows: write*, *Administration*, or *Secrets* permissions.

Click **Create GitHub App**.

### Step 2.3: Record Client ID & Generate Private Key

1. On the app summary page, find the **Client ID** (e.g. `Iv23...`).
   > [!IMPORTANT]
   > Record the **Client ID**, **NOT** the numeric App ID.
2. Scroll down to **Private keys** and click **Generate a private key**.
3. A `.pem` file will download to your machine (e.g. `new-org-codex-automation.private-key.pem`).
4. Keep this file safe. This is your `PRIVATE_KEY` secret.

### Step 2.4: Install the App on Target Repositories

1. On the left sidebar of the App page, click **Install App**.
2. Click **Install** next to `NEW_ORG`.
3. Choose **Only select repositories**, and select your target repositories (e.g. `community-animal-registry-infrastructure-sandbox`).
4. Click **Save** / **Install**.

---

## Phase 3: Set Up Authentication & Organization Secrets
![alt text](image-3.png)
**Where to make this change:** Workstation terminal + GitHub Organization Secrets settings.

The automation requires three organization secrets:

| Secret Name | Exact Content | Purpose |
|---|---|---|
| `CLIENT_ID` | String (Client ID from Step 2.3) | Used by `actions/create-github-app-token` |
| `PRIVATE_KEY` | Full PEM content (including `BEGIN`/`END` lines) | Signs JWT for App token minting |
| `CODEX_AUTH_JSON` | Raw contents of `~/.codex/auth.json` | Authenticates `codex exec` in the sandbox |

### Step 3.1: Generate `CODEX_AUTH_JSON`

On your local workstation:
1. Ensure the Codex CLI is installed:
   ```bash
   npm install -g @openai/codex@0.145.0
   ```
2. Configure file-backed credential storage:
   ```bash
   mkdir -p ~/.codex
   cat << 'EOF' >> ~/.codex/config.toml
   cli_auth_credentials_store = "file"
   EOF
   ```
3. Run authentication:
   ```bash
   codex login
   ```
   *Follow the browser prompts to sign in.*
4. Verify your `auth.json` file without printing secret tokens:
   ```bash
   jq '{
     auth_mode,
     has_tokens: (.tokens != null),
     has_refresh_token: ((.tokens.refresh_token // "") != ""),
     last_refresh
   }' ~/.codex/auth.json
   ```
   *Verify that `auth_mode` is `chatgpt` and `has_refresh_token` is `true`.*

### Step 3.2: Store Secrets in GitHub Organization

You can set these via the GitHub Web UI or using the GitHub CLI:

#### Option A: Using the GitHub CLI (`gh`)
```bash
export ORG="NEW_ORG"
export TARGET_REPOS="community-animal-registry-infrastructure-sandbox"

# 1. Set CLIENT_ID
gh secret set CLIENT_ID --org "$ORG" --repos "$TARGET_REPOS" --body "Iv23..."

# 2. Set PRIVATE_KEY
gh secret set PRIVATE_KEY --org "$ORG" --repos "$TARGET_REPOS" < /path/to/app-private-key.pem

# 3. Set CODEX_AUTH_JSON (raw JSON file)
gh secret set CODEX_AUTH_JSON --org "$ORG" --repos "$TARGET_REPOS" < ~/.codex/auth.json
```

#### Option B: Using GitHub Web UI
1. Go to: `https://github.com/organizations/NEW_ORG/settings/secrets/actions`.
2. Click **New organization secret**.
3. Add `CLIENT_ID`, `PRIVATE_KEY`, and `CODEX_AUTH_JSON`.
4. Under **Repository access**, select **Selected repositories** and choose your target repository.

---

## Phase 4: Onboard a Target Repository

**Where to make this change:** Inside each target repository (e.g. `TARGET_REPO`).

Using [community-animal-registry-infrastructure-sandbox](file:///Users/mindstix-dev/Documents/Codex/community-animal-registry-infrastructure-sandbox) as the reference, follow these steps to onboard a repository.

### Step 4.1: Add Repository `AGENTS.md`

Create `AGENTS.md` in the root of the repository. It should inherit the organization policy and specify local conventions:

````markdown
# Repository Guidelines

## Policy Hierarchy
This repository follows the organization-wide agent policy defined in
`NEW_ORG/.github/AGENTS.md`. The rules in this file extend that policy.

## Technical Architecture & Constraints
- Add architecture context (e.g. Terraform modules, directory layout, language frameworks).
- Enforce safety boundaries: do NOT run remote cloud mutating commands (`apply`, `destroy`, `plan` with remote state).
- Explicitly define coding styles, formatting, and file structures.
```

### Step 4.2: Add Validation Skill (`SKILL.md`)

Create the directory `.agents/skills/repository-validation/` and file `SKILL.md`:

```bash
mkdir -p .agents/skills/repository-validation
```

Create `.agents/skills/repository-validation/SKILL.md`:

```markdown
---
name: repository-validation
description: Validate changes before Codex finishes implementation. Runs safe local checks without accessing remote state or mutating live resources.
---

# Validate repository changes

The trusted workflow runs `scripts/setup.sh` before Codex starts. Codex must not
run provider-facing validation inside its restricted sandbox. After Codex
returns, the controller runs the protected baseline copy of
`scripts/validate.sh` on the trusted GitHub runner. Repository CI remains the
final merge gate.

The trusted validator runs exactly:

```bash
terraform -chdir=infra/environments/preprod validate -no-color
```

Codex returns a blocked/skipped pending placeholder. The controller replaces it
with the actual result, sends implementation failures through one bounded repair
turn, and validates once more. Do not run Terraform plan, apply, TFLint, or any
command requiring cloud credentials or remote state locks.
````

*(For a Node.js or Python repository, replace the bash commands with `npm test`, `pytest`, `eslint`, `ruff check`, etc.).*

### Step 4.3: Add Optional Toolchain Setup Script (`setup.sh`)

If the disposable runner needs pinned CLI tools, modules, or providers, add a
`setup.sh` script:

```bash
mkdir -p .agents/skills/repository-validation/scripts
```

Create `.agents/skills/repository-validation/scripts/setup.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

runner_temp="${RUNNER_TEMP:?}"
terraform_version="1.15.8"
bin_dir="${runner_temp}/codex-validation-bin"
mkdir -p "$bin_dir"

# Download and verify Terraform
curl --fail --silent --show-error --location \
  --output "${runner_temp}/terraform.zip" \
  "https://releases.hashicorp.com/terraform/${terraform_version}/terraform_${terraform_version}_linux_amd64.zip"
echo "d25ce7b6902013ad905db3d2eab0be4cd905887fe88b81a6171b8d5503c31f3d  ${runner_temp}/terraform.zip" | sha256sum --check --status
unzip -oq "${runner_temp}/terraform.zip" -d "$bin_dir"
chmod 700 "${bin_dir}/terraform"
echo "$bin_dir" >> "${GITHUB_PATH:?}"

# Repository-specific setup must also initialize modules/providers with
# -backend=false, create a lockfile-backed provider mirror, and export its
# writable TF_DATA_DIR/TF_PLUGIN_CACHE_DIR/TF_CLI_CONFIG_FILE via GITHUB_ENV.
```

> [!IMPORTANT]
> Ensure `setup.sh` has executable permissions in Git:
> ```bash
> chmod +x .agents/skills/repository-validation/scripts/setup.sh
> git add --chmod=+x .agents/skills/repository-validation/scripts/setup.sh
> ```

Add `.agents/skills/repository-validation/scripts/validate.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  command) echo 'terraform -chdir=infra/environments/preprod validate -no-color' ;;
  run) terraform -chdir="$2/infra/environments/preprod" validate -no-color ;;
  *) exit 2 ;;
esac
```

Commit it with executable mode as well. The interface is `command` plus
`run <repository-root>`; exit `0` means passed, `1` means failed, and `2` means
the trusted environment is blocked.

### Step 4.4: Add the Issue Fix Caller Workflow

Create `.github/workflows/codex-issue-fix.yml`:

```yaml
name: 🤖 Codex Issue Fix

on:
  issues:
    types: [opened, edited, reopened, labeled, unlabeled]

permissions:
  contents: write
  issues: write
  pull-requests: write

jobs:
  issue-fix:
    # Trigger only on implementation issues with a Target branch heading,
    # or when maintainer approval label is added.
    if: >-
      contains(github.event.issue.body, '### Target branch') &&
      ((github.event.action != 'labeled' && github.event.action != 'unlabeled') ||
       github.event.label.name == 'codex-run-approved')
    uses: NEW_ORG/.github/.github/workflows/reusable-codex-issue-fix.yml@main
    with:
      automation_ref: main
      approval_label: codex-run-approved
      request_label: codex-run-requested
      # Set to true for infrastructure repos requiring AWS / Terraform MCP tools
      enable_aws_mcp: true
      enable_terraform_mcp: true
    secrets:
      CODEX_AUTH_JSON: ${{ secrets.CODEX_AUTH_JSON }}
      CLIENT_ID: ${{ secrets.CLIENT_ID }}
      PRIVATE_KEY: ${{ secrets.PRIVATE_KEY }}
```

> [!IMPORTANT]
> **Why `NEW_ORG` must be static in `jobs.<job_id>.uses` (GitHub Actions Limitation):**
> You **cannot** use dynamic expressions like `${{ github.repository_owner }}` in the `uses:` line of caller workflows.
> - GitHub Actions parses `uses:` during workflow graph compilation before runtime contexts exist. Trying to use an expression in `uses:` will cause GitHub to error: `The workflow is not valid. The uses attribute cannot contain expressions.`
> - Therefore, `jobs.issue-fix.uses` must always specify your organization name as an exact static string (e.g. `NEW_ORG/.github/...` or `Ai-Automation-testing-01/.github/...`).
> - Inside the central workflow steps, expressions *are* supported, which is why the central reusable workflow dynamically checks out `${{ github.repository_owner }}/.github` without hardcoding.

### Step 4.5: Add the Review-Fix Caller Workflow

Create `.github/workflows/codex-review-fix.yml`:

```yaml
name: Codex Review-Fix Loop (EXPERIMENTAL)

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  loop:
    # Restrict strictly to same-repository pull requests
    if: github.event.pull_request.head.repo.full_name == github.repository
    permissions:
      contents: write
      pull-requests: write
    uses: NEW_ORG/.github/.github/workflows/reusable-codex-review-fix.yml@main
    with:
      automation_ref: main
      profile: infrastructure # Optional caller metadata
    secrets:
      CODEX_AUTH_JSON: ${{ secrets.CODEX_AUTH_JSON }}
      CLIENT_ID: ${{ secrets.CLIENT_ID }}
      PRIVATE_KEY: ${{ secrets.PRIVATE_KEY }}
```

### Step 4.6: Verify Issue Templates & Understand Approval Gates

In `TARGET_REPO` on GitHub, click **Issues** → **New Issue**. You should see the inherited forms:
- 🐛 **Bug report**
- 🚀 **Feature request**
- 🛠️ **Technical task**
- 💬 **General issue or discussion**
- 📝 **Blank issue** (if enabled in repo)

#### Which forms trigger Codex Auto-Fix?

The workflow checks for the required markdown heading `### Target branch` before triggering:

| Issue Template | Triggers Codex Auto-Fix? | Why? |
|---|:---:|---|
| 🐛 **Bug report** | **YES** | Contains mandatory `Target branch` field. Generates a branch and PR with bugfix. |
| 🚀 **Feature request** | **YES** | Contains mandatory `Target branch` field. Generates a branch and PR with new feature. |
| 🛠️ **Technical task** | **YES** | Contains mandatory `Target branch` field. Generates a branch and PR with refactoring/task work. |
| 💬 **General issue or discussion** | ❌ **NO** | Deliberately has **no `Target branch`**. Used for questions/planning; ignored by automation. |
| 📝 **Blank issue** | ❌ **NO** | Has no pre-set headings or `Target branch`. Ignored by automation. |

#### Issue Approval & Execution Rules

For the 3 implementation forms (Bug, Feature, Task), execution depends on author permissions:

1. **Maintainer / Admin Authors:**
   - If an issue is opened by a user with `admin` or `maintain` repository permissions, it is **automatically approved**.
   - The workflow adds the `codex-run-approved` label and starts the coding sandbox immediately.
2. **External Contributor Authors:**
   - If opened by an external contributor or non-maintainer, the workflow tags the issue with **`codex-run-requested`**.
   - **Codex does NOT run yet.** The workflow halts safely without touching code.
   - A maintainer must review the issue and manually apply the **`codex-run-approved`** label to authorize Codex execution.
3. **Safety on Edit (Invalidation):**
   - If an external contributor edits an approved issue, the workflow automatically revokes approval by removing `codex-run-approved` and re-applying `codex-run-requested`, preventing unauthorized prompt injection.

> [!NOTE]
> If inherited templates do not appear under **New Issue**, check whether `TARGET_REPO` contains a local `.github/ISSUE_TEMPLATE` directory. If any local issue template exists, GitHub suppresses all inherited templates. Either remove the local templates or copy the central ones locally.

### Step 4.7: Configure Branch Protection & Repository Rulesets

In `TARGET_REPO` → **Settings** → **Rules** → **Rulesets** (or **Branches**):
1. Protect your default branch (`main`).
2. Require a pull request before merging:
   - Require **at least 1 human approval**.
   - Dismiss stale pull request approvals when new commits are pushed.
3. Require status checks to pass before merging:
   - Select your authoritative repository CI workflow (build, test, lint).
4. **Do not exempt the GitHub App from required checks or human approval.**

---

## Phase 5: End-to-End Verification & Pilot Testing

Validate the entire pipeline using this sequential testing procedure.

```text
┌───────────────────────┐    ┌───────────────────────┐    ┌───────────────────────┐
│  Test 1: Maintainer   │───►│  Test 2: Contributor  │───►│ Test 3: Invalidation  │
│  Auto-Approval & PR   │    │  Approval Gate Check  │    │  On Contributor Edit  │
└───────────────────────┘    └───────────────────────┘    └───────────────────────┘
                                                                      │
┌───────────────────────┐    ┌───────────────────────┐                │
│  Test 5: Fork & Gate  │◄───│  Test 4: PR Review-   │◄───────────────┘
│  Safety Validation    │    │  Fix Autonomous Loop  │
└───────────────────────┘    └───────────────────────┘
```

### Test 1: Maintainer Implementation Issue
1. As a repo maintainer, open a new **Technical task** issue.
2. Under **Target branch**, enter `main` (or an active feature branch).
3. Specify a small, clear change (e.g. updating a documentation comment or adding a variable description in Terraform).
4. Submit the issue.
5. **Expected Results:**
   - The workflow starts immediately.
   - The issue automatically receives the `codex-run-approved` label.
   - The runner executes `setup.sh`, runs Codex, executes validation from `SKILL.md`.
   - The GitHub App creates branch `codex/issue-<ID>` and opens a pull request.
   - When validation passes, the issue is updated with a summary comment and
     labeled `codex-run-completed`; incomplete validation instead creates a draft
     PR and applies `codex-run-validation-blocked`.

### Test 2: Contributor Approval Gate
1. Have a non-collaborator or test account open an implementation issue.
2. **Expected Results:**
   - The issue receives `codex-run-requested`.
   - Codex **does not run**.
3. Now, as a maintainer, manually add the label `codex-run-approved`.
4. **Expected Results:**
   - The workflow re-triggers and proceeds with implementation and PR creation.

### Test 3: Edit Invalidation Check
1. On an approved contributor issue, edit the issue body as the contributor.
2. **Expected Results:**
   - The workflow detects the edit and automatically removes `codex-run-approved`, restoring `codex-run-requested`.

### Test 4: PR Review-Fix Loop
1. Open a pull request against `main` with a small syntax or style finding (e.g. missing required formatting or lint rule).
2. **Expected Results:**
   - Workflow `Codex Review-Fix Loop` triggers.
   - Reviewer agent spots the discrepancy.
   - Fixer agent resolves it, validates via `SKILL.md`, and commits:
     ```text
     Apply Codex auto-fix round 1 [codex-autofix]
     ```
   - The guard detects `[codex-autofix]` and halts recursive execution.
   - An evidence comment is posted on the PR detailing the findings and validation output.

### Test 5: Fork & Validation Negative Tests
1. **Fork PR Test:** Open a PR from a fork repository.
   - *Result:* The review-fix workflow skips immediately (`if` condition evaluates to false); secrets are never exposed.
2. **Validation Failure Test:** Introduce an unfixable syntax error in an issue request.
   - *Result:* Codex validation fails. The workflow does **not** create a PR and marks the issue with `codex-run-failed`.

---

## Phase 6: Maintenance, Rotation & Troubleshooting

### Credential Rotation Runbooks

#### Rotating GitHub App Private Key
1. Go to `NEW_ORG` → **Settings** → **Developer settings** → **GitHub Apps** → Select your App.
2. Scroll to **Private keys** and click **Generate a private key**.
3. Update the `PRIVATE_KEY` organization secret with the new `.pem` content.
4. Run a pilot test to confirm token minting works.
5. Delete the old private key from the GitHub App settings.

#### Rotating `CODEX_AUTH_JSON`
If Codex sessions expire or return `401 Unauthorized`:
1. On your trusted workstation, run:
   ```bash
   codex login
   ```
2. Re-upload the refreshed file:
   ```bash
   gh secret set CODEX_AUTH_JSON --org NEW_ORG --repos "TARGET_REPOS" < ~/.codex/auth.json
   ```

---

### Troubleshooting Matrix

| Symptom | Root Cause | Immediate Fix |
|---|---|---|
| **Reusable workflow not found (404)** | Central `.github` repo access not configured, or branch/SHA mismatch | Go to `NEW_ORG/.github` → Settings → Actions → General → Set Access to *Accessible from repositories in organization*. Check `uses:` ref. |
| **Issue forms do not appear** | Target repository has a local `.github/ISSUE_TEMPLATE` folder | Remove target repo's local templates or copy the central templates locally. |
| **Workflow starts but Codex never runs** | Missing `### Target branch` heading, invalid branch name, or pending approval | Check issue body for the exact markdown heading `### Target branch` with an existing branch. If contributor, add label `codex-run-approved`. |
| **Resource not accessible by integration** | GitHub App missing permissions or caller permissions too narrow | In GitHub App settings, verify `Contents: write` and `Pull requests: write`. In caller workflow, verify permissions block includes `contents: write`, `pull-requests: write`, `issues: write`. |
| **`actions/create-github-app-token` failed: App not found** | Using numeric `App ID` instead of `Client ID` in secret | Check `CLIENT_ID` secret. It must be the alphanumeric Client ID (e.g. `Iv23...`), not the numeric App ID. |
| **Codex output empty or 401 Unauthorized** | Expired or invalid `CODEX_AUTH_JSON` | Re-authenticate via `codex login` on workstation and update the secret. |
| **Setup failed: `setup.sh: Permission denied`** | `setup.sh` missing executable bit in Git | Run `chmod +x path/to/setup.sh` and `git add --chmod=+x path/to/setup.sh` then commit. |
| **Codex completed but no PR was created** | Protected path, secret scan, no-change, or publishing gate rejected the candidate | Check the Actions result comment. Failed or blocked validation alone should now create a draft PR. Codex remains forbidden from modifying `.github/workflows/*`, `.agents/*`, or `.env*`. |
| **Terraform provider handshake fails in Codex** | Provider processes cannot initialize inside the restricted Codex runtime | Do not execute provider-facing validation in Codex. Prepare it with `setup.sh` and run it through trusted `validate.sh` on the GitHub runner. |
| **Review-fix runs in an infinite loop** | Commit message guard bypassed or modified | Ensure commit message contains `[codex-autofix]`, which the caller step checks to prevent re-triggering. |
| **`The uses attribute cannot contain expressions`** | Attempted to use dynamic `${{ github.repository_owner }}` in caller `jobs.<id>.uses` | GitHub Actions strictly requires `jobs.<id>.uses` to be a literal static string. Replace with actual organization name (e.g. `NEW_ORG/.github/...`). |

---

## Security Invariants Checklist

Before approving the setup for production use, verify all 10 security invariants:

- [ ] **Supply-Chain Pinning:** Reusable workflow and `automation_ref` use a reviewed immutable commit SHA or controlled branch.
- [ ] **Explicit Secrets:** Callers pass only `CLIENT_ID`, `PRIVATE_KEY`, and `CODEX_AUTH_JSON`; `secrets: inherit` is never used.
- [ ] **Isolated Worktree:** Issue implementation runs in a disposable directory; GitHub tokens are not exposed to Codex.
- [ ] **Validation Gate:** Only `validation.status === 'passed'` creates a review-ready PR; failed or blocked validation can create only a clearly labelled draft PR. Shipped changes still require normal required checks and human review.
- [ ] **Protected Paths:** Codex cannot modify `.github/workflows/`, `.agents/`, `.codex/`, or `.env` files.
- [ ] **Secret Scanning:** All diffs pass Gitleaks scanning before the GitHub App publishes any branch or PR.
- [ ] **Fork Boundary:** Fork PRs are strictly excluded from receiving App tokens or Codex credentials.
- [ ] **Same-Repository Boundary:** Review-fix loop enforces `head.repo.full_name == github.repository`.
- [ ] **Human Review Mandatory:** Branch rules require at least one human approval; the automation bot cannot merge.
- [ ] **Zero Cloud Mutation:** Validation and agent prompts strictly forbid running deploy, apply, or state modification commands.
