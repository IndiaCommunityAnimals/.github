# Complete CI Automation Guide

This document explains the current IndiaCommunityAnimals Codex automation from
issue creation or pull-request creation through validation, publishing, and
human review. It documents both pipelines:

1. **Issue-to-PR automation** validates a structured issue, asks Codex to make
   an implementation in a disposable worktree, scans and validates the result,
   then opens a normal pull request.
2. **Review-fix automation** reviews an existing pull request, negotiates
   findings with a fixer, validates agreed edits, and pushes fixes to the same
   PR branch.

Neither pipeline merges PRs, approves PRs, deploys infrastructure, runs
Terraform apply/destroy, migrates production data, or replaces human review.

To reproduce this system in a different GitHub organization, follow the
[organization-wide bootstrap runbook](organization-codex-ci-bootstrap.md) for
GitHub App registration, credentials, central files, callers, and rollout.

## 1. Repository layout and ownership

The organization `.github` repository owns shared policy and reusable logic:

```text
.github/.github/ISSUE_TEMPLATE/              inherited issue forms
.github/.github/workflows/                   reusable workflows
.github/automation/codex-issue-fix/          issue controller and verifier
.github/automation/codex-review-fix/         review controller
.github/automation/*/prompts/                trusted prompts and templates
.github/docs/                                operational documentation
```

Each application repository owns a thin caller workflow. The event must be
declared in the repository where the issue or pull request exists; the central
repository cannot receive that repository-local event by itself. Callers pass
the central automation ref, repository-owned validation configuration,
permissions, and explicit secrets. Central workflows own verification, Codex
execution, gates, delivery, and comments.

The two reusable entry points are:

```text
.github/workflows/reusable-codex-issue-fix.yml
.github/workflows/reusable-codex-review-fix.yml
```

Callers should reference them with a reviewed release tag or immutable commit
SHA. The available sandbox callers are pinned to the reviewed organization
commit used for this rollout.

## 2. Issue forms: why each field exists

Issue forms generate a normal GitHub issue. They do not execute automation by
themselves. The later verifier reads the generated title and Markdown headings.
Blank issues are disabled because arbitrary prose cannot safely identify a base
branch or provide enough evidence for an implementation.

### 2.1 Issue chooser configuration

`.github/ISSUE_TEMPLATE/config.yml` contains:

```yaml
blank_issues_enabled: false
contact_links: []
```

`blank_issues_enabled: false` forces users through one of the known contracts.
`contact_links: []` means there is no alternate external support link in the
chooser. These settings reduce underspecified automation requests.

### 2.2 Common title prefixes

| Form | Prefix | Purpose |
|---|---|---|
| Bug report | `[Bug]: ` | Identifies an existing defect. |
| Feature request | `[Feature]: ` | Identifies a new capability. |
| Technical task | `[Task]: ` | Identifies maintenance, CI, testing, docs, or infrastructure work. |
| General discussion | `[Discussion]: ` | Deliberately does not request a code change. |

The verifier accepts only the first three implementation prefixes. The prefix
selects the required-heading contract and is also removed when generating the
PR title.

### 2.3 Bug report fields

`name: Bug report` and `description` are the visible chooser text. They explain
that the report should be reproducible and can result in a PR.

`title: "[Bug]: "` gives every bug a machine-detectable type prefix.

The introductory markdown warns the author that the form starts automation and
that secrets, tokens, personal data, and production credentials must not be
pasted into the issue. It is guidance, not a substitute for secret scanning.

`target_branch` is a required input. It names the existing branch to use as
the implementation baseline and PR base, normally `main`. The verifier checks
that the branch exists through the GitHub API and rejects unsafe values such as
`..`, `@{`, `//`, leading/trailing `/`, trailing `.`, and `.lock` names.

`summary` (`Problem summary`) is required. It gives a concise statement of the
defect and its impact.

`current_behavior` is required. It describes what happens now, including an
error or incorrect result. This keeps Codex from treating a desired feature as
a bug fix.

`expected_behavior` is required. It defines the observable result after repair
and prevents speculative interpretations of “fix.”

`reproduction` (`Steps to reproduce`) is required. Deterministic steps, inputs,
URLs, and API calls are the strongest evidence that the defect can be checked.

`evidence` (`Supporting evidence`) is optional. Sanitized logs, screenshots,
failing tests, and request/response examples are useful but are not available
for every defect.

`acceptance` is required. It lists observable outcomes that prove the bug is
fixed and compatible behavior remains intact.

`validation` is required. It states the checks and evidence the generated PR
must provide. Repository-specific commands come from the repository validation
skill; this field captures issue-specific proof.

`risks` (`Constraints and out of scope`) is optional. It tells Codex what must
not change and prevents unrelated cleanup, migrations, or refactors.

`safety` is a required checkbox confirming that secrets, credentials, tokens,
and sensitive personal data were removed. The verifier checks the checked
Markdown line, not just the existence of the field.

### 2.4 Feature request fields

`name`, `description`, and `title: "[Feature]: "` identify the chooser option,
explain the expected outcome, and supply the accepted type prefix.

`target_branch` has the same branch existence and safety purpose as the Bug
form.

`problem` (`Problem and context`) explains the need, affected users, and value.
It prevents implementation from being driven only by a proposed solution.

`desired_behavior` describes what users or systems must be able to do after
implementation.

`acceptance` defines testable outcomes. A feature is not complete merely
because a source file changed.

`out_of_scope` records deliberately excluded work and limits scope creep.

`evidence` (`Validation and evidence`) specifies commands or proof required
before completion.

`risks` records security, compatibility, data, migration, rollout, and
implementation constraints.

`safety` confirms removal of sensitive information.

