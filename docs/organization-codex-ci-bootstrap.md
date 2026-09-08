# Bootstrap the Organization-Wide Codex CI Automation

This runbook explains how to reproduce the CI automation from
`IndiaCommunityAnimals/.github` in a different GitHub organization. It covers
only the CI control plane: organization files, reusable workflows, repository
callers, the publishing GitHub App, Codex authentication, validation contracts,
repository settings, rollout, and operations. It does not copy application,
AWS deployment, Terraform state, or production configuration.

For the behavior of every workflow stage, see
[Complete CI Automation Guide](ci-automation-guide.md). This document is the
installation and onboarding procedure.

> **Security boundary:** this automation can write source code and create or
> update pull requests. It never merges or deploys. Keep required CI checks and
> human review in branch protection or rulesets.

## 1. What you are installing

The installation has one central repository and one small integration in each
participating repository:

```text
NEW_ORG/.github
├── .github/ISSUE_TEMPLATE/                  # inherited issue forms
├── .github/workflows/
│   ├── reusable-codex-issue-fix.yml         # workflow_call only
│   └── reusable-codex-review-fix.yml        # workflow_call only
├── automation/codex-issue-fix/              # verifier, prompt, schema, controller
├── automation/codex-review-fix/             # prompts and review/fix loop
├── AGENTS.md                                 # organization agent policy
└── docs/                                     # maintainer documentation

NEW_ORG/each-target-repository
├── .github/workflows/codex-issue-fix.yml     # local issues event caller
├── .github/workflows/codex-review-fix.yml    # local pull_request event caller
├── .agents/skills/repository-validation/
│   ├── SKILL.md                              # exact repository checks (required)
│   └── scripts/                              # optional setup/validate/cleanup scripts
├── AGENTS.md                                 # repository-specific rules
└── .github/workflows/<normal-ci>.yml          # tests/builds remain repository-owned
```

GitHub events belong to the repository where the issue or PR exists. Therefore,
the central reusable workflows cannot replace the two local caller files.

### 1.1 Identity and credential separation

There are three distinct identities:

| Identity | Purpose | Where it exists |
|---|---|---|
| Caller `GITHUB_TOKEN` | Verify issues, create labels, and post verification/result comments | Automatically created for the caller job, limited by caller permissions |
| GitHub App installation token | Push branches/fixes and create PRs/comments as the automation bot | Minted only in publishing steps from `CLIENT_ID` and `PRIVATE_KEY` |
| Codex credential | Authenticate `codex exec` | Restored shortly before Codex runs and removed immediately afterward |

The GitHub App private key is never passed to Codex. The target checkout used by
issue implementation has no persisted GitHub credentials. The issue automation
runs Codex in a disposable exported worktree; only a secret-scanned patch is
later applied to the authenticated checkout.

## 2. Prerequisites and placeholders

Before starting, confirm:

- You are an owner of `NEW_ORG`, or can manage organization GitHub Apps,
  Actions policies, secrets, and repositories.
- GitHub Actions is enabled for the target repositories.
- The target repositories have Issues enabled if issue-to-PR automation will be
  used.
- You have a trusted workstation on which you can run `codex login` if you
  reproduce the current `CODEX_AUTH_JSON` path.
- Every target repository has an authoritative test/build workflow and a clear
  repository-specific validation contract.
- Branch rules require human review and required CI; the bot cannot merge.

Use these placeholders consistently:

| Placeholder | Meaning |
|---|---|
| `NEW_ORG` | Destination GitHub organization login |
| `CENTRAL_SHA` | Full 40-character commit SHA of reviewed central automation |
| `TARGET_REPO` | One repository being onboarded |
| `APP_NAME` | Human-readable GitHub App name |

## 3. Create the central `.github` repository

