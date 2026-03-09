
## Security (Enforced on All Projects)

### Secrets & Environment Variables
- NEVER hardcode API keys, passwords, tokens, or secrets in code. Always use environment variables.
- NEVER prefix secrets with `NEXT_PUBLIC_` — that exposes them to every browser.
- NEVER commit `.env` files. Verify `.gitignore` includes `.env*` (except `.env.example`).
- When creating new projects, immediately set up `.gitignore` with `.env*` exclusion.
- In Vite + Vercel projects: server-side code (API routes, serverless functions) CANNOT access `VITE_` prefixed env vars. Use non-prefixed names for anything needed at runtime and set them in the Vercel dashboard.

### Authentication & Authorization
- NEVER build custom auth. Use Supabase Auth, Clerk, or Auth0.
- EVERY API route must have authentication. There are no "internal" routes on Vercel — all routes are public URLs.
- EVERY webhook endpoint must verify the signature from the sending service.
- For customer-facing apps, store tokens in httpOnly secure cookies, never localStorage. For internal tools with domain-restricted access, localStorage is acceptable with session timeouts of 8 hours or less.

### Database
- ALWAYS enable Row-Level Security (RLS) on every new Supabase table immediately.
- NEVER use the `service_role` key in client-side, edge, or browser-accessible code.
- NEVER use `SECURITY DEFINER` on database functions unless explicitly discussed and justified.
- Use parameterized queries exclusively. Never concatenate user input into SQL strings.
- Select only needed columns. Avoid `select('*')` in production code.

### Input Validation & Output Safety
- Validate ALL user inputs at the API boundary using zod or equivalent schema validation.
- Sanitize and validate AI model outputs before displaying to users or storing in database.
- Return generic error messages to clients. Log detailed errors server-side only with structured logger.
- Never pass raw user input directly into LLM prompts without sanitization.

### Dependencies
- Vet every new package before installing: check downloads, maintenance, known CVEs.
- Prefer well-known packages. Question AI-suggested packages with <1000 weekly downloads.
- Ask "can I write this in 20 lines instead of adding a dependency?" before installing.
- Always preserve and commit lockfiles. Never suggest `--no-frozen-lockfile`.

### HTTP Security & Rate Limiting
- ALWAYS apply rate limiting to every public API route. If a rate limiter exists in the project, USE IT — do not build it and leave it unused.
- ALWAYS add security headers. For Vercel: add a `headers` block in `vercel.json` with `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, and `Referrer-Policy: strict-origin-when-cross-origin`.
- NEVER expose `error.message` or `error.stack` in API responses. Return a generic message and log the real error server-side.
- NEVER pass API keys or tokens as URL query parameters — use Authorization headers only.

### Cloud Service Scopes
- ALWAYS use the most restrictive OAuth/API scope available. For BigQuery analytics, use `bigquery.readonly` unless writes are explicitly needed. For Google Drive, use `drive.readonly` unless writes are needed.
- Review cloud service scopes when setting up a new integration — default scopes are often overly permissive.

### AI API Security
- Always set `max_tokens` on AI API calls.
- Never send PII to AI APIs unless the feature explicitly requires it and it is documented.
- Implement per-user rate limits on AI-powered features.

### Logging
- Use structured logging. No raw console.log in production code.
- NEVER log secrets, tokens, passwords, or full PII.
- DO log auth events, data mutations, and errors with context.

### Static Analysis (Semgrep)
- Semgrep Skills must be installed on this project.
- Use `code-security` skill knowledge when writing or reviewing code.
- Use `llm-security` skill knowledge when building any LLM-powered feature.

### Pre-Deploy Check
Before marking any task complete, you MUST complete ALL of these steps in order:
1. No hardcoded secrets in new/modified code
2. All new API routes have auth checks (not just middleware — also in the route handler)
3. All new database tables have appropriate access controls
4. All user inputs are validated
5. Error responses do not leak internal details (no error.message/error.stack in responses)
6. No new unvetted dependencies
7. If a PR was created or updated, wait for CI then run `gh pr checks` to verify the Security Checks workflow completed
8. If `gh pr checks` shows the security workflow finished, run `gh run view $(gh run list --workflow=security.yml --limit=1 --json databaseId -q ".[0].databaseId") --log-failed` to check for warnings
9. If ANY security warnings were found in CI, fix them in a follow-up commit before reporting the task as complete
Do NOT skip steps 7-9. CI is the primary safety net for this project — there are no pre-commit hooks or branch protection blocking insecure code. If you skip the CI review, vulnerabilities ship undetected.

### CI Review Commands

Use these commands to complete steps 7-9 of the Pre-Deploy Check above:
```bash
# Step 7: Check if security workflow finished
gh pr checks

# Step 8: Read the security results
gh run view $(gh run list --workflow=security.yml --limit=1 --json databaseId -q ".[0].databaseId") --log-failed

# If no failures shown, check the full log for warnings:
gh run view $(gh run list --workflow=security.yml --limit=1 --json databaseId -q ".[0].databaseId") --log 2>&1 | grep -i "warning\|⚠️\|found.*vulnerabilit\|found.*issue\|found.*secret"
```
