# Contributing to IndiaCommunityAnimals

This document defines the shared contribution workflow across IndiaCommunityAnimals repositories. The organization-wide `AGENTS.md` and each repository's local `AGENTS.md` remain authoritative for agent behavior, architecture, testing, and security.

## Development Workflow

1. Start from a structured GitHub issue with clear acceptance criteria.
2. Read the organization and repository `AGENTS.md` files.
3. Inspect existing code, specifications, tests, and conventions before making changes.
4. Create the smallest change that satisfies the issue.
5. Add or update tests and capture reproducible evidence.
6. Open a pull request using the organization PR template.
7. Obtain human review before merge.

## Definition of Ready

An issue is ready for implementation when:

- The problem or desired outcome is clear.
- Acceptance criteria are observable and testable.
- The affected repository or repositories are identified.
- Dependencies and constraints are documented.
- Required logs, screenshots, examples, or design references are attached and sanitized.
- Security-sensitive or production-impacting work is explicitly identified.

Agents must not invent missing product behavior or API contracts. Ambiguity should be resolved before implementation or explicitly documented in the proposed plan.

## Branch Naming

Use lowercase, hyphenated names:

```text
feature/<short-description>
bugfix/<short-description>
hotfix/<short-description>
infra/<short-description>
refactor/<short-description>
test/<short-description>
docs/<short-description>
ci/<short-description>
```

Examples:

```text
feature/animal-search-filters
bugfix/duplicate-animal-registration
infra/waf-rate-limit
ci/pr-evidence-check
```

## Commit Messages

Use Conventional Commit-style prefixes:

```text
feat: add animal search filters
fix: prevent duplicate registration
infra: add WAF rate limiting
refactor: simplify token rotation
test: cover missing volunteer zone
docs: update animal API contract
ci: add pull request evidence check
chore: update development tooling
```

Keep commits focused, imperative, and easy to revert. Do not mix unrelated changes in one commit or pull request.

## Evidence-Based Pull Requests

A pull request is an evidence package. It should explain:

- The problem or requested outcome.
- The root cause or relevant context.
- The implementation approach.
- The exact validation commands executed.
- Fail-before and pass-after evidence when practical.
- Risks, limitations, rollback, and cross-repository impact.

For bug fixes, prefer a regression test that fails against the prior implementation and passes with the change.

For frontend changes, include automated tests and visual evidence when useful.

For backend changes, include unit or integration tests that verify status codes, response shapes, business rules, and regressions.

For infrastructure changes, include formatting and validation results plus the Terraform plan summary. Explicitly call out replacements, deletions, IAM expansion, networking, WAF, database, public exposure, downtime, and recovery implications.

## Definition of Done

A change is done when:

- Acceptance criteria are satisfied.
- Repository conventions and specifications are followed.
- Required tests, builds, validations, and security checks pass.
- The pull request contains enough evidence for independent review.
- Documentation and specifications are updated in the same PR when behavior changes.
- Cross-repository dependencies and rollout order are documented.
- No secrets or sensitive personal information are included.
- A human reviewer approves the change and makes the merge decision.

## AI Agent Policy

AI agents may plan, implement, test, review, and document changes. Their output must be treated as a proposal supported by reproducible evidence. Agents must not bypass required checks, approve their own work, merge autonomously, or deploy production changes without explicit human authorization.

When a recurring failure or durable engineering lesson is discovered, update the appropriate repository `AGENTS.md`, or the organization `AGENTS.md` when the lesson applies across repositories.

