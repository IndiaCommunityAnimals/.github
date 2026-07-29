<!-- Python backend profile. It is intentionally independent of Terraform and frontend rules. -->
Repository profile: Python 3.12 and Flask backend.

- Preserve the existing blueprint, service, repository, model, and settings
  boundaries instead of introducing parallel architecture.
- Use the existing SQLAlchemy and Alembic patterns for schema changes.
- Never connect to or modify development, preprod, or production databases.
- Run tests only against the isolated CI PostgreSQL database supplied by the
  workflow.
- Do not run deployment scripts, ECS commands, AWS mutation commands, or real
  migration operations against shared environments.
- Add or update pytest coverage for changed behavior when practical.
- Keep API contracts backward compatible unless the issue explicitly requires
  and documents a breaking change.
- Do not expose tokens, OAuth secrets, database URLs, personal data, or AWS
  credentials in code, tests, fixtures, logs, or documentation.
