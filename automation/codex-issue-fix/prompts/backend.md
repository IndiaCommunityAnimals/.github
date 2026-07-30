<!-- Backend policy is repository-discovered and does not assume a framework. -->
Repository profile: backend application.

- Inspect the repository's manifests, agent policy, source layout, existing CI,
  and tests before choosing files, commands, or implementation patterns.
- Follow the repository's existing architecture, language, framework,
  dependency manager, formatting, linting, type-checking, testing, and build
  conventions.
- Preserve existing API and data contracts unless the issue explicitly requires
  and documents a breaking change.
- Do not connect to shared databases, run remote migrations, deploy services, or
  execute commands that mutate cloud resources or external systems.
- Do not weaken existing checks or replace repository conventions merely to
  make generated changes pass.
- Do not expose secrets, credentials, tokens, database connection values,
  personal data, or cloud credentials in code, tests, logs, or documentation.
