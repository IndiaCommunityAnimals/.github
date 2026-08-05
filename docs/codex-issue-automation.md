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
does not have the automation labels yet. The shared workflow creates any missing
the optional `codex-fix-approved` label in the caller repository. No request
label is required; trusted repository contributors run automatically after
validation.

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
.agents/skills/repository-validation/scripts/cleanup.sh  # optional
```

The optional executable setup script may install locked dependencies, download
pinned tooling, or start an isolated supporting service. It runs in the
disposable export before Codex or GitHub credentials are restored. It must not
perform validation or modify tracked/non-ignored files. Cleanup runs after the
agent attempt even when validation fails.

Codex discovers this tracked repository skill from the isolated worktree. The
trusted base prompt explicitly invokes `$repository-validation`, so Codex runs
the repository's checks, repairs implementation-caused failures, and reruns the
checks before ending its single turn. If an environment limitation or existing
repository problem prevents a pass, Codex must report the exact command, error,
and reason in its structured result; that result is rendered in the pull request.
The common controller protects `.agents/*`, preventing an implementation from
editing or weakening its own validation instructions. Automation stops before
Codex execution when the required skill file is missing.

## Common and repository-specific responsibilities

The common workflow contains no repository dependency setup, path allowlist,
test, lint, build, audit, Terraform validation, or validation-reporting command.
Those instructions live in the target repository's skill so each repository
owns its implementation and validation contract.

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

Codex must report the checks it actually ran in its implementation summary. The
workflow includes that summary in the normal pull request. This is agent-reported
evidence rather than an independent controller gate; repository CI and human
review remain authoritative and must prevent merge when required checks fail.

The common job is pinned to `ubuntu-24.04`. Repository-owned setup installs and
checksum-verifies the exact stack tooling it requires; the infrastructure skill
owns pinned Terraform and TFLint instead of relying on runner-image contents.

## Trigger and approval

The **Bug report**, **Feature request**, and **Technical task** forms all request
automation. In a repository with a caller workflow, each valid issue requests
one Codex implementation PR. The **General issue or discussion** form is
ignored by the caller because it does not contain a target-branch field.

Labels are metadata, not the trigger. Caller workflows start on an implementation
issue's target-branch field. The reusable workflow provisions only the
`codex-fix-approved` label, which is needed for external-contributor approval;
trusted repository contributors do not need a label. This avoids GitHub's
behavior of silently omitting Issue Form labels that do not already exist in the
repository.

Owners, organization members, and collaborators can proceed after validation.
An external contributor requires a maintainer to add `codex-fix-approved`.
Adding that label triggers a new verification run.

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
7. Tag a reviewed central release and update callers from `@main` to that tag or
   an immutable commit SHA.

The initial `@main` reference supports the pilot. A release tag or SHA prevents
an unreviewed central change from immediately affecting all callers.

## Failure behavior

- Invalid issue: one marked verification comment is created or updated.
- External issue without approval: no checkout, Codex run, branch, or PR.
- Agent makes no change: result comment; no PR.
- Protected path changed: patch rejected; no PR.
- Validation skill missing: no Codex run, branch, or PR.
- Skill validation fails because of the implementation: Codex fixes the change
  and reruns the skill checks within its turn.
- Validation cannot pass because of an environment or pre-existing problem:
  Codex reports the exact command and reason; the normal PR exposes that
  evidence for repository CI and human review.
- Secret scan finding in candidate code or the agent report: no branch or PR.
- PR creation forbidden by settings: branch may exist, job reports the GitHub API failure.
- Agent produces an accepted patch: one commit on `codex/issue-N`, one normal
  PR containing the agent's validation report, and one result comment.

## Local checks

Run these before publishing shared changes:

```bash
bash -n automation/codex-issue-fix/run-agent.sh
jq empty automation/codex-issue-fix/agent-output.schema.json
```

Also validate all issue forms and workflow YAML with a YAML parser or
`actionlint`. A live end-to-end test is still required because local checks do
not exercise GitHub permissions, secrets, runner sysctls, or PR creation.