### 2.5 Technical task fields

`name`, `description`, and `title: "[Task]: "` identify maintenance work and
select the Task verifier contract.

`target_branch` selects the existing implementation baseline.

`context` explains the current state and why the work is needed.

`task` (`Required change`) states exactly what must change without inviting
unrelated cleanup.

`acceptance` lists observable outcomes.

`validation` lists commands or proof required before completion.

`risk` (`Constraints and out of scope`) defines boundaries.

`dependencies` identifies blocked work, related issues, external systems, or
required sequencing.

`safety` confirms removal of sensitive data.

### 2.6 General discussion fields

The General Discussion form has no `target_branch`. It asks for a topic,
context, related area, desired outcome, and safety confirmation. Its
`labels: []` explicitly requests no labels. Because it lacks the target-branch
heading and uses `[Discussion]:`, the issue caller ignores it. Use it for
questions, investigation, planning, and decisions that should not modify code.

## 3. Labels, identity, permissions, and secrets

Labels are the visible request and authorization state:

1. A contributor's implementation issue receives `codex-run-requested`.
2. A maintainer-authored implementation issue receives `codex-run-approved`.
3. The coding agent runs only when `codex-run-approved` is present.
4. A maintainer can review a contributor issue and add `codex-run-approved`.
5. Verification checks the approval label's event actor has repository
   `maintain` or `admin` permission, preventing contributor self-approval.

The reusable workflow creates both labels if they do not already exist.

The caller grants:

```yaml
permissions:
  contents: write
  issues: write
  pull-requests: write
```

`contents: write` permits branches and commits. `issues: write` permits
verification/result comments and label provisioning. `pull-requests: write`
permits PR creation and review evidence comments. A reusable workflow cannot
elevate permissions that its caller did not grant.

Callers forward only these secrets:

| Secret | Used for | Exposure boundary |
|---|---|---|
| `CODEX_AUTH_JSON` | Codex CLI authentication | Written late, removed after the agent step. |
| `CLIENT_ID` | GitHub App client ID | Used only to mint an installation token. |
| `PRIVATE_KEY` | GitHub App signing key | Passed to token creation, never to Codex. |

The callers do not use `secrets: inherit`. The GitHub App must be installed on
the target repository with the minimum required repository permissions,
including Contents write and Pull requests write; issue comments/labels also
need Issues write.

The Actions runner is the execution environment. The GitHub App token is the
publishing identity. The default `GITHUB_TOKEN` should not be substituted when
App-authored pushes, comments, or PRs are required.

## 4. Issue-to-PR caller flow

The checked-in organization workflow is a reusable `workflow_call` workflow. It
does not declare an `issues` event itself. A repository-local caller must
provide the issue event and call this workflow; caller workflow files are not
present in this repository, so their exact event filters, `uses` references,
and conditions cannot be documented as verified code here.

The reusable workflow accepts:

| Input/secret | Required | Default or value | Code use |
|---|---:|---|---|
| `automation_ref` | No | `main` | Ref used to check out this organization repository. |
| `approval_label` | No | `codex-run-approved` | Maintainer-only label required to run Codex. |
| `request_label` | No | `codex-run-requested` | Label automatically added while approval is pending. |
| `enable_aws_mcp` | No | `false` | Enables the required AWS Knowledge MCP server. |
| `enable_terraform_mcp` | No | `false` | Enables the required, registry-only Terraform MCP container. |
| `CODEX_AUTH_JSON` | Yes | — | Codex authentication secret. |
| `CLIENT_ID` | Yes | — | GitHub App client ID. |
| `PRIVATE_KEY` | Yes | — | GitHub App private key. |

The issue workflow itself declares:

- `contents: write`, `issues: write`, and `pull-requests: write` permissions;
- concurrency group `codex-issue-fix-${{ github.repository }}-${{ github.event.issue.number }}`;
- `cancel-in-progress: true`;
- runner `ubuntu-24.04`; and
- a 75-minute job timeout, allowing one bounded validation-repair turn.

The caller normally needs to invoke the workflow for issue events such as:

```yaml
on:
  issues:
    types: [opened, edited, reopened, labeled, unlabeled]
```

That event block is an integration requirement described by the workflow's
expected payload and is not present in the checked-in organization workflow.

`opened` handles a new form. `edited` allows a rejected issue to be corrected.
`reopened` allows an intentionally resumed issue. `labeled` lets a maintainer's
approval unlock a contributor issue. The job condition requires a Target branch
heading and, for label events, specifically requires `codex-run-approved`.

The caller passes `automation_ref`, the label names, any repository-appropriate
MCP opt-ins, and the three secrets to `reusable-codex-issue-fix.yml`. It does
not contain implementation logic; this keeps all repositories on the same
centrally reviewed behavior.

## 5. Issue workflow: every execution step

### 5.1 Check out trusted organization automation

The reusable workflow checks out the central repository into
`organization-automation`. It reads prompts, the verifier, output schema, and
controller from this trusted checkout rather than from the issue-selected
branch. An issue author therefore cannot edit the instructions that evaluate
their own issue.

### 5.2 Ensure the approval label exists

`actions/github-script` calls `issues.getLabel`. Missing request and approval
labels are created with colors and descriptions. A concurrent 422 “already
exists” response is treated as harmless. The issue author's current repository
permission determines whether the workflow attaches request or approval.

### 5.3 Verify the issue

`verify-issue.js` is deterministic and performs these checks:

1. Title length is at least ten characters.
2. Body length is at least eighty characters.
3. Title matches `[Bug]:`, `[Feature]:`, or `[Task]:`.
4. Every required heading for that type exists and is non-empty.
5. The safety checkbox is checked exactly.
6. The target branch is safely formatted.
7. The target branch exists through `repos.getBranch`.
8. The issue has `codex-run-approved`, and that approval was added by a
   maintainer unless the issue author is currently a maintainer.
