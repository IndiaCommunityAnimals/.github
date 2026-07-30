<!-- Frontend policy is repository-discovered and does not assume a framework. -->
Repository profile: frontend application.

- Inspect the repository's manifests, agent policy, source layout, existing CI,
  and tests before choosing files, commands, or implementation patterns.
- Follow the repository's existing architecture, package manager, language,
  framework, formatting, linting, type-checking, testing, and build conventions.
- Preserve accessibility, responsive behavior, loading states, error states,
  and existing user flows when they are relevant to the reported issue.
- Do not weaken existing checks or replace repository conventions merely to
  make generated changes pass.
- Do not embed secrets, credentials, tokens, or environment-specific production
  values in source code, fixtures, logs, documentation, or built assets.
- Do not publish packages, push images, or deploy the application.
