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

## Shared prompt and repository validation

The review prompt (`prompts/review.md`) and evidence template are shared and
stack-agnostic. The loop no longer assumes a backend, frontend, Terraform,
directory, provider, runtime, package manager, or test framework.

The repository owns validation through `.agents/skills/repository-validation/SKILL.md`.
The Codex fixer reads that skill, runs its setup and every required command,
and makes one repair attempt for implementation-caused failures. The shared
controller does not assume a language, directory, provider, runtime, package
manager, or validation command. It records Codex's reported commands and
results in the evidence comment; repository CI remains authoritative for merge.
Terraform scripts should use `TF_PLUGIN_CACHE_DIR` or a provider mirror; TFLint
scripts should pin and initialize plugins separately and retain their logs.

The fixer may modify any repository path only when the path is cited by an
agreed finding using `file:line`. There is no profile path prefix. New files
are subject to the same citation rule as existing files. Whole-file deletion
remains prohibited automatically.

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
5. Keep the caller workflow on the repository default branch.

## Merge and rollout order

1. Merge and validate the organization `.github` repository first.
2. Merge one caller (e.g. backend) and test against a real PR with a
   deliberately introduced, findable issue.
3. After the pilot succeeds, add the caller to the remaining repository.
4. Tag a reviewed central release and update callers to that tag or an
   immutable commit SHA.

Callers should not use a mutable central branch for long-term operation.

## A note on execution model

`codex-issue-fix` runs Codex inside its own sandbox (`--sandbox
workspace-write --ephemeral`) against a **disposable exported copy** of the
repository (`git archive HEAD | tar -x`), and only applies the resulting
patch to the authenticated checkout after every gate passes — Codex itself
never holds push credentials or touches the real checkout.

`codex-review-fix` does not do this. It runs Codex with its configured
workspace-write sandbox directly against the
authenticated checkout, relying on post-hoc scope and deletion guards plus
Codex's validation evidence rather than
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
- Gate A reverts a change to a file that no agreed finding cites: logged as a
  `::warning::` and captured in the PR comment's cleanup-candidates section;
  the round continues with the remaining cited changes.
- Whole-file deletion attempted: reverted, logged, and captured for a human
  to evaluate — never silently dropped.
- Codex reports a validation failure: the exact command and result are kept in
  the evidence comment; repository CI remains authoritative for merge.
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
