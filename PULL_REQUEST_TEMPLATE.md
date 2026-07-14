# Pull Request

## Summary

Describe what this PR changes and why it is needed.

## Related Issue

Closes #

## Change Type

- [ ] Bug fix
- [ ] Feature
- [ ] Refactor
- [ ] Documentation
- [ ] Infrastructure
- [ ] CI/CD

## Root Cause or Context

For a bug, explain the root cause. For a feature or task, describe the relevant context and constraints.

## Solution

Describe the implementation and why this approach was chosen.

## Evidence

Provide reproducible proof that the change works.

### Fail Before

For bug fixes or behavior changes, show the failing test, reproduction, or previous invalid state.

```text
Command or reproduction steps:

Result:
```

### Pass After

Show the same test, validation, or scenario succeeding on this branch.

```text
Command or validation steps:

Result:
```

For frontend changes, include screenshots or recordings when useful. For infrastructure changes, include the Terraform plan summary and call out replacements, deletions, IAM, networking, WAF, database, or public-exposure changes.

## Validation

- [ ] Repository tests pass
- [ ] Build/type checks pass where applicable
- [ ] Security/dependency checks pass where applicable
- [ ] Manual verification completed where necessary

Commands executed:

```text

```

## Risk and Rollback

**Risk level:** Low / Medium / High

Describe known risks, affected systems, and how the change can be rolled back or disabled.

## Cross-Repository Impact

- [ ] No cross-repository impact
- [ ] Frontend changes required or included
- [ ] Backend changes required or included
- [ ] Infrastructure changes required or included

Describe dependencies, rollout order, and compatibility considerations.

## Documentation and Guidance

- [ ] Relevant specification updated
- [ ] README or operational documentation updated
- [ ] Repository `AGENTS.md` updated when a durable lesson or convention changed
- [ ] No documentation update required

## Human Review Checklist

- [ ] The evidence is reproducible
- [ ] The change follows the organization and repository `AGENTS.md`
- [ ] Security and privacy impact has been considered
- [ ] The PR is small enough to review confidently
- [ ] A human reviewer will make the merge decision