9. There is no existing automation PR for `codex/issue-N`.

The step emits `eligible`, `target_branch`, `problems_json`, and a verification
result. If `eligible` is false, checkout and Codex steps are skipped.

### 5.4 Verification comment

An ineligible issue receives one bot comment identified by a hidden marker. On a
later edit, that comment is updated instead of creating a comment for every
failed attempt. It lists missing headings, invalid branches, missing approval,
or duplicate-PR problems.

### 5.5 Stage trusted prompt and controller

The common prompt, output schema, controller, and repository validation
instructions are copied into runner scratch storage. The issue body is stored
separately and passed as untrusted data. This separates organization
instructions from user-provided text.

### 5.6 Check out the target branch

The verified target repository branch is checked out into `target-repository`
with persisted credentials disabled. It is the source from which the disposable
Codex worktree is built; it is not directly edited by Codex.

### 5.7 Install common tools

The runner installs the pinned Codex CLI and downloads a pinned Gitleaks
archive. It verifies the archive SHA-256 checksum before extracting the scanner.
This gives the controller known tool versions and prevents silently trusting a
changed scanner download.

### 5.8 Prepare the disposable validation worktree

`run-agent.sh prepare` creates `${RUNNER_TEMP}/codex-issue-fix/agent-work`.
It exports the target branch with `git archive`, initializes a new Git
repository, configures a baseline identity, and records a baseline commit.
Codex receives this disposable copy, not the authenticated checkout.

The target repository must contain:

```text
.agents/skills/repository-validation/SKILL.md
```

An optional executable `setup.sh` may install locked dependencies or isolated
tools. Setup must not modify tracked or non-ignored files. An optional
`cleanup.sh` runs after the attempt even when Codex fails.

### 5.9 Prepare the Linux Codex sandbox

The job records user-namespace and AppArmor settings, enables values required
by Bubblewrap, and restores the original values in a later always-run step.
This is runner preparation, not a repository or cloud-resource change.

### 5.10 Restore Codex authentication

`CODEX_AUTH_JSON` is written to `~/.codex/auth.json` with mode `0600`. It is
restored only after repository setup. The workflow empties and removes the file
after implementation, including successful and failed attempts.

### 5.11 Run Codex

Codex executes once in the disposable worktree with workspace-write, no
interactive approval, ignored user configuration, and the trusted output
schema. The issue title and body are enclosed in `<github_issue>` and are data,
not instructions.

The structured result must contain a diff-wide summary, a non-empty change
list, an implementation approach, a validation status of `passed`, `failed`, or
`blocked`, at least one validation command, a failure reason string, a risks
array, and a documentation string. Command results may also use `skipped` when
a prerequisite did not complete.

### 5.12 Protect paths

The controller rejects changes to `.agents`, `.github`, `AGENTS.md`,
`.gitignore`, real environment files, and credentials. This prevents Codex from
weakening its own validation instructions, CI policy, or secret configuration.

### 5.13 Secret-scan the candidate

Gitleaks scans the candidate Git history and scans the structured result as a
separate directory. A finding or scanner failure prevents branch publication
and PR creation.

### 5.14 Publish the candidate branch

Only after the safety gates pass does the workflow create a GitHub App
installation token. The patch is applied to `codex/issue-N`, committed, and
pushed with `--force-with-lease`. The lease prevents silently overwriting a
branch that changed concurrently.

### 5.15 Create the PR

The App token creates a PR whose base is the verified target branch. A fully
validated candidate is opened ready for review; a candidate with failed or
blocked validation is opened as a draft. Its title is derived from the issue
title. Its body contains a diff-wide summary and change list, the objective file
list from Git, implementation approach, commands and results, risks,
limitations, and a human-review notice.

### 5.16 Report the result

The workflow updates one marked issue comment with the target branch, result,
PR URL, validation status, and failure reason. “No pull request was created”
means no accepted patch reached publication; it does not mean the issue was
deleted or merged.

## 6. Issue outcomes

| Outcome | Meaning | Branch/PR |
|---|---|---|
| Invalid issue | Form contract failed | None |
| Missing approval | External author not authorized | None |
| Validation skill missing | Repository lacks its contract | None |
| Setup changed tracked files | Environment setup violated policy | None |
| No Codex change | No safe implementation was produced | None |
| Protected path changed | Candidate rejected | None |
| Secret scan failed | Sensitive value or scanner error | None |
| Accepted validated patch | Safety gates and validation passed | One branch and one review-ready PR |
| Accepted patch with incomplete validation | Safety gates passed; validation failed or was blocked | One branch and one draft PR |

## 7. Review-fix caller flow

The checked-in review workflow is also reusable `workflow_call` code and does
not declare a `pull_request` event itself. Repository-local caller workflows
are not present here, so their exact event filters and conditions are not
verified by this repository.

The caller is expected to invoke it for events such as:

```yaml
on:
  pull_request:
    types: [opened, synchronize, reopened]
```

The reusable workflow accepts these inputs:

| Input/secret | Required | Default or value |
|---|---:|---|
| `profile` | No | Optional caller metadata; it does not select paths or commands. |

| `automation_ref` | No | `main` |
| `max_fix_rounds` | No | `2` |
| `max_negotiation_rounds` | No | `5` |
| `deletion_line_threshold` | No | `30` |
| `deletion_ratio` | No | `3` |
| `codex_cli_version` | No | `0.145.0` |
| `CODEX_AUTH_JSON` | Yes | Raw `~/.codex/auth.json` contents. |
| `CLIENT_ID` | Yes | GitHub App client ID. |
| `PRIVATE_KEY` | Yes | GitHub App private key. |

