# Organization Codex Issue Automation

<!-- Operational documentation for maintainers of the shared workflow and its callers. -->

## Outcome

The supported flow is:

```text
Bug/Feature/Technical Task form → verify → Codex fix → profile validation → normal PR → stop
```

The workflow never merges, deploys, applies Terraform, changes cloud resources,
or performs a remote database migration. Human review remains mandatory.

## Ownership boundary

The organization `.github` repository owns shared policy and implementation:

```text
.github/.github/ISSUE_TEMPLATE/          inherited issue forms
.github/.github/workflows/               reusable workflow
automation/codex-issue-fix/              controller and verifier
automation/codex-issue-fix/prompts/      independent stack prompts
automation/codex-issue-fix/tests/        verifier regression tests
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

The three implementation forms automatically add `codex-fix-requested`. They
also require a safety confirmation that secrets, credentials, tokens, and
sensitive personal data were removed. Supporting evidence, dependencies,
constraints, risks, and out-of-scope details are available where relevant.

The General Issue or Discussion form deliberately has no target branch and no
`codex-fix-requested` label. It is intended for questions, investigation,
planning, and decisions that should not create a code change.

### Why there is no repository dropdown

The repository is determined by where the issue is created. The repository's
caller workflow supplies its own `infrastructure`, `frontend`, or `backend`
profile to the reusable workflow. Asking the issue author to select a fixed
repository category would duplicate information and could conflict with the
actual caller.

An implementation issue therefore describes one change in its current
repository. Cross-repository work must be split into linked repository-local
issues so each caller creates one independently reviewable PR.

## Independent prompts

The workflow concatenates trusted instructions in this order:

1. Organization `AGENTS.md`.
2. `prompts/base.md` for shared security and evidence rules.
3. Exactly one profile prompt:
   - `prompts/infrastructure.md`
   - `prompts/frontend.md`
   - `prompts/backend.md`
4. The issue title and body inside `<github_issue>` delimiters as untrusted data.

Editing one profile does not change instructions for the other profiles.

## Profiles and validation

| Profile | Central workflow behavior | Codex behavior |
|---|---|---|
| `infrastructure` | Installs Terraform/TFLint, restricts changes to `infra/*` and `README.md`, then runs fmt, backend-free validate, and TFLint | Follows the infrastructure prompt and existing Terraform policy |
| `frontend` | Installs no application runtime and runs only the stack-neutral `git diff --check` gate | Discovers the repository's architecture, tools, paths, and checks |
| `backend` | Installs no application runtime and runs only the stack-neutral `git diff --check` gate | Discovers the repository's architecture, tools, paths, and checks |

The central workflow does not install or select a frontend/backend language,
runtime, framework, dependency manager, source directory, or test command.
Codex must inspect the checked-out repository and follow its existing policy,
manifests, CI, architecture, and validation conventions.

The controller rejects `.github`, agent policy, real environment files,
Terraform state, real tfvars, and credentials before validation or Git
operations. Infrastructure retains its known `infra/*` and `README.md` path
boundary. Frontend and backend may change any path not rejected by the global
protection list because their layouts are repository-discovered.

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

This flexibility has a tradeoff: the independent central application gate
checks patch integrity with `git diff --check`, but it cannot guarantee that
repository-specific tests were selected correctly. Codex must report the checks
it actually ran in its implementation summary, and a human reviewer must verify
that evidence before merging.

## Trigger and approval

The **Bug report**, **Feature request**, and **Technical task** forms all request
automation. In a repository with a caller workflow, each valid issue requests
one Codex implementation PR. The **General issue or discussion** form is
ignored by the caller because it does not carry `codex-fix-requested`.

Owners, organization members, and collaborators can proceed after validation.
An external contributor requires a maintainer to add `codex-fix-approved`.
Adding that label triggers a new verification run.

## Required settings

For each caller repository:

1. Enable GitHub Actions.
2. Allow read/write workflow permissions.
3. Enable **Allow GitHub Actions to create and approve pull requests**.
4. Add `bug`, `needs reproduction`, `feature`, `technical task`,
   `codex-fix-requested`, and `codex-fix-approved` labels to both the
   organization `.github` repository and each caller.
5. Permit `codex/issue-*` branch creation under repository rulesets.
6. Grant the organization `CODEX_AUTH_JSON` secret to the repository.
7. Keep the caller workflow on the repository default branch.

Only `CODEX_AUTH_JSON` is passed explicitly. The caller does not use
`secrets: inherit`, so unrelated organization or repository secrets are not
made available to the reusable workflow.

## Merge and rollout order

1. Merge and validate the organization `.github` repository first.
2. Confirm organization-default issue forms appear in a repository without a
   local `.github/ISSUE_TEMPLATE` directory.
3. Create required labels and configure the organization secret access.
4. Merge the infrastructure caller and test a small repository-local issue
   using one of the three organization forms.
5. After the infrastructure pilot succeeds, add callers to frontend and backend.
6. Tag a reviewed central release and update callers from `@main` to that tag or
   an immutable commit SHA.

The initial `@main` reference supports the pilot. A release tag or SHA prevents
an unreviewed central change from immediately affecting all callers.

## Failure behavior

- Invalid issue: one marked verification comment is created or updated.
- External issue without approval: no checkout, Codex run, branch, or PR.
- Agent makes no change: result comment; no PR.
- Protected path changed: patch rejected; no PR.
- Infrastructure validation or the central patch-integrity gate fails: patch
  rejected; no PR.
- PR creation forbidden by settings: branch may exist, job reports the GitHub API failure.
- Success: one commit on `codex/issue-N`, one normal PR, one result comment.

## Local checks

Run these before publishing shared changes:

```bash
node automation/codex-issue-fix/tests/verify-issue.test.js
bash -n automation/codex-issue-fix/run-agent.sh
```

Also validate all issue forms and workflow YAML with a YAML parser or
`actionlint`. A live end-to-end test is still required because local checks do
not exercise GitHub permissions, secrets, runner sysctls, or PR creation.
