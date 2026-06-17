/**
 * Test Template — use for every Phase 4.5 test authoring.
 *
 * Usage: copy, rename to f-{finding_id}.test.ts, fill RED/GREEN/boundary.
 */
import { describe, it, expect } from 'vitest';

describe('FINDING-ID: {one-line description}', () => {
  // RED: Prove the bug exists (must FAIL before fix)
  it('reproduces the bug (RED)', () => {
    // Arrange: set up the bug condition
    // Act: execute the buggy code
    // Assert: expect failure / wrong result
  });

  // GREEN: Verify the fix (must PASS after fix)
  it('passes after fix (GREEN)', () => {
    // Arrange: same setup
    // Act: same code, with fix applied
    // Assert: expect correct result
  });

  // BOUNDARY: Edge cases that SHOULD also work
  it('handles boundary: {describe the edge case}', () => {
    // e.g. null input, max value, empty string, concurrent access
  });
});
