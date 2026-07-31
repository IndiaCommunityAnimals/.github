# IndiaCommunityAnimals GitHub Standards

<!-- This repository is the organization-wide source for community files and shared CI. -->

This public special-purpose repository supplies default issue forms, the pull
request template, organization agent policy, and reusable Codex issue-to-PR
automation for the infrastructure, frontend, and backend repositories.

Bug, Feature, and Technical Task forms all request Codex implementation and
produce one reviewable pull request when the repository caller is configured.
The General Issue or Discussion form is the non-automation path and never
requests a code change or pull request.

Automation starts from the implementation forms' required target-branch field,
not from a pre-existing label. The shared workflow creates missing category and
automation labels in the caller repository and attaches them to the issue.

The forms do not ask users to select Infrastructure, Frontend, Backend, or any
other fixed repository category. GitHub already identifies the repository from
where the issue is created, and repository-specific behavior stays in that
repository's agent policy and validation skill.

## Repository roles

- `.github/.github/ISSUE_TEMPLATE/` contains organization-default issue forms.
- `.github/.github/workflows/` contains callable workflows, not repository event triggers.
- `automation/codex-issue-fix/` contains the trusted controller, verifier,
  structured result schema, tests, and common prompt.
- `docs/` explains onboarding, settings, security boundaries, and rollout order.

Each implementation repository keeps a small caller workflow on its default
branch. Normal test, build, Docker, and deployment CI remains in the repository
that owns the application or infrastructure.

For frontend and backend callers, the shared workflow does not prescribe a
runtime, framework, source layout, package manager, or test command. Codex
discovers those details from the target repository; the central application
gate remains stack-neutral. Repository-specific dependency setup, validation,
and repair instructions belong to the target repository skill.

Each target repository owns a `.agents/skills/repository-validation/SKILL.md`
with its exact implementation-time checks and optional dependency-only setup
and cleanup scripts. Setup runs before credentials are restored. Codex uses the
skill before finishing, fixes implementation-caused failures, and reruns checks.
The resulting PR carries Codex's actual validation results, including the exact
failure when a check cannot pass. Repository CI and human review remain the
authoritative merge gates. A common secret scan is the exception: a finding
blocks branch publication entirely.

See [Codex issue automation](docs/codex-issue-automation.md) for issue-form
fields, triggering rules, settings, security boundaries, and rollout guidance.
