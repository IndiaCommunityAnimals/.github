# Organization Codex Issue Automation

<!-- Operational documentation for maintainers of the shared workflow and its callers. -->

## Outcome

The supported flow is:

```text
Bug/Feature/Technical Task form → verify → repo setup → Codex fix + validation → secret gate → normal PR → stop
```

The workflow never merges, deploys, applies Terraform, changes cloud resources,
or performs a remote database migration. Human review remains mandatory.

## Ownership boundary

The organization `.github` repository owns shared policy and implementation:

```text
.github/.github/ISSUE_TEMPLATE/          inherited issue forms
.github/.github/workflows/               reusable workflow
automation/codex-issue-fix/              controller and verifier
automation/codex-issue-fix/prompts/      common trusted prompt
```

The infrastructure, frontend, and backend repositories each own one small
`.github/workflows/codex-issue-fix.yml` caller. GitHub issue events are local to
the repository where the issue is created, so the organization repository
cannot replace those callers.

## Issue forms

Organization repositories inherit these forms when they do not define a local
`.github/ISSUE_TEMPLATE` directory:

| Form | Creates a Codex PR? | Required implementation information |
|---|---|---|
| **Bug report** | Yes | Target branch, problem summary, current behavior, expected behavior, reproduction steps, acceptance criteria, and validation |
| **Feature request** | Yes | Target branch, problem and context, desired behavior, acceptance criteria, and validation |
| **Technical task** | Yes | Target branch, context, required change, acceptance criteria, and validation |
| **General issue or discussion** | No | Question/topic, context, and desired discussion outcome |

The three implementation forms contain a required **Target branch** field,
which must name an existing branch in that repository. The selected branch is
checked out as the implementation baseline and becomes the generated pull
request's base. The field starts the caller workflow even when the repository
does not have the automation labels yet. The shared workflow creates the
`codex-run-requested` and `codex-run-approved` labels when needed. A contributor
gets `codex-run-requested`; a maintainer-authored issue gets
`codex-run-approved` automatically.

Editing a contributor issue removes its previous approval and returns it to the
request state. Removing an approval label also reruns verification and cannot
start the agent. Issue runs use `cancel-in-progress: true`, so newer edits or
label changes supersede older runs. A superseded run does not post an automation
result or change result labels; the replacement run owns the final issue status.

All forms require a safety confirmation that secrets, credentials, tokens, and
sensitive personal data were removed. Supporting evidence, dependencies,
constraints, risks, and out-of-scope details are available where relevant. The
General Issue or Discussion form deliberately has no target branch. It is
intended for questions, investigation, planning, and decisions that should not
create a code change.

### Why there is no repository dropdown

The repository is determined by where the issue is created. The reusable
workflow has no infrastructure, frontend, or backend profile input. Asking the
issue author to select a fixed category would duplicate repository identity.

An implementation issue therefore describes one change in its current
repository. Cross-repository work must be split into linked repository-local
issues so each caller creates one independently reviewable PR.

## Trusted prompt

The workflow concatenates trusted instructions in this order:

1. Organization `AGENTS.md`.
2. `prompts/base.md` for shared security and evidence rules.
3. The issue title and body inside `<github_issue>` delimiters as untrusted data.

Technology, architecture, dependency, and validation guidance is read from the
target repository instead of being duplicated centrally.

## Target-repository validation skill

Every caller repository owns its exact implementation-time checks in:

```text
.agents/skills/repository-validation/SKILL.md
.agents/skills/repository-validation/scripts/setup.sh    # optional
.agents/skills/repository-validation/scripts/validate.sh # optional trusted gate
.agents/skills/repository-validation/scripts/cleanup.sh  # optional
```

The optional executable setup script may install locked dependencies, download
pinned tooling, prepare offline dependency mirrors, pre-initialize dependency
data, or start an isolated supporting service. It runs in the disposable export
before Codex or GitHub credentials are restored. It must not run the validation
gates or modify tracked/non-ignored files. Cleanup runs after the agent attempt
even when validation fails.

When executable `validate.sh` exists, the controller copies the protected
baseline version before Codex starts. The script implements `command` to print
the human-readable command and `run <repository-root>` to execute the gate with
exit codes `0` (passed), `1` (failed), or `2` (blocked). The controller invokes
it on the trusted GitHub runner after Codex returns, outside the restricted
Codex sandbox. This is the supported path for provider processes or validation
tools that cannot run inside that sandbox.

Codex discovers this tracked repository skill from the isolated worktree. For a
trusted validator, Codex returns the skill-defined pending placeholder instead
of starting provider processes. The controller replaces that placeholder with
the actual runner-side result. If validation fails or is blocked, the common
controller secret-scans the structured result and sends it back to the same
Codex thread for one bounded repair turn, then runs the trusted validator again.
Without `validate.sh`, the legacy contract remains: Codex runs the checks defined
by the skill. If the thread ID is unavailable, the controller starts one fresh
repair turn with the original trusted context and validation feedback.

If an environment limitation or existing repository problem still prevents a
pass after the repair turn, Codex must report the exact command, error, and
reason. The controller preserves the candidate and opens a **draft pull
request** instead of discarding reviewable work. The issue result comment and
draft PR include the command-level outcomes; validation must pass before the PR
is promoted for merge.
The common controller protects `.agents/*`, preventing an implementation from
editing or weakening its own validation instructions. Automation stops before
Codex execution when the required skill file is missing.

## Common and repository-specific responsibilities

