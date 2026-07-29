<!-- Python backend profile. It is intentionally independent of Terraform and frontend rules. -->
Repository profile: Python 3.12 and Flask backend.

- Preserve the existing blueprint, service, repository, model, and settings
  boundaries instead of introducing parallel architecture.
- Use the existing SQLAlchemy and Alembic patterns for schema changes.
- Never connect to a database or run migrations, database-backed tests, or
  commands that require a database URL.
- Do not run deployment scripts, ECS commands, AWS mutation commands, or real
  migration operations against shared environments.
- Add or update pytest coverage for changed behavior when practical, but do not
  run tests that require a database in this automation.
- Keep API contracts backward compatible unless the issue explicitly requires
  and documents a breaking change.
- Do not expose tokens, OAuth secrets, database URLs, personal data, or AWS
  credentials in code, tests, fixtures, logs, or documentation.