### Repository-owned trusted validation

The repository provides `.agents/skills/repository-validation/SKILL.md`.
The shared workflow runs the reviewed base branch's optional setup script before
Codex starts. Repositories whose tools cannot execute in the Codex sandbox may
also provide executable `scripts/validate.sh`. The controller copies the
protected baseline version and runs it on the trusted GitHub runner after Codex
returns. The repository script defines the exact command; the shared controller
only implements the generic `command` and `run <repository-root>` interface.
Repository CI remains the authoritative merge gate.

The issue controller enables MCP servers only when the caller opts in. AWS uses
the managed AWS Knowledge endpoint. Terraform uses the official registry-only
Terraform MCP container, pinned by version and manifest digest, with no host
mounts or Terraform credentials. Enabled servers are required, so startup
failure stops the Codex run rather than silently continuing without them.

The reusable review workflow declares `contents: write` and
`pull-requests: write`, uses concurrency group
`codex-review-fix-${{ github.repository }}-${{ github.event.pull_request.number }}`,
sets `cancel-in-progress: false`, runs on `ubuntu-latest`, and has a
90-minute job timeout. The same-repository/fork condition is not present in
this repository's reusable workflow; if a caller adds that condition, it must
be documented from the caller code rather than inferred here.

## 8. Review-fix workflow: every execution step

### 8.1 Check out central automation

The reusable workflow checks out the selected central revision into
`organization-automation`. The PR cannot replace the review prompt or loop.

### 8.2 Generate the GitHub App token

The App token is created before the PR checkout. It is used for checkout,
validated pushes, and the final evidence comment. This makes the publishing
identity consistent and avoids the special event behavior of a default
`GITHUB_TOKEN`.

### 8.3 Check out the PR head

The real PR branch, not GitHub's synthetic merge ref, is checked out into:

```text
${{ github.workspace }}/target-repository
```

The `path` must be under the checkout action's `with:` block. The controller's
`REPOSITORY_ROOT` points to this exact directory. A missing or misplaced path
causes `git -C .../target-repository` to fail before review starts.

### 8.4 Detect an automatic-fix synchronize event

The guard reads the latest commit subject. A subject matching:

```text
Apply Codex auto-fix round N [codex-autofix]
```

sets `skip=true`. Review, Codex, validation, and delivery steps then skip. This
prevents an automatic push from creating an endless synchronize loop. A human
commit or the original issue-generated commit does not match this pattern and
is reviewed normally.

GitHub reruns use the original workflow revision. Rerunning an old failed run
does not reload a newly merged reusable workflow. To test a central workflow
fix, create a fresh PR event or push a legitimate new commit.

### 8.5 Repository-owned validation setup

Before starting Codex, the reusable workflow checks the PR base commit for
`.agents/skills/repository-validation/scripts/setup.sh`. If present, it must be
executable. The workflow extracts that reviewed base-branch version into the
runner temporary directory and executes it against the PR checkout. This makes
repository-owned tools and environment variables available to the subsequent
review loop without executing a setup script controlled by the PR head.

The workflow similarly extracts an executable base-branch `validate.sh`, when
present, and exposes only that protected copy to the review controller. Codex
does not run setup or trusted validation inside its sandbox. After fixes, the
controller executes validation on the runner and adds the actual result to the
evidence comment. Repositories without these scripts retain the legacy
skill-defined behavior. Repository CI remains the authoritative merge gate.

### 8.6 Seed Codex authentication

The workflow rejects an empty `CODEX_AUTH_JSON`, writes it with restricted
permissions, and records its path. It removes the file after the loop, even if
the loop fails.

### 8.7 Run the persistent review-fix loop

`run-loop.sh` performs at most `MAX_FIX_ROUNDS` rounds. A round contains:

1. Full three-dot diff review against the base SHA.
2. Persistent reviewer/fixer negotiation.
3. Fixer edits limited to agreed findings.
4. Git reset to collapse any Codex stage/commit attempts.
5. Gate A finding-citation scope.
6. Whole-file deletion protection.
7. Codex validation evidence is captured.
8. Commit and push if product changes remain.

### 8.8 Reviewer thread

The reviewer reads the current full PR diff and ends with exactly one verdict:
`VERDICT: needs-changes` or `VERDICT: looks-good`. It checks bugs, security,
quality, and diff-based test coverage. Coverage findings are advisory and must
not require a test edit merely to make a finding disappear.

### 8.9 Negotiation threads

The fixer first answers every finding with `Agree` or a specific `Disagree`.
Disagreements go back to the same reviewer thread. The reviewer can concede or
hold each finding. `MAX_NEGOTIATION_ROUNDS` bounds the exchange and the
negotiation transcript is included in evidence.

This prevents the fixer from treating every review sentence as an unquestioned
command and gives human reviewers visibility into disputed findings.

### 8.10 Fix prompt scope

The fixer may make only changes required by agreed findings. Every changed file,
including a newly created file, must be cited by a finding using `file:line`.
It must not perform unrelated cleanup, finish an unrelated TODO, or delete a
complete file. No directory structure is assumed.

### 8.11 Gate A: cited-file restriction

The controller does not use a profile prefix. It extracts file paths from
`file:line` citations in the agreed findings and reverts both tracked and
untracked changed files that are not cited. New files are not exempt; the
reviewer must cite them if the fixer is expected to create them.

### 8.12 Whole-file deletion guard

A staged whole-file deletion is restored from the round starting commit. In-file
deletions can remain when they are part of an agreed fix, but deleting an entire
file is never automatic. The attempted deletion and fixer summary are captured
for human review.