The common workflow contains no hard-coded repository dependency setup, path
allowlist, test, lint, build, audit, Terraform validation, or validation command.
Those instructions and executable gates live in the target repository's skill;
the common controller only enforces the generic `validate.sh` interface.

The common controller rejects `.agents`, `.github`, agent policy, real
environment files, and credentials before Git operations. Repository-specific
path and generated-file restrictions are instructions owned by the protected
repository skill and repository `AGENTS.md`.

### Application discovery contract

For frontend and backend issues, Codex must inspect before editing:

- organization and repository agent policy;
- manifests, lockfiles, and tool-version files;
- source and test layout;
- existing CI workflows and scripts;
- formatting, linting, type-checking, test, and build conventions; and
- existing architecture and compatibility boundaries.

The central automation deliberately does not assume React, React Native, Vite,
Node versions, Python versions, Flask, directory names, package managers, test
frameworks, database URLs, or fixed validation commands.

Codex reports checks it actually ran. Results produced by `validate.sh` are
runner-side controller evidence and replace the agent placeholder before pull
request publication. Repository CI and human review remain authoritative and
must prevent merge when required checks fail.

The common job is pinned to `ubuntu-24.04`. Repository-owned setup installs and
checksum-verifies the exact stack tooling it requires; the infrastructure skill
owns pinned Terraform and its provider mirror instead of relying on runner-image
contents.

## Trigger and approval

The **Bug report**, **Feature request**, and **Technical task** forms all request
automation. In a repository with a caller workflow, each valid issue requests
one Codex implementation PR. The **General issue or discussion** form is
ignored by the caller because it does not contain a target-branch field.

Labels are both visible state and the authorization gate. Caller workflows start
on implementation issue events, but the coding job proceeds only when
`codex-run-approved` exists. Contributors initially receive
`codex-run-requested`; a repository maintainer must review the issue and add
`codex-run-approved`. Maintainer-authored issues receive the approval label
automatically. Verification also checks the label event history so a contributor
cannot self-approve by adding the label or editing an old issue.

Generated PRs and issue result comments include the issue author, approving
maintainer, triggering actor, and GitHub Actions run ID for auditability.
Validated PRs receive `codex-run-completed`; draft PRs with failed or blocked
validation receive `codex-run-validation-blocked`; eligible runs that do not
publish a PR receive `codex-run-failed`. The workflow removes stale result labels
so retries cannot leave conflicting states on one issue.

## Required settings

For each caller repository:

1. Enable GitHub Actions.
2. Allow read/write workflow permissions.
3. Enable **Allow GitHub Actions to create and approve pull requests**.
4. Permit `codex/issue-*` branch creation under repository rulesets.
5. Grant the organization `CODEX_AUTH_JSON` secret to the repository.
6. Grant the caller `CLIENT_ID` and `PRIVATE_KEY` Actions secrets for the
   GitHub App credentials.
7. Keep the caller workflow on the repository default branch.
8. Set `enable_aws_mcp` and `enable_terraform_mcp` only for repositories that
   need those documentation tools.

The caller passes `CODEX_AUTH_JSON`, `CLIENT_ID`, and `PRIVATE_KEY` explicitly.
It does not use `secrets: inherit`, so unrelated organization or repository
secrets are not made available to the reusable workflow. The GitHub App used
for publication must be installed on the target repository with `Contents:
write` and `Pull requests: write` permissions.

The target checkout disables persisted Git credentials. Codex authentication
is restored only after repository setup, then removed before publication. The
GitHub token exists only in later publish/API steps and is never available to
the Codex process.

## Merge and rollout order

1. Add and validate the repository-owned validation skill first.
2. Merge and validate the organization `.github` repository.
3. Confirm organization-default issue forms appear in a repository without a
   local `.github/ISSUE_TEMPLATE` directory.
4. Configure the organization secret access and repository workflow permissions.
5. Merge the infrastructure caller and test a small repository-local issue
   using one of the three organization forms.
6. After the infrastructure pilot succeeds, add callers to frontend and backend.
7. Tag a reviewed central release and update callers to that tag or an
   immutable commit SHA.

Callers should not use a mutable central branch for long-term operation.

## Failure behavior

- Invalid issue: one marked verification comment is created or updated.
- External issue without approval: no checkout, Codex run, branch, or PR.
- Agent makes no change: result comment; no PR.
- Protected path changed: patch rejected; no PR.
- Validation skill missing: no Codex run, branch, or PR.
- Trusted validation fails because of the implementation: the controller sends
  the exact runner result to one bounded Codex repair turn and validates again.
- Validation still fails or is blocked after the bounded repair: Codex reports
  the exact command and reason; the controller publishes a draft PR and labels
  the issue `codex-run-validation-blocked`.
- A prerequisite does not complete: dependent checks are reported as skipped,
  not as duplicate failures.
- Secret scan finding in candidate code or the agent report: no branch or PR.
- PR creation forbidden by settings: branch may exist, job reports the GitHub API failure.
- Agent produces an accepted, validated patch: one commit on `codex/issue-N`,
  one review-ready PR with a diff-wide change summary and validation report, and
  one result comment.

## Local checks

Run these before publishing shared changes:

```bash
bash -n automation/codex-issue-fix/run-agent.sh
jq empty automation/codex-issue-fix/agent-output.schema.json
```

Also validate all issue forms and workflow YAML with a YAML parser or
`actionlint`. A live end-to-end test is still required because local checks do
not exercise GitHub permissions, secrets, runner sysctls, or PR creation.
