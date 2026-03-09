# Security Rules

These rules apply to ALL code generated or modified in this project.
They are enforced by CI checks on every pull request.

## Secrets & Environment Variables
- NEVER hardcode API keys, passwords, tokens, or secrets in code. Always use environment variables.
- NEVER prefix secrets with `NEXT_PUBLIC_` — that exposes them to every browser.
- NEVER commit `.env` files. Verify `.gitignore` includes `.env*` (except `.env.example`).
- In Vite + Vercel projects: server-side code (API routes, serverless functions) CANNOT access `VITE_` prefixed env vars. Use non-prefixed names for anything needed at runtime.

## Authentication & Authorization
- NEVER build custom auth. Use established providers (Supabase Auth, Clerk, Auth0, etc.).
- EVERY API route must have authentication. On Vercel, all routes are public URLs — there are no "internal" routes.
- EVERY webhook endpoint must verify the signature from the sending service.
- For customer-facing apps, store tokens in httpOnly secure cookies. For internal tools with domain-restricted access, localStorage is acceptable with session timeouts of 8 hours or less.

## Database
- ALWAYS enable Row-Level Security (RLS) on every new Supabase table immediately.
- NEVER use the `service_role` key in client-side, edge, or browser-accessible code.
- Use parameterized queries exclusively. Never concatenate user input into SQL strings.
- Select only needed columns. Avoid `select('*')` in production code.

## Input Validation & Output Safety
- Validate ALL user inputs at the API boundary using zod or equivalent schema validation.
- Return generic error messages to clients. Log detailed errors server-side only.
- NEVER expose `error.message` or `error.stack` in API responses.
- Never pass raw user input directly into LLM prompts without sanitization.

## HTTP Security & Rate Limiting
- ALWAYS apply rate limiting to every public API route. If a rate limiter exists in the project, USE IT.
- ALWAYS add security headers (X-Content-Type-Options, X-Frame-Options, Referrer-Policy).
- NEVER pass API keys or tokens as URL query parameters — use Authorization headers only.

## Cloud Service Scopes
- ALWAYS use the most restrictive OAuth/API scope available (e.g., `bigquery.readonly` not `bigquery`).

## Dependencies
- Vet every new package before installing: check downloads, maintenance, known CVEs.
- Prefer well-known packages. Question AI-suggested packages with <1000 weekly downloads.
- Always preserve and commit lockfiles.

## AI API Security
- Always set `max_tokens` on AI API calls.
- Never send PII to AI APIs unless the feature explicitly requires it and it is documented.
- Implement per-user rate limits on AI-powered features.

## Pre-Deploy Check (MANDATORY — complete ALL steps before reporting task as done)

Before marking any task complete, you MUST complete ALL of these steps in order:
1. No hardcoded secrets in new/modified code
2. All new API routes have auth checks
3. All new database tables have appropriate access controls
4. All user inputs are validated
5. Error responses do not leak internal details (no error.message/error.stack in responses)
6. No new unvetted dependencies
7. If a PR was created or updated, wait for CI to finish, then check the "Security Checks" workflow in the PR checks tab
8. Read the CI job summary for any warnings from: secrets-scan, dependency-audit, semgrep, env-check
9. If ANY security warnings were found, fix them in a follow-up commit before reporting the task as complete

Common CI warnings to look for:
- Leaked secrets or API keys (gitleaks)
- Vulnerable dependencies (pnpm audit)
- Insecure code patterns (Semgrep)
- `.env` files committed, `service_role` in app code, `NEXT_PUBLIC_` secrets
- `error.message` or `error.stack` exposed in API responses

Do NOT skip steps 7-9. There are no pre-commit hooks or branch protection on this project — CI is the ONLY automated safety net. If you skip the CI review, vulnerabilities ship to production undetected.