Create a repository literally named `.github` under `NEW_ORG`. For a normal
GitHub organization it must be public for organization-default community files
to apply. An enterprise managed-user organization uses an internal repository.
GitHub applies defaults only when a target repository has no local file of the
same type; for issue templates, any local `.github/ISSUE_TEMPLATE` content
overrides the entire inherited template set. See
[GitHub's default community health file rules](https://docs.github.com/en/enterprise-cloud@latest/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file).

Do not put secrets in this repository. A public central repository exposes
workflow, prompt, and policy source, but Actions secrets remain in GitHub's
secret store and are forwarded only by explicitly configured callers.

### 3.1 Copy the CI files

Copy these paths from the source `.github` repository while preserving their
relative paths and executable bits:

```text
.github/ISSUE_TEMPLATE/bug-template.yml
.github/ISSUE_TEMPLATE/config.yml
.github/ISSUE_TEMPLATE/feature-template.yml
.github/ISSUE_TEMPLATE/general-discussion-template.yml
.github/ISSUE_TEMPLATE/technical-task-template.yml
.github/workflows/reusable-codex-issue-fix.yml
.github/workflows/reusable-codex-review-fix.yml
automation/codex-issue-fix/agent-output.schema.json
automation/codex-issue-fix/prompts/base.md
automation/codex-issue-fix/run-agent.sh
automation/codex-issue-fix/verify-issue.js
automation/codex-review-fix/prompts/evidence-template.md
automation/codex-review-fix/prompts/review.md
automation/codex-review-fix/run-loop.sh
AGENTS.md
```

Copy the documentation if useful to destination maintainers. Normal application
CI files are not copied into the central repository.

### 3.2 Replace organization-specific values

Search the copied source before committing:

```bash
grep -RInE 'IndiaCommunityAnimals|animal-automation|community-animal' \
  --exclude-dir=.git .
```

At minimum, change both reusable workflows:

- `repository: IndiaCommunityAnimals/.github` to
  `repository: NEW_ORG/.github`;
- both `automation_ref` descriptions;
- the issue publisher's `animal-automation-bot[bot]` Git author and email to a
  neutral destination value such as `NEW_ORG-automation[bot]` (the commit's
  authenticated actor will still be the GitHub App);
- organization names and policy links in `AGENTS.md`, `README.md`, and docs.

Do not replace GitHub expression syntax such as `${{ github.repository }}`.
Do not change prompt, gate, protected-path, or permission logic merely to make
the initial port easier.

### 3.3 Preserve reusable-workflow rules

The central files must keep `on: workflow_call`; do not add organization-wide
`issues` or `pull_request` triggers to them. Each target repository owns
those events through its caller.

Keep actions and downloaded tools pinned. Review versions and checksums during
the port instead of replacing them with mutable `@main` references.

### 3.4 Central repository Actions access

If the central workflow repository is private in a setup that does not rely on
inherited issue forms, go to:

`NEW_ORG/.github` → **Settings** → **Actions** → **General** → **Access**

and select **Accessible from repositories in the `NEW_ORG` organization**.
GitHub documents this at
[Sharing actions and workflows with your organization](https://docs.github.com/en/actions/how-tos/reuse-automations/share-with-your-organization).

For the normal public special `.github` repository, ensure organization and
target-repository Actions policies allow:

- `NEW_ORG/.github/.github/workflows/*`;
- `actions/checkout`;
- `actions/github-script`; and
- `actions/create-github-app-token`.

If the organization allowlists actions, allow the exact tags or SHAs referenced
by the copied workflow. See
[organization Actions policy settings](https://docs.github.com/en/organizations/managing-organization-settings/disabling-or-limiting-github-actions-for-your-organization).

### 3.5 Review and record an immutable ref

Open a human-reviewed PR in `NEW_ORG/.github`. After merge, record:

```bash
git rev-parse HEAD
```

Use that full `CENTRAL_SHA` in every caller's `uses:` value and
`automation_ref` input. The values must match because `automation_ref`
controls which scripts and prompts the reusable workflow checks out. A full SHA
is the strongest immutable pin.

## 4. Create the publishing GitHub App

The App gives automated pushes and PR creation a short-lived, non-human
identity. App-authored events can start normal PR CI without the special
approval behavior associated with PRs created using only `GITHUB_TOKEN`.
See [Triggering a workflow](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow).

### 4.1 Register the App under the organization

As an organization owner:

1. Open GitHub → **Your organizations** → `NEW_ORG` → **Settings**.
2. Open **Developer settings** → **GitHub Apps** → **New GitHub App**.
3. Use settings equivalent to this table.

| Field | Value |
|---|---|
| GitHub App name | Globally unique, for example `NEW_ORG Codex Automation` |
| Description | Publishes Codex issue fixes and review fixes for `NEW_ORG` |
| Homepage URL | `https://github.com/NEW_ORG/.github` |
| Callback URL | Blank |
| Request user authorization during installation | Off |
| Enable Device Flow | Off |
| Setup URL | Blank |
| Webhook Active | Off; Actions events drive this automation |
| Where can this GitHub App be installed? | **Only on this account** |

No OAuth callback, user authorization, device flow, or webhook endpoint is
required. GitHub permits webhook delivery to be disabled for an App used only
for authentication. See
[Registering a GitHub App](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).

### 4.2 Grant minimum repository permissions

Configure these **Repository permissions**:

| Permission | Access | Why |
|---|---|---|
| Contents | Read and write | Check out with the App token and push issue/review fix commits |
| Pull requests | Read and write | Create PRs and create/update review evidence comments |
| Metadata | Read-only | Automatically included by GitHub |

Set every other repository and organization permission to **No access** unless
you deliberately extend and review the automation. In particular:

- Do not grant Administration, Secrets, Actions, Deployments, Environments, or
  organization-wide write access.
- Do not grant `Workflows: write` for the baseline. GitHub requires it to edit
  `.github/workflows`; not granting it prevents the App from publishing such
  changes. If your design intentionally permits that, treat it as a separate
  privilege expansion and update guards and docs.
- The issue caller's labels and issue comments use its scoped `GITHUB_TOKEN`.
  The baseline App does not need a separate Issues permission.

GitHub recommends minimum App permissions and documents HTTP Git access at
[Choosing permissions for a GitHub App](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app).

Subscribe to no webhook events. Select **Only on this account**, then create the
App.

### 4.3 Record Client ID

On the App settings page, copy **Client ID**, not **App ID**. The workflows call
`actions/create-github-app-token@v3` using `client-id`. GitHub's example
distinguishes these at
[Authenticating with a GitHub App in Actions](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/making-authenticated-api-requests-with-a-github-app-in-a-github-actions-workflow).

Although GitHub's generic example uses an Actions variable for Client ID, this
automation declares `CLIENT_ID` as a secret. Keep that exact secret name unless
you change both reusable workflows and every caller.

### 4.4 Generate and protect the private key

On the App settings page:

1. Scroll to **Private keys**.
2. Click **Generate a private key**.
3. Save the PEM in a trusted password manager or vault.
4. Store the complete PEM, including `BEGIN` and `END` lines, as
   `PRIVATE_KEY`.
5. Delete any unprotected local copy after secret storage is verified.

GitHub stores only the public half; the key cannot be downloaded again.
Generate a replacement before deleting the old key during rotation. See
[Managing private keys for GitHub Apps](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/managing-private-keys-for-github-apps).

### 4.5 Install the App

Choose **Install App** → `NEW_ORG` → **Install**. Start with **Only select
repositories** and select only pilot repositories. GitHub documents the steps
at [Installing your own GitHub App](https://docs.github.com/en/apps/using-github-apps/installing-your-own-github-app).

For every later repository, update both independent lists:

1. repositories accessible to the App installation; and
2. repositories allowed to read each organization Actions secret.

## 5. Configure Actions secrets

The unchanged workflows require exactly:

| Secret | Exact content | Rotation owner |
|---|---|---|
| `CLIENT_ID` | GitHub App Client ID, not App ID | GitHub App administrator |
| `PRIVATE_KEY` | Complete PEM private key | GitHub App administrator |
| `CODEX_AUTH_JSON` | Raw `~/.codex/auth.json`, not base64 | Trusted Codex account owner |

Prefer organization Actions secrets with **Selected repositories** access.
GitHub supports selected-repository policies; see
[GitHub Actions secrets](https://docs.github.com/en/enterprise-cloud@latest/actions/concepts/security/secrets).

In the UI:

1. Open `NEW_ORG` → **Settings**.
2. Open **Secrets and variables** → **Actions**.
3. Select **New organization secret**.
4. Create each exact name above.
5. Choose **Selected repositories** and only onboarded repositories.

Repository secrets may be used for a pilot, but centralized secrets are easier
to rotate consistently.

### 5.1 CLI examples

With authenticated GitHub CLI and comma-separated repository names:

```bash
export ORG=NEW_ORG
export REPOS=repo-one,repo-two

gh secret set CLIENT_ID --org "$ORG" --repos "$REPOS" \
  --body "$CLIENT_ID_VALUE"

gh secret set PRIVATE_KEY --org "$ORG" --repos "$REPOS" \
  < /trusted/path/app-private-key.pem
```

Do not put values in shell history, repository `.env` files, issue/PR bodies,
logs, or workflow YAML.

## 6. Configure Codex authentication

### 6.1 Reproduce the current implementation

The copied workflows write raw `CODEX_AUTH_JSON` to
`~/.codex/auth.json` with mode `0600`, restore it only after setup, and remove
it after Codex. They do not accept an OpenAI API key without code changes.

On a trusted workstation:

1. Install the same Codex CLI version family used by the workflows.
2. Configure file-backed credential storage:

   ```toml
   # ~/.codex/config.toml
   cli_auth_credentials_store = "file"
   ```

3. Authenticate:

   ```bash
   codex login
   ```

4. Verify without printing tokens:

   ```bash
   AUTH_FILE="${CODEX_HOME:-$HOME/.codex}/auth.json"
   jq '{
     auth_mode,
     has_tokens: (.tokens != null),
     has_refresh_token: ((.tokens.refresh_token // "") != ""),
     last_refresh
   }' "$AUTH_FILE"
   ```

   Continue only if `auth_mode` is `chatgpt` and
   `has_refresh_token` is true.

5. Upload raw JSON:

   ```bash
   gh secret set CODEX_AUTH_JSON --org NEW_ORG \
     --repos repo-one,repo-two < "$AUTH_FILE"
   ```

The secret is JSON, not base64. Never print or commit it.

### 6.2 Current limitation and recommended direction

Official OpenAI documentation recommends API-key authentication for most
automation and the Codex GitHub Action for GitHub Actions. ChatGPT-managed
`auth.json` is advanced, for trusted private automation, and must not be used
for public/open-source repository automation. See
[Codex non-interactive authentication](https://learn.chatgpt.com/docs/non-interactive-mode#authenticate-in-automation)
and [CI/CD account-auth maintenance](https://learn.chatgpt.com/docs/auth/ci-cd-auth).

The current workflows run on ephemeral GitHub-hosted runners. Codex may refresh
`auth.json`, but the workflows delete that file and do not write it back to
the organization secret. Therefore:

- monitor for empty Codex output, `401`, or refresh failures;
- rerun `codex login` and replace `CODEX_AUTH_JSON` when needed;
- do not share one refreshable session across concurrent independent systems;
- for a durable new installation, plan a reviewed migration to the Codex GitHub
  Action/API-key auth, workload identity federation, or a trusted
  persistent/secure round-trip auth store.

Do not put an API key into `CODEX_AUTH_JSON`; it does not match the current
workflow contract.

## 7. Onboard each target repository

Repeat this section per repository.

### 7.1 Add agent policy

Add a repository `AGENTS.md` that points to
`NEW_ORG/.github/AGENTS.md` and defines only repository-specific architecture,
safety, coding, and validation rules. Do not put framework- or
infrastructure-specific rules in organization policy unless they apply
everywhere.

### 7.2 Add the required validation skill

Create:

```text
.agents/skills/repository-validation/SKILL.md
```

It must define the repository's exact validation contract: locked dependency
setup, formatting, linting, type checking, tests, build, audit, and safe
infrastructure validation as appropriate. Commands must use a documented
working directory and must not deploy or mutate remote services. When a
provider-facing check cannot run safely in Codex's restricted sandbox, put it
behind the trusted `validate.sh` interface described below instead of asking
Codex to execute it directly.

Optional issue-automation scripts:

```text
.agents/skills/repository-validation/scripts/setup.sh
.agents/skills/repository-validation/scripts/validate.sh
.agents/skills/repository-validation/scripts/cleanup.sh
```

Rules:

- `setup.sh` runs in the disposable issue worktree before Codex credentials.
  It may install pinned dependencies/tools or prepare an isolated service. It
  must not modify tracked or non-ignored files.
- `validate.sh` is loaded from the reviewed base commit and runs after Codex on
  the trusted GitHub runner. It must support `command` and
  `run <repository-root>`; exit `0` means passed, `1` means failed, and `2`
  means the trusted environment is blocked.
- `cleanup.sh` removes only the isolated validation environment and is
  attempted after failures.
- Commit executable bits:

  ```bash
  chmod +x .agents/skills/repository-validation/scripts/*.sh
  git add --chmod=+x .agents/skills/repository-validation/scripts/*.sh
  ```

- Never include cloud credentials, production tokens, deployment, state, or
  destructive database commands.

The issue controller stops before Codex if the skill is missing. When
`validate.sh` exists, Codex returns the skill's pending placeholder and the
controller replaces it with the actual trusted-runner result. An
implementation failure is sent through one bounded repair turn and validated
once more. Review-fix uses the same trusted setup and validator. Normal CI is
the authoritative independent gate.

### 7.3 Add the issue-to-PR caller

Create `.github/workflows/codex-issue-fix.yml` on the default branch:

```yaml
name: Codex Issue Fix

on:
  issues:
    types: [opened, edited, reopened, labeled, unlabeled]

permissions:
  contents: write
  issues: write
  pull-requests: write

jobs:
  issue-fix:
    if: >-
      contains(github.event.issue.body, '### Target branch') &&
      ((github.event.action != 'labeled' && github.event.action != 'unlabeled') ||
       github.event.label.name == 'codex-run-approved')
    uses: NEW_ORG/.github/.github/workflows/reusable-codex-issue-fix.yml@CENTRAL_SHA
    with:
      automation_ref: CENTRAL_SHA
      approval_label: codex-run-approved
      request_label: codex-run-requested
      enable_aws_mcp: false
      enable_terraform_mcp: false
    secrets:
      CODEX_AUTH_JSON: ${{ secrets.CODEX_AUTH_JSON }}
      CLIENT_ID: ${{ secrets.CLIENT_ID }}
      PRIVATE_KEY: ${{ secrets.PRIVATE_KEY }}
```

Replace both `CENTRAL_SHA` values with the same full SHA. Do not use
`secrets: inherit`.

Enable only the MCP servers the target repository needs. For an AWS/Terraform
infrastructure repository, set both inputs to `true`; leave them `false` for
repositories that do not need those tools.

The workflow creates its labels. A maintainer-authored implementation issue is
auto-approved. A contributor issue gets `codex-run-requested`; a current
maintainer must add `codex-run-approved`. Editing it invalidates old approval.

### 7.4 Add the review-fix caller

Create `.github/workflows/codex-review-fix.yml`:

```yaml
name: Codex Review-Fix Loop (EXPERIMENTAL)

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  loop:
    if: github.event.pull_request.head.repo.full_name == github.repository
    permissions:
      contents: write
      pull-requests: write
    uses: NEW_ORG/.github/.github/workflows/reusable-codex-review-fix.yml@CENTRAL_SHA
    with:
      automation_ref: CENTRAL_SHA
      profile: ""
    secrets:
      CODEX_AUTH_JSON: ${{ secrets.CODEX_AUTH_JSON }}
      CLIENT_ID: ${{ secrets.CLIENT_ID }}
      PRIVATE_KEY: ${{ secrets.PRIVATE_KEY }}
```

The same-repository condition is mandatory. Fork PR code must not receive Codex
or App credentials. Do not switch to `pull_request_target` without a separate
threat model and redesign.

`profile` is optional caller metadata and does not select commands or paths.
Keep optional round/deletion inputs at defaults until a pilot proves a change is
needed.

### 7.5 Keep normal CI separate

Do not move normal test/build/deployment logic into Codex callers. Existing CI
continues to run on `pull_request` and remains required. App publication makes
the created PR and bot pushes produce normal events. The review workflow's
commit-message guard prevents its own `synchronize` event from starting another
review loop; it does not suppress test/build workflows.

### 7.6 Check inherited issue forms

Open `TARGET_REPO` → **Issues** → **New issue**. Confirm:

- Bug report;
- Feature request;
- Technical task; and
- General issue or discussion.

If absent, inspect `TARGET_REPO/.github/ISSUE_TEMPLATE`. Any local template or
`config.yml` makes GitHub ignore the inherited set. Remove the local set or
copy/adapt all central forms locally.

Implementation forms must preserve exact title prefixes and rendered headings
checked by `verify-issue.js`, especially **Target branch** and the exact Safety
check sentence. Discussion intentionally has no Target branch.

## 8. Configure target-repository settings

### 8.1 Actions policy

In **Settings** → **Actions** → **General**:

- enable Actions;
- allow pinned GitHub actions and `NEW_ORG/.github` workflows;
- keep default permissions minimal—the callers explicitly declare theirs;
- never expose Actions secrets to fork PR workflows.

A reusable workflow cannot elevate its caller's `GITHUB_TOKEN`; nested
permissions can only stay the same or become more restrictive. See
[reusable workflow access and permissions](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations).

**Allow GitHub Actions to create and approve pull requests** is not required
here because PR publication uses the separate App token. Do not enable automated
approval unless another reviewed workflow needs it.

### 8.2 Rulesets and branch protection

Configure rules so:

- `codex/issue-*` branches may be created/updated by the App;
- the App can fast-forward fix commits to same-repository PR branches;
- required test/build/security checks run and must pass;
- at least one human approval is required;
- approvals are dismissed or re-review required after bot pushes as appropriate;
- the App cannot bypass merge review or protected-environment deployment.

Do not exempt the App from all rules. If a push is rejected, add only the
narrowest reviewed bypass.

### 8.3 Secret and App access

Confirm all four independently:

1. App installation includes `TARGET_REPO`.
2. `CLIENT_ID` secret access includes it.
3. `PRIVATE_KEY` secret access includes it.
4. `CODEX_AUTH_JSON` secret access includes it.

Adding a repository to the App does not grant secrets and vice versa.

## 9. Validate before rollout

### 9.1 Central static checks

From destination `.github`:

```bash
bash -n automation/codex-issue-fix/run-agent.sh
bash -n automation/codex-review-fix/run-loop.sh
node --check automation/codex-issue-fix/verify-issue.js
ruby -e 'require "yaml"; Dir[".github/**/*.yml"].each { |f| YAML.load_file(f) }; puts "YAML parsed"'
git diff --check
grep -RIn 'IndiaCommunityAnimals' --exclude-dir=.git .
```

The final grep should be empty unless a migration note deliberately names the
source organization.

Manually review:

- exact central repository owner/path;
- matching full `CENTRAL_SHA` values;
- explicit secret forwarding;
- caller/reusable permissions;
- same-repository PR restriction;
- protected paths and secret scan;
- pinned actions/tools and checksum;
- absence of merge/deployment commands.

### 9.2 Target repository checks

For each target:

```bash
bash -n .agents/skills/repository-validation/scripts/setup.sh   # if present
bash -n .agents/skills/repository-validation/scripts/cleanup.sh # if present
git diff --check
```

Parse both caller YAML files and run all normal repository checks documented by
its `AGENTS.md` and validation skill.

### 9.3 Live pilot

Use a low-risk private pilot repository.

1. **Inherited forms:** all four appear.
2. **Maintainer issue:** open a small Technical task against an existing test
   branch. Confirm approval, disposable implementation, validation, secret
   scan, App-authored `codex/issue-N` branch, PR, and result comment.
3. **Contributor approval:** confirm `codex-run-requested` and no Codex run
   until a maintainer adds `codex-run-approved`.
4. **Edit invalidation:** edit after approval and confirm approval is removed.
5. **Review-fix:** open a safe same-repository PR; confirm review, negotiation,
   validation, App push, and updated comment.
6. **Recursion:** confirm `[codex-autofix]` does not start another review loop
   while normal CI still runs.
7. **Fork boundary:** confirm fork PR review-fix is skipped and gets no secrets.
8. **Human gate:** confirm no merge/deployment without normal policy.

Inspect every step and actor, not only the final comment.

## 10. Roll out to more repositories

For each repository:

1. Add repository `AGENTS.md` and validation skill.
2. Add callers pinned to reviewed `CENTRAL_SHA`.
3. Add the repository to the App installation.
4. Add it to all three secret access lists.
5. Verify Actions policies and rulesets.
6. Confirm inherited/local issue forms.
7. Run a low-risk issue and PR pilot.
8. Require normal CI and human review.

Do not grant App or secret access to every repository by default.

## 11. Update central automation safely

Treat each central change as a supply-chain change:

1. Open a PR in `NEW_ORG/.github`.
2. Review scripts, prompts, permissions, pins, downloads, and checksums.
3. Run static checks and pilot.
4. Merge and record the new full SHA.
5. Update every caller's `uses:` and `automation_ref` together.
6. Roll out to one pilot before bulk updates.

Never update only one ref. Avoid mutable `@main` during normal operation.

## 12. Rotation and incident response

### 12.1 GitHub App key rotation

1. Generate a second key.
2. Update `PRIVATE_KEY`.
3. Pilot token minting and a harmless publish.
4. Delete the old key.

If compromised, remove repository access or suspend the installation, rotate,
review App-authored activity, and restore only after investigation.

### 12.2 Codex credential rotation

Rerun `codex login` and replace `CODEX_AUTH_JSON`. If no review output is
produced, inspect the Codex log tail; never interpret an empty response as clean.

### 12.3 Secret exposure

If a secret appears in source, issue/PR content, logs, or an artifact:

1. revoke/rotate immediately;
2. disable the workflow/App installation if necessary;
3. remove content/history per incident procedure;
4. inspect audit/workflow logs;
5. restore only after scope and new credentials are verified.

## 13. Troubleshooting

| Symptom | Likely cause | Check |
|---|---|---|
| Reusable workflow inaccessible | Wrong owner/path/ref or Actions access | Verify `NEW_ORG/.github/.github/workflows/...@CENTRAL_SHA` and policies |
| Forms absent | Central visibility/default branch wrong or local templates override | Check special `.github` rules and target `.github/ISSUE_TEMPLATE` |
| Issue runs but Codex skips | Invalid form, no approval, missing branch, or existing issue PR | Read marked verification comment |
| `Resource not accessible by integration` | Caller token or App permission too narrow | Match failing step to caller/App permissions |
| App-token Not Found | App not installed, wrong Client ID, or repo omitted | Check installation and Client ID (not App ID) |
| App key/signature error | Incomplete PEM, mismatched ID/key, or deleted key | Replace with complete matching PEM |
| Secret empty | Repo not selected, name mismatch, or caller did not forward | Check all access lists and exact names |
| Codex empty/`401` | `CODEX_AUTH_JSON` stale/invalid or CLI failed | Rerun login, replace secret, inspect log |
| Setup stops issue job | Skill absent, script not executable/failed, or changed files | Fix validation skill and modes |
| Provider validation fails inside Codex | Provider process cannot run in the restricted sandbox | Prepare the runtime in `setup.sh` and execute the protected check through `validate.sh` on the trusted runner |
| Candidate rejected | Protected path, schema, or Gitleaks gate | Inspect implementation logs; do not bypass |
| PR created but CI absent | Wrong actor/token, policy, filters, or caller missing on default branch | Confirm App token and normal `pull_request` CI |
| Review job skipped | Fork PR or bot `[codex-autofix]` event | Expected; inspect condition/guard |
| Review push rejected | Branch moved/rules block App/workflow-file permission required | Re-run current head or narrowly change rule |
| Gate A reverts fix | Finding did not cite each changed file as `file:line` | Improve finding, not gate |
| Several runs appear | App PR/push triggers normal CI and queued review | Confirm concurrency/guard; keep unrelated CI |

## 14. Security invariants

Installation is complete only if:

- central controls come from a reviewed immutable SHA;
- `uses:` and `automation_ref` match;
- callers forward only three named secrets, never `secrets: inherit`;
- fork PRs cannot access credentials;
- App repository access and permissions are minimum;
- Codex never receives App token/private key;
- issue implementation uses a disposable worktree;
- protected-path and Gitleaks gates run before publication;
- every target owns a validation skill, any required trusted validator, and normal CI;
- App cannot merge, deploy, or bypass human review;
- credentials and access lists are audited/rotated.

## 15. Source map

| Concern | Authoritative file |
|---|---|
| Issue form contract | `.github/ISSUE_TEMPLATE/*.yml` |
| Title/headings/branch verification | `automation/codex-issue-fix/verify-issue.js` |
| Issue implementation/gates | `automation/codex-issue-fix/run-agent.sh` |
| Issue result schema | `automation/codex-issue-fix/agent-output.schema.json` |
| Issue orchestration/publishing | `.github/workflows/reusable-codex-issue-fix.yml` |
| Review criteria | `automation/codex-review-fix/prompts/review.md` |
| Review/fix negotiation/gates | `automation/codex-review-fix/run-loop.sh` |
| Review orchestration/publishing | `.github/workflows/reusable-codex-review-fix.yml` |
| Repository checks | Target `.agents/skills/repository-validation/SKILL.md` |
| Repository events/permissions | Target `.github/workflows/codex-*.yml` |

When code and docs disagree, stop rollout, inspect reviewed source, and update
both in the same PR.