### 8.13 Commit and push

Surviving product changes are committed as:

```text
Apply Codex auto-fix round N [codex-autofix]
```

The branch is pushed without force. If a human moves the branch during the run,
the push fails rather than overwriting human work.

### 8.15 Final review and evidence

When the round cap is reached, one confirming review runs without another fix.
The cumulative diff is passed to the evidence template. The workflow posts or
updates one marked PR comment containing findings, negotiation transcript,
cleanup notes, validation information, and evidence.

## 9. Review-fix controls

| Control | Default | Reason |
|---|---:|---|
| `max_fix_rounds` | 2 | Bounds automatic product commits per run. |
| `max_negotiation_rounds` | 5 | Bounds reviewer/fixer disagreement exchanges. |
| `deletion_line_threshold` | 30 | Flags large in-file removals. |
| `deletion_ratio` | 3 | Flags removals much larger than additions. |
| Job timeout | 90 minutes | Stops a hung loop. |
| Concurrency group | One group per PR | Prevents concurrent branch races. |

The loop may run again for a human PR change. Its own fix commit is recognized
and skipped by the synchronize guard.

## 10. Why several workflow runs can appear

Issue automation subscribes to `opened`, `edited`, `reopened`, `labeled`, and
`unlabeled`.
Opening, editing, and approving can therefore create separate visible runs.
The current request label is `codex-run-requested`; adding it does not invoke
the caller's approval-only labeled path. Adding `codex-run-approved` does invoke
verification again and can unlock the coding job when the labeler is a
maintainer.

Editing a contributor issue removes its prior approval. Removing the approval
label also reruns verification, and issue concurrency cancels older runs when a
new edit or approval state arrives. Cancelled superseded runs do not post a
result comment or change result labels; the replacement run owns that output.
PR and issue result messages include issue author, approval maintainer, trigger
actor, and workflow run ID.

Review automation subscribes to `opened`, `synchronize`, and `reopened`. Every
human push naturally creates `synchronize`. An automatic fix push also creates
`synchronize`, but the `[codex-autofix]` guard skips its own follow-up run.

## 11. Troubleshooting

### “Repository validation environment is ready” but no PR

That text means only that repository setup succeeded. Inspect the
`Implement and validate issue` step next. If it was cancelled or skipped, no
patch reached publication. The final comment's “No pull request was created”
is an outcome summary, not a claim that the issue was deleted.

### `target-repository` does not exist

The review checkout must have `path: target-repository` under the checkout
action's `with:` block. If the line appears inside the shell script, the job is
using a broken workflow revision. Merge the correction and trigger a fresh PR
event; rerunning an old run continues using its original revision.

### App token reports Not Found

The App is not installed on the target repository, or the installation does not
cover it. Install the App on that repository and grant Contents write and Pull
requests write. Issues write is needed when comments or labels are used.

### App client ID is empty

The caller must define a `CLIENT_ID` secret and pass it explicitly. Secret names
must not use the prohibited `GITHUB_*` prefix. The reusable workflow cannot read
a secret that the caller does not forward.

### No review output

Codex authentication may be stale, empty, or invalid, or the CLI may have
failed. The controller fails loudly rather than interpreting no output as a
clean review.

### Gate A reverted the change

The fixer changed a file that no agreed finding cited. Inspect cleanup notes and
the fixer summary. The reviewer must cite every file and line that the fixer is
expected to change.

### Validation failed

Inspect Codex's command-by-command validation evidence and the repository CI
checks. Codex gets one repair attempt for implementation-caused failures;
environment or dependency failures are reported rather than hidden.

### Push was rejected

The branch moved after checkout, usually because of a human push or another
workflow. The loop does not force-push. Review the current branch and retry.

## 12. Repository configuration checklist

Each caller repository should provide:

1. A thin caller workflow on the default branch.
2. `CODEX_AUTH_JSON`, `CLIENT_ID`, and `PRIVATE_KEY` Actions secrets.
3. `.agents/skills/repository-validation/SKILL.md`.
4. Optional executable issue-automation validation `setup.sh` and `cleanup.sh` scripts.
5. Required write permissions and branch rules allowing automation branches.
6. GitHub App installation on the repository.
7. Repository CI checks that remain authoritative for merging.

The repository validation skill should state its exact install, format, lint,
type-check, test, build, and infrastructure commands. The central automation
does not guess whether a repository uses React, Vite, Python, Flask, Terraform,
or a particular database.

## 13. Safe rollout procedure

1. Validate central YAML and shell syntax locally.
2. Review the central workflow in a human-approved PR.
3. Merge the organization workflow first.
4. Confirm each caller references the intended central ref.
5. Run a small, reversible issue or PR pilot.
6. Inspect every job step, not only the final issue/PR comment.
7. Confirm no test files, credentials, plans, or state files entered a commit.
8. Confirm the App identity performed publishing and comments.
9. Enable additional repositories only after the pilot is understood.

## 14. Local validation commands

From the organization `.github` checkout:

```bash
bash -n automation/codex-review-fix/run-loop.sh
bash -n automation/codex-issue-fix/run-agent.sh
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/reusable-codex-issue-fix.yml"); YAML.load_file(".github/workflows/reusable-codex-review-fix.yml"); puts "workflow YAML parsed"'
git diff --check
```

For each caller repository, also parse its local workflow and run the
repository's documented Terraform, frontend, or backend checks. Local checks
cannot prove GitHub permissions, secret availability, App installation, or
event behavior; a live pilot is still required.

## 15. Code-backed implementation reference

This section records implementation details that are easy to lose when using
the higher-level flow above. They are taken from the checked-in workflows,
shell controllers, JavaScript verifier, prompts, and JSON schema.

