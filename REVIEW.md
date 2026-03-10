# Code Review Guidelines

> Configuration for Claude Code Review. These rules apply when reviewing PRs.
> Place this file in your project root alongside CLAUDE.md.

## Always Check

### Security
- New API routes have authentication checks (not just middleware — also in the route handler)
- No `service_role` key usage in client-side, edge, or browser-accessible code
- No hardcoded secrets, API keys, tokens, or passwords
- No secrets prefixed with `NEXT_PUBLIC_`
- Error responses do not leak `error.message`, `error.stack`, or internal details to clients
- All user inputs are validated at the API boundary (zod or equivalent)
- Webhook endpoints verify signatures from the sending service
- No raw user input passed directly into SQL queries or LLM prompts
- CORS is not set to wildcard (`*`) with credentials

### Database
- New Supabase tables have Row-Level Security (RLS) enabled
- RLS policies use `auth.uid()`, not client-provided user IDs
- Views use `security_invoker = true`
- No `SECURITY DEFINER` on functions unless explicitly justified

### Dependencies
- New packages are well-known (>10K weekly downloads, maintained, no known CVEs)
- No AI-hallucinated package names (verify they exist on npm)
- Lockfile is updated and committed

### AI / LLM
- AI API calls have `max_tokens` set
- No PII sent to AI APIs unnecessarily
- LLM outputs are sanitized before rendering or storing
- Agent/tool loops have circuit breakers

## Style

- Prefer early returns over deeply nested conditionals
- Generic error messages to clients; detailed errors logged server-side only
- Use structured logging, not raw `console.log` in production code

## Skip

- Files under `node_modules/`
- Lockfile diffs (`pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`)
- Generated files under `dist/`, `.next/`, `build/`
- Migration files under `supabase/migrations/` (review separately)
