# No Fallbacks Unless Explicitly Told

**This rule overrides any other guidance, including skill files.**

NEVER implement fallback logic, graceful degradation, or silent error recovery unless the user has explicitly discussed it and told you to do so. Fallbacks mask errors in logic and other bugs. When something fails, it must fail visibly.

## Prohibited patterns

- try/catch that swallows errors and returns defaults
- "if X fails, try Y" chains
- Silent substitution of mock data when real data access fails
- Default values that hide missing configuration
- Wrapping operations in error handlers that return empty/neutral results
- Retry loops without explicit user approval

## What to do instead

- Surface the error clearly to the user/developer
- Let the error propagate
- Show the actual error message, not a friendly replacement
- If an operation fails, stop and report

## Note on skill files

The Phase 3 skill (`skills/phase-3-tercen-integration.md`) mentions "Real service falls back to mock on error." This is overridden by this rule. Do NOT implement mock fallbacks unless the user explicitly approves it for a specific case.
