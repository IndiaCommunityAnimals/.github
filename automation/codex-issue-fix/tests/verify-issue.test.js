'use strict';

// This dependency-free regression test protects branch parsing and the trusted
// author boundary used before Codex receives any repository access.
const assert = require('node:assert/strict');
const {
  extractTargetBranch,
  isTrustedAssociation,
  validateIssue
} = require('../verify-issue.js');

assert.equal(extractTargetBranch('### Target branch\n\nmain'), 'main');
assert.equal(
  extractTargetBranch('### Target branch\n\n<!-- branch -->\n`release/preprod`'),
  'release/preprod'
);
assert.equal(extractTargetBranch('**Target branch**: feature/fix-123'), 'feature/fix-123');
assert.equal(extractTargetBranch('### Target branch\n\n../../main'), null);
assert.equal(extractTargetBranch('### Target branch\n\nmain;curl'), null);
assert.equal(extractTargetBranch('No branch supplied'), null);

// Bug, feature, and technical-task forms all render the same required branch
// heading, so every supported form enters the same safe checkout path.
for (const section of ['Bug description', 'Problem statement', 'Required work']) {
  const renderedForm = `### Target branch\n\nmain\n\n### ${section}\n\nDetailed request`;
  assert.equal(extractTargetBranch(renderedForm), 'main');
}

assert.equal(isTrustedAssociation('OWNER'), true);
assert.equal(isTrustedAssociation('MEMBER'), true);
assert.equal(isTrustedAssociation('COLLABORATOR'), true);
assert.equal(isTrustedAssociation('CONTRIBUTOR'), false);
assert.equal(isTrustedAssociation('NONE'), false);

assert.deepEqual(
  validateIssue({ title: 'A descriptive issue title', body: 'A'.repeat(80) }),
  { problems: [] }
);
assert.equal(validateIssue({ title: 'Short', body: 'brief' }).problems.length, 2);

console.log('Issue verifier tests passed.');
