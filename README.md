# IndiaCommunityAnimals GitHub Standards

<!-- This repository is the organization-wide source for community files and shared CI. -->

This public special-purpose repository supplies default issue forms, the pull
request template, organization agent policy, and reusable Codex issue-to-PR
automation for the infrastructure, frontend, and backend repositories.

## Repository roles

- `.github/.github/ISSUE_TEMPLATE/` contains organization-default issue forms.
- `.github/.github/workflows/` contains callable workflows, not repository event triggers.
- `automation/codex-issue-fix/` contains the trusted controller, verifier, tests,
  and independently editable stack prompts.
- `docs/` explains onboarding, settings, security boundaries, and rollout order.

Each implementation repository keeps a small caller workflow on its default
branch. Normal test, build, Docker, and deployment CI remains in the repository
that owns the application or infrastructure.

See [Codex issue automation](docs/codex-issue-automation.md) for the complete design.
