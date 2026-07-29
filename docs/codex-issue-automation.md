# Organization Codex Issue Automation

<!-- Operational documentation for maintainers of the shared workflow and its callers. -->

## Outcome

The supported flow is:

```text
Automated issue form → verify → Codex fix → profile validation → normal PR → stop
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

| Profile | Repository stack | Independent validation |
|---|---|---|
| `infrastructure` | Terraform | fmt, backend-free validate, TFLint |
| `frontend` | React, TypeScript, Vite | clean install, Vitest, audit, build |
| `backend` | Python 3.12, Flask | database-independent Python syntax compilation |

The controller rejects `.github`, agent policy, real environment files,
Terraform state, real tfvars, credentials, and files outside the selected
profile allowlist before validation or Git operations.

## Trigger and approval

Only the **Automated Codex implementation** form adds the
`codex-fix-requested` label. Repository callers ignore normal bug, feature, and
technical-task issues.

Owners, organization members, and collaborators can proceed after validation.
An external contributor requires a maintainer to add `codex-fix-approved`.
Adding that label triggers a new verification run.

## Required settings

For each caller repository:

1. Enable GitHub Actions.
2. Allow read/write workflow permissions.
3. Enable **Allow GitHub Actions to create and approve pull requests**.
4. Add `technical task`, `codex-fix-requested`, and `codex-fix-approved`
   labels to both the organization `.github` repository and each caller.
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
4. Merge the infrastructure caller and test a small README-only issue.
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
- Validation fails: patch rejected; no PR.
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