### 15.1 Issue verifier implementation

`automation/codex-issue-fix/verify-issue.js` is dependency-free and exports
four helpers:

- `automationLabelsForIssue()` always returns an empty array. The verifier does
  not add a request label.
- `isTrustedAssociation()` returns true only for `OWNER`, `MEMBER`, and
  `COLLABORATOR`.
- `extractTargetBranch()` accepts either a level-2 through level-6 Markdown
  `Target branch` heading or an inline `Target branch: value` form. It accepts
  branch characters matching `[A-Za-z0-9._/-]+`, rejects a leading slash,
  `..`, `@{`, `//`, a trailing slash, a trailing dot, and a `.lock` suffix.
- `validateIssue()` trims title and body, requires a title of at least 10
  characters, requires a body of at least 80 characters, and accepts only a
  title matching `^[Bug|Feature|Task]` in the implemented regular-expression
  form `[Bug]:`, `[Feature]:`, or `[Task]:` followed by whitespace and a
  non-space character.

The required Markdown headings are exactly:

| Type | Required headings |
|---|---|
| Bug | `Target branch`, `Problem summary`, `Current behavior`, `Expected behavior`, `Steps to reproduce`, `Acceptance criteria`, `Validation and evidence`, `Safety check` |
| Feature | `Target branch`, `Problem and context`, `Desired behavior`, `Acceptance criteria`, `Validation and evidence`, `Safety check` |
| Task | `Target branch`, `Context`, `Required change`, `Acceptance criteria`, `Validation and evidence`, `Safety check` |

Each section must be non-empty and must not equal `_No response_`. The safety
checkbox must match this exact checked line:

```text
- [x] I removed secrets, credentials, tokens, and sensitive personal data from this issue.
```

The workflow then performs API checks that are outside the pure verifier:

1. It calls `repos.getBranch` for the extracted target branch.
2. It requires the configured approval label for an author whose association
   is not trusted.
3. It lists all PRs and rejects any existing PR whose head is
   `${owner}:codex/issue-${issue_number}`.
4. It writes the issue title and body to
   `${RUNNER_TEMP}/codex-issue-fix/issue.md` with mode `0600`.

The verification outputs are `eligible`, `target_branch`, and
`problems_json`. An ineligible run creates or updates one bot comment marked
`<!-- codex-issue-verification -->`; the comment lists every problem and asks
the author to edit the issue. No repository checkout or Codex implementation
step runs when `eligible` is not `true`.

### 15.2 Issue controller preparation mode

`run-agent.sh` uses `set -euo pipefail`, requires `REPOSITORY_ROOT`, and supports only `prepare` and
`implement`; any other mode exits with status 2 and prints
`Usage: $0 prepare|implement`.

In `prepare` mode it:

1. Removes and recreates `${RUNNER_TEMP}/codex-issue-fix/agent-work`.
2. Exports `HEAD` from the target checkout with `git archive HEAD | tar -x`.
3. Initializes a new Git repository in the exported directory.
4. Sets identity `codex-baseline <codex-baseline@localhost>`.
5. Creates the `Codex isolated baseline` commit and records its SHA in
   `baseline.sha`.
6. Requires `.agents/skills/repository-validation/SKILL.md`.
7. If `scripts/setup.sh` exists, requires it to be executable and runs it with
   the isolated worktree path as its only argument.
8. Rejects setup if it changes tracked files, staged files, or creates
   non-ignored files.
9. Emits `prepared=true` and the reason
   `Repository validation environment is ready` only after all checks pass.

Failure reasons emitted by preparation are missing validation skill,
non-executable setup script, setup failure, tracked-file modification, or
non-ignored files created by setup. The workflow later looks for an optional
executable `scripts/cleanup.sh` in the isolated worktree. It runs it with the
worktree path after the attempt; a missing executable or cleanup failure is a
warning, not a new implementation result.

### 15.3 Issue controller implementation mode

In `implement` mode the controller requires `CODEX_AUTH_FILE` and
`SECRET_SCANNER`. It installs an exit trap that empties the Codex auth file and
restores mode `0600`. The prompt is the trusted prompt file followed by the
issue snapshot inside `<github_issue>...</github_issue>`.

The initial Codex turn runs from the isolated worktree with:

```text
codex exec
  --sandbox workspace-write
  --config approval_policy="never"
  --ignore-user-config
  --ignore-rules
  --skip-git-repo-check
  --json
  --output-schema agent-output.schema.json
  --output-last-message agent-result.json
```

`GH_TOKEN` and `GITHUB_TOKEN` are removed from the Codex environment. Standard
error is written to `codex.log`, while JSON events are captured separately so
the controller can retain the thread ID. A nonzero Codex exit emits
`Codex agent execution failed`. The controller rejects a result unless it has
non-empty string `summary`, non-empty `changes` array, string `approach`,
`validation.status` equal to `passed`, `failed`, or `blocked`, a non-empty
validation command array, a string failure reason, an array of risks, and string
documentation. A command whose prerequisite did not complete may be `skipped`.
A non-passed overall result must have a non-empty failure reason.

After initial result validation, the controller:

- records all changed paths relative to the baseline, including added,
  copied, deleted, modified, renamed, type-changed, or unmerged paths;
- rejects `.agents`, `.codex`, `.github`, `AGENTS.md`, `.gitignore`, real
  `.env` files, and their nested equivalents, while allowing `.env.example`;
- rejects a no-change result;
- creates a `Codex candidate change` commit in the isolated repository;
- runs Gitleaks `git --redact --no-banner --no-color` over the baseline-to-
  candidate history;
