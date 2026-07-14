> This document defines the organization-wide standards for AI agents working across all IndiaCommunityAnimals repositories.
>
> Repository-level `AGENTS.md` files extend this policy with technology- and project-specific guidance. They should not duplicate the rules defined here.

# Organization Agent Instructions

**Organization:** IndiaCommunityAnimals

This document defines the organization-wide standards for AI agents working across all repositories. Repository-level `AGENTS.md` files extend this policy with stack-specific guidance. If there is a conflict, this organization policy takes precedence unless an explicit exception is documented.

---

# Policy Hierarchy

All repositories follow this hierarchy:

1. Organization-wide `IndiaCommunityAnimals/.github/AGENTS.md` (this document)
2. Repository `AGENTS.md`
3. Repository source code and project specifications

Repository-specific instructions must extend this document rather than duplicate it.

---

# Purpose

AI agents are engineering assistants—not autonomous developers.

Their responsibility is to:

* Understand the existing system
* Produce well-tested changes
* Preserve architectural consistency
* Minimize regressions
* Provide objective evidence for every change

Merge decisions remain the responsibility of human reviewers.

---

# Agent Principles

Agents must:

* Read existing code before introducing new patterns.
* Prefer modifying existing implementations over creating parallel ones.
* Make the smallest change necessary to solve the problem.
* Preserve backward compatibility unless explicitly requested.
* Follow repository architecture and conventions.
* Never invent APIs, contracts, or infrastructure behavior.
* Ask for clarification rather than making assumptions when requirements are ambiguous.

---

# Evidence-Based Development

Every change should produce verifiable evidence.

Whenever practical:

1. Reproduce the issue.
2. Add or update tests.
3. Implement the fix.
4. Verify the fix through automated testing.

For bug fixes, the preferred evidence is:

* Issue reproduced
* Test added or updated
* Test passes after the implementation

For infrastructure work, evidence may include:

* `terraform validate`
* `terraform plan`
* Security scans
* Configuration validation
* Deployment verification

---

# Pull Request Requirements

Every agent-generated Pull Request should clearly describe:

* Problem being solved
* Root cause
* Approach taken
* Tests executed
* Validation performed
* Risks or limitations
* Documentation updated (if applicable)

PR descriptions should make review easier rather than requiring reviewers to rediscover context.

---

# Human Review Policy

AI-generated code must always be reviewed before merge.

Agents may:

* Generate code
* Generate tests
* Review code
* Suggest improvements
* Produce documentation

Agents must **not** assume approval or merge authority.

Production deployments and infrastructure changes require explicit human approval.

---

# Testing Expectations

Every repository defines its own testing framework.

Agents must:

* Execute the repository's documented validation commands.
* Update existing tests when behavior changes.
* Add tests for new functionality where appropriate.
* Never bypass failing tests without documented justification.
* Keep changes compatible with existing CI pipelines.

---

# Security Principles

Security is mandatory for every repository.

Agents must never:

* Commit secrets or credentials.
* Expose sensitive configuration.
* Disable security controls for convenience.
* Introduce unnecessary permissions.
* Log confidential information.

Follow the repository-specific security guidance for implementation details.

---

# Documentation

Documentation is part of the implementation.

Whenever behavior, architecture, workflows, APIs, infrastructure, or user-visible functionality changes, update the appropriate documentation in the same Pull Request.

Do not leave specifications or documentation inconsistent with the implementation.

---

# Cross-Repository Changes

When a feature affects multiple repositories:

* Keep API contracts synchronized.
* Update dependent repositories as required.
* Document breaking changes.
* Preserve compatibility whenever possible.
* Clearly identify cross-repository dependencies in the PR.

---

# Repository Responsibilities

Each repository's `AGENTS.md` defines:

* Project architecture
* Technology stack
* Directory structure
* Build commands
* Test commands
* Coding conventions
* Security guidance
* Performance considerations
* Common pitfalls
* Definition of repository-specific success

Agents must always read the repository's local `AGENTS.md` before making changes.

---

# Continuous Improvement

If a recurring mistake, operational issue, or architectural lesson is identified:

* Update the appropriate repository `AGENTS.md`, or
* Update this organization document if the guidance applies across repositories.

Institutional knowledge should be captured so future agent runs benefit from previous experience.

---

# Definition of Done

A task is complete only when:

* Requirements are satisfied.
* Repository conventions are followed.
* Automated validation succeeds.
* Documentation is updated where necessary.
* No known regressions are introduced.
* The Pull Request contains sufficient evidence for human review.

Success is measured by reproducible evidence—not by who (or what) authored the code.
