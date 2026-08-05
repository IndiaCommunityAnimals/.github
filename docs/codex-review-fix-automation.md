# Organization Codex Review-Fix Automation

<!-- Operational documentation for maintainers of the shared workflow and its callers. -->

## Outcome

The supported flow is:

```text
Pull request opened/updated → review → fixer<->reviewer negotiation → gated
fix → validated tests → push to the PR's own branch → one PR comment
```

The workflow never merges a PR, approves it, or bypasses human review. It
commits directly to the PR's own branch — a human still opens, reviews, and
merges the PR itself.

This is the second half of a two-part pipeline. [Codex issue automation](codex-issue-automation.md)
(`automation/codex-issue-fix/`) takes a verified issue to a new PR; this
automation reviews and improves a PR that already exists, whichever
automation or human opened it.

## Ownership boundary

The organization `.github` repository owns shared policy and implementation:

```text
.github/.github/workflows/reusable-codex-review-fix.yml   reusable workflow
automation/codex-review-fix/run-loop.sh                   controller (review, negotiate, fix, gates, push)
automation/codex-review-fix/prompts/                       review prompt + evidence template
```

The infrastructure, frontend, and backend repositories each own one small
`.github/workflows/codex-review-fix.yml` caller. Pull request events are local
to the repository where the PR is opened, so the organization repository
cannot replace those callers.

## Shared prompt, not independent per-profile

Unlike `codex-issue-fix`'s `base.md` + one profile prompt per stack, the
review prompt (`prompts/review.md`) is a **single file shared by every
profile**, not split. Its content — bugs, security, code quality, test
coverage presence, severity tagging, output format — is already
stack-agnostic; splitting it would only recreate the "two nearly-identical
copies kept in sync by hand" problem this consolidation exists to remove. The
same is true of `prompts/evidence-template.md`.

What genuinely differs per stack lives in `run-loop.sh` itself, selected by
`PROFILE` at the top of the script — mirroring how
`automation/codex-issue-fix/run-agent.sh` switches `is_allowed_path()` and
`validate_agent_work()` on `PROFILE`:

- the in-scope path prefix (and, for frontend, its test-file exclusion)
- the dependency install step
- the Gate B validation command
- the fix prompt's "Rules:" bullets (wording differs enough — "function/class"
  vs. "function/component", a TypeScript-specific strictness note — that this
  is prose per profile, not a templated string)

Adding a new stack means adding a case to `run-loop.sh` deliberately, not
passing an arbitrary caller-supplied path or command as a workflow input.

## Profiles and validation

| Profile | Repository stack | Scope prefix | Gate B validation |
|---|---|---|---|
| `backend` | Python 3.12 | `api/app/` | `python -m compileall` + `pytest -m no_db` |
| `frontend` | TypeScript, Vite | `src/` (excl. `*.test.ts(x)`/`*.spec.ts(x)`) | `tsc --noEmit` + `npm run test` |
| `infrastructure` | Terraform | `infra/` | `terraform fmt` + backend-free `terraform validate` + `tflint` |

## Trigger and approval

Triggers on `pull_request: [opened, synchronize, reopened]`, same-repo PRs
only. Each caller keeps its own
`if: github.event.pull_request.head.repo.full_name == github.repository`
gate — belt-and-suspenders on top of GitHub's own platform behavior, since
fork PRs on `pull_request` (not `pull_request_target`) already can't see
secrets and get a forced read-only token regardless.

Unlike `codex-issue-fix`, there is no approval-label step: nothing here runs
against untrusted external contributions, since it only ever reacts to a PR
that already exists in this repository, opened by someone with write access
or by the issue-fix automation itself.

The review loop creates a GitHub App installation token before checking out the
PR branch. The checkout persists that token so validated fix commits are
pushed as the App, and the same token is used for the evidence comment. This
keeps the automation identity consistent and avoids the approval behavior that
can affect workflow-created pull requests using the default `GITHUB_TOKEN`.

## Required settings

For each caller repository:

1. Enable GitHub Actions.
2. Grant the organization `CODEX_AUTH_JSON` secret to the repository.
3. Grant the App credential secrets used by the caller (`CLIENT_ID` and
   `PRIVATE_KEY`). The App must be installed on the target
   repository with `Contents: write` and `Pull requests: write` permissions.
4. Keep the caller workflow on the repository default branch.

## Merge and rollout order

1. Merge and validate the organization `.github` repository first.
2. Merge one caller (e.g. backend) and test against a real PR with a
   deliberately introduced, findable issue.
3. After the pilot succeeds, add the caller to the remaining repository.
4. Tag a reviewed central release and update callers from `@main` to that tag
   or an immutable commit SHA.

The initial `@main` reference supports the pilot. A release tag or SHA
prevents an unreviewed central change from immediately affecting all callers.

## A note on execution model

`codex-issue-fix` runs Codex inside its own sandbox (`--sandbox
workspace-write --ephemeral`) against a **disposable exported copy** of the
repository (`git archive HEAD | tar -x`), and only applies the resulting
patch to the authenticated checkout after every gate passes — Codex itself
never holds push credentials or touches the real checkout.

`codex-review-fix` does not do this. It runs Codex with its configured
workspace-write sandbox directly against the
authenticated checkout, relying entirely on post-hoc gates (Gate A/A2, the
whole-file-deletion guard, Gate B) to catch anything out of line, rather than
never letting Codex touch the real tree in the first place. This was a
deliberate, tested design from when the loop lived standalone in each
repository, driven by the negotiation architecture needing Codex to actually
edit files in place across multiple resumed rounds. It was preserved as-is
during consolidation rather than redesigned to match `codex-issue-fix`'s
stronger isolation model — that would be a substantial behavior change, not
a move. Worth revisiting as a deliberate follow-up, not assumed equivalent
just because the two automations now share a repository.

## Failure behavior

- No review output (stale token or CLI failure): job fails loudly
  (`::error::`), never silently treated as "clean."
- Gate A / Gate A2 reverts an out-of-scope or uncited change: logged as a
  `::warning::` and captured in the PR comment's cleanup-candidates section;
  the round continues with the remaining in-scope changes.
- Whole-file deletion attempted: reverted, logged, and captured for a human
  to evaluate — never silently dropped.
- Gate B validation fails: the entire round is reverted; nothing is committed.
- Push rejected (branch moved during the run): job fails loudly; fixes were
  validated locally but not pushed.
- Success: one or more commits on the PR's own branch, one PR comment with
  findings, evidence, and (if applicable) the negotiation transcript.

## Local checks

Run before publishing shared changes:

```bash
bash -n automation/codex-review-fix/run-loop.sh
```

Also validate the workflow YAML with a YAML parser or `actionlint`. A live
end-to-end test against a real PR is still required — local checks don't
exercise GitHub permissions, secrets, or the negotiation loop's actual
back-and-forth with the Codex CLI.