- when validation is not `passed`, copies and secret-scans the structured result
  before including it as untrusted diagnostic data in one repair prompt;
- builds the trusted repair instructions as literal text and appends the scanned
  feedback separately, so prompt markup cannot trigger shell expansion;
- resumes the same Codex thread with `workspace-write` for that single repair
  turn, or starts a fresh workspace-write turn with the full trusted context if
  no thread ID was captured;
- reapplies the protected-path and baseline-to-candidate secret scans after the
  repair and accepts the repair turn's validation result as final;
- preserves the initial implementation summary when the repair turn only reruns
  checks; if the repair changes code, it appends those implementation details;
- derives an objective changed-file list from the final Git diff;
- copies the final structured result and changed-file list into a separate
  result-scan directory and runs Gitleaks `dir --redact --no-banner --no-color`
  over it;
- distinguishes a secret finding (scanner exit 1) from a scanner failure;
- marks the result safe only after both scans pass;
- opens a draft PR with the unresolved evidence when validation remains
  `failed` or `blocked` after the one repair turn; and
- writes a binary patch from baseline to candidate and rejects an empty patch.

The controller emits `patch_ready=true` after path and secret gates pass. Its
reason records either successful validation or the retained `failed`/`blocked`
status after the bounded repair turn. No branch or PR is published before this
output is present.

### 15.4 Issue workflow tool and cleanup details

For an eligible issue, the workflow concatenates `AGENTS.md` and
`automation/codex-issue-fix/prompts/base.md` into the trusted prompt, copies
the controller and schema into runner scratch storage, and checks out the
verified target branch into `target-repository` with `fetch-depth: 1` and
`persist-credentials: false`.

It installs `@openai/codex@0.150.0`. When Terraform MCP is enabled, it pulls the
official `hashicorp/terraform-mcp-server:1.2.0` image pinned to its immutable
manifest digest before Codex authentication is restored. It also downloads
Gitleaks `v8.30.1` for Linux x64. The archive is checked against SHA-256
`551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb` before the
binary is extracted and made mode `0700`.

The workflow records and temporarily changes these Linux settings when they
exist:

- `kernel.unprivileged_userns_clone` is set to `1`;
- `kernel.apparmor_restrict_unprivileged_userns` is set to `0`.

Both original values are restored in an always-run step, with warnings if
restoration fails. The Codex auth JSON is written to `~/.codex/auth.json` with
mode `0600` and emptied and removed after the agent step. The target checkout
does not receive GitHub credentials.

When a patch is ready, the workflow creates a GitHub App token with
`actions/create-github-app-token` v3.2.0, configures the publishing identity as
`animal-automation-bot[bot] <animal-automation-bot[bot]@users.noreply.github.com>`,
checks out or creates `codex/issue-N` from `origin/TARGET_BRANCH`, applies the
patch with `git apply --index`, and commits:

```text
fix: address issue #N
```

If the branch already exists, it is fetched and pushed with a matching
`--force-with-lease`; a new branch uses an empty lease. The PR uses the verified
target branch as base, removes the `[Bug]`, `[Task]`, or `[Feature]` prefix from
the issue title, truncates the remainder to 180 characters, and creates the
title `fix: <clean title>`. Passed validation creates a review-ready PR; failed
or blocked validation creates a draft.

The generated PR body includes the issue number, diff-wide summary, semantic
change list, Git-derived changed-file list, implementation approach, automated
validation status, every command/result/details entry, a failure or blocking
reason when status is not `passed`, risks, documentation status, and these fixed
notices: automation generated it and requires human review; no deployment,
merge, Terraform apply, or remote database migration was run. The text
`Overall status: blocked` is intentionally not used: environment limitations
are displayed as `incomplete — environment or tooling limitation`.

For an eligible run that was not cancelled, the final issue result comment is marked
`<!-- codex-issue-fix-result -->`. It reports the target branch, stop reason,
PR URL or `No pull request was created.`, and validation status when the
secret-scanned result is available. It distinguishes “branch was pushed, but
pull request creation failed” from earlier failures. Existing result and
verification comments are updated only when their bot marker is found.

### 15.5 Review workflow setup and execution

The review workflow checks out the selected `automation_ref` from this
organization repository with `fetch-depth: 1` and no persisted credentials.
It creates the GitHub App token before checking out the PR head. The PR
checkout uses the actual `github.head_ref`, `fetch-depth: 0`, the App token,
persisted credentials, and path `target-repository`.

The trigger guard reads the latest commit subject. It sets `skip=true` only
when the subject matches:

```text
Apply Codex auto-fix round <anything> [codex-autofix]
```

When skipped, authentication, Codex, the loop, cleanup, and
evidence comment are skipped. A human or other non-matching commit proceeds.

The reusable workflow does not define stack-specific tooling or validation
commands. It executes the reviewed base branch's optional setup and validator
scripts. The repository owns runtime, dependency, provider, cache, module, and
validation details; provider-facing validation runs outside the Codex sandbox.

The workflow prepares and restores the same two Linux sysctl settings as the
issue workflow. It rejects an empty `CODEX_AUTH_JSON`, writes the raw secret
contents to `~/.codex/auth.json` with mode `0600`, installs the configured
Codex CLI version globally, and removes the auth file after the loop even when
the loop fails or times out.

### 15.6 Review controller validation contract

`run-loop.sh` uses `set -uo pipefail` and requires `MAX_FIX_ROUNDS`, `MAX_NEGOTIATION_ROUNDS`,
`DELETION_LINE_THRESHOLD`, `DELETION_RATIO`, `BASE_SHA`, `SRC_BRANCH`,
`REPOSITORY_ROOT`, and `VALIDATION_SCRIPT`. The
Codex command is:

