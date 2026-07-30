<!--
AI FIX-PR EVIDENCE TEMPLATE. NOT the human PR template — this is the
evidence-only format the loop asks Codex to fill in, from the final diff, for
the fixes it actually applied. The workflow's own comment wrapper already
states which source PR/branch this is for, how many rounds ran, and why it
stopped — do NOT duplicate those here (Codex generating this has no access to
them); only describe what's actually present in the diff.
-->
**Validation:** {{VALIDATION_SUMMARY}}  <!-- e.g. ✅ Gate B validation passed · Gate A ✅ (no deletions, in-scope) -->

---

### Change {{N}} — {{MARKER}} {{CATEGORY}} · {{SHORT_TITLE}}
- **Finding:** {{WHAT_WAS_WRONG}} — `{{FILE}}:{{LINE}}`
- **Why changed:** {{RATIONALE}}  <!-- cite the rule/spec, e.g. "AGENTS.md: secrets come from settings/env" -->
- **Change:**
  ```diff
  {{DIFF_HUNK}}
  ```
- **Verified:** {{HOW_VERIFIED}}  <!-- e.g. "import check passes; no other references to the constant" -->

<!-- repeat the Change block for each fix -->

---

### Not fixed (left for a human)
- {{FINDING}} — {{REASON}}  <!-- judgment call / out of scope / too risky to auto-edit; omit section if none -->
