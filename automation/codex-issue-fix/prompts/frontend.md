<!-- Frontend profile based on the current React 19, TypeScript, and Vite repository. -->
Repository profile: React, TypeScript, and Vite web frontend.

- Follow existing component, hook, route, API-client, styling, and test patterns.
- Preserve accessibility, responsive behavior, loading states, error states,
  and existing user flows.
- Keep TypeScript types explicit and avoid weakening checks with unnecessary
  `any`, ignored errors, or disabled lint/type rules.
- Add or update Vitest and Testing Library coverage for changed behavior when
  practical.
- Do not introduce React Native APIs unless the repository itself is migrated
  and the issue explicitly requests that architectural change.
- Do not embed API secrets, OAuth secrets, AWS credentials, or environment-
  specific production values in source code or built assets.
- Do not publish packages, push Docker images, or deploy the application.