```text
codex exec --sandbox workspace-write --skip-git-repo-check
```

The scratch directory is `${RUNNER_TEMP}/codex-review-fix`, outside the
repository. It contains the review output, Codex log, evidence, negotiation
notes, cleanup candidates, and no-op summary. The controller sets the Git
identity to `codex-autofix[bot] <41898282+github-actions[bot]@users.noreply.github.com>`
and does not create a new branch.

The generic fixer rules prohibit unrelated edits, Git commands, deployment or
remote-service changes, credential/secret edits, generated dependency folders,
build output, and complete-file/function/class/component/resource deletion.
They require every changed file to be cited by an agreed finding and do not
prohibit any repository directory solely because of its name.

### 15.7 Review loop and gate order

At the start, the loop records the PR head as `LOOP_START`. Each round does the
following in order:

1. Writes a three-dot diff, `BASE_SHA...HEAD`, so changes on the base branch
   after the fork point are not misread as PR changes.
2. Uses one persistent reviewer Codex thread. The review prompt checks bugs,
   security, basic quality, and diff-based test presence; test findings are
   advisory. It skips linter/formatter nitpicks, generated files, lockfiles,
   and vendored code. It requires severity-tagged findings with applicable
   `file:line` citations and ends with `VERDICT: needs-changes` or
   `VERDICT: looks-good`.
3. Fails loudly if the reviewer produces no output. It uses the last verdict
   token, not a quoted intermediate verdict.
4. Uses one persistent fixer thread to answer every finding with `Agree` or a
   specific `Disagree`, before editing anything.
5. Resumes the reviewer thread for disagreements. The reviewer can `CONCEDE`
   and drop a finding or `HOLD` and retain it. Negotiation stops at agreement
   or the configured negotiation-round cap, and the transcript is saved.
6. Resumes that same fixer thread to edit only the surviving findings.
7. Runs `git reset --mixed` to collapse any Codex stage or commit into the
   working tree before gates inspect it.
8. Gate A extracts cited paths from `file:line` citations, reverts tracked and
   untracked changes to files not cited by a finding, and records cleanup notes.
9. Whole-file deletions are restored from `LOOP_START`; in-file deletions can
    remain. The attempted deletion and fixer summary become a human cleanup
    candidate.
10. The surviving changes are staged. If no staged product change remains,
    the fix summary is saved as a no-op summary and no commit is made.
11. Deletions are flagged if they exceed the configured line threshold, or if
    at least 10 lines are deleted and deleted lines exceed
    `deletion_ratio * added lines`.
12. Codex reports the validation commands and results in its evidence.
13. If product changes remain, the loop commits
    `Apply Codex auto-fix round N [codex-autofix]`.

The loop stops on a clean review, a blocked validation, a no-op, or the maximum
round count. If the maximum is reached immediately after a fix, it performs
one additional confirming review without attempting another fix. If at least
one fix was committed, it generates one evidence document from the complete
cumulative diff using `evidence-template.md`; evidence describes the finding,
rationale, diff hunk, and verification and must flag deletions.

Finally, the loop writes outputs for fix count, stop reason, whether a fix was
made, deletion warnings, cleanup notes, negotiation notes, and a no-op
summary. If fixes exist, it pushes `HEAD` to the PR's own branch without force.
A rejected push means the branch moved during the run; the validated fixes are
not pushed and the job exits with an error.

### 15.8 Review evidence comment

The review workflow creates or updates one App-authored issue comment on the
PR with marker `<!-- codex-loop -->`. It paginates all comments, matches both
the marker and the App bot login, and patches that comment when found.

The comment includes the first review, a deletion warning when applicable,
fix count and stop reason, evidence and final confirming review when fixes
were pushed, or a no-op summary when nothing was applied. It also includes
the negotiation transcript and cleanup candidates when those files exist.
The comment explicitly tells a human to re-review new commits if the PR was
already approved and states that fixes were committed directly to the branch.

### 15.9 Incomplete validation and prerequisite reporting

The issue implementation schema permits overall validation statuses `passed`,
`failed`, and `blocked`. `failed` means a check found an implementation or
repository defect. `blocked` means the environment or toolchain prevented a
check from completing. Individual commands may be `skipped` when a prerequisite
failed; for example, `terraform validate` is skipped when `terraform init` did
not complete instead of repeating a missing-provider error as a second failure.

The issue controller does not discard an otherwise safe candidate solely because
validation is incomplete. It protects changed paths, secret-scans the candidate
history and report, and emits `patch_ready=true`. The workflow creates a draft
PR and labels the issue `codex-run-validation-blocked`; only a PR with passed
validation receives `codex-run-completed`.

A repair turn resumes with the same `workspace-write` sandbox as the initial
turn. Its validation evidence becomes final, but a validation-only repair cannot
overwrite the original implementation summary with a no-change message. The PR
renders a semantic change list plus an objective list of files from the final
Git diff.

Terraform repository setup should prepare providers before the network-restricted
agent turn, store the Terraform data directory and plugin cache in writable,
ignored workspace paths, and use a local provider mirror. Provider-facing
validation should run through the trusted validator after the agent turn, not
inside Codex. A remaining blocked result is evidence that human follow-up is
required; it is not permission to merge or deploy.

## 16. Definition of done

An automation change is complete only when:

- every issue field and workflow stage is documented;
- event and permission behavior is understood;
- secrets are explicit and protected;
- Codex runs in the intended isolation boundary;
- scope, citation, deletion, validation-evidence, and secret gates are active;
- failure output identifies the actual failing stage;
- local syntax and diff checks pass;
- a human reviews the resulting PR; and
- no merge or production deployment is assumed by automation.
