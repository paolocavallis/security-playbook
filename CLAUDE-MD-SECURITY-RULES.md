# Security Rules for Global CLAUDE.md

> Copy the section below into your `~/.claude/CLAUDE.md` under a `## Security` heading.
> These rules are enforced by Claude Code on every session, every project.

---

```markdown
## Security (Enforced on All Projects)

### Secrets & Environment Variables
- NEVER hardcode API keys, passwords, tokens, or secrets in code. Always use environment variables.
- NEVER prefix secrets with `NEXT_PUBLIC_` — that exposes them to every browser.
- NEVER commit `.env` files. Verify `.gitignore` includes `.env*` (except `.env.example`).
- When creating new projects, immediately set up `.gitignore` with `.env*` exclusion.

### Authentication & Authorization
- NEVER build custom auth. Use Supabase Auth, Clerk, or Auth0.
- EVERY API route must have authentication. There are no "internal" routes on Vercel — all routes are public URLs.
- EVERY webhook endpoint must verify the signature from the sending service.
- Store tokens in httpOnly secure cookies, never localStorage.

### Database (Supabase)
- ALWAYS enable Row-Level Security (RLS) on every new table immediately.
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

### AI API Security
- Always set `max_tokens` on AI API calls.
- Never send PII to AI APIs unless the feature explicitly requires it and it's documented.
- Implement per-user rate limits on AI-powered features.

### Logging
- Use structured logging (createLogger pattern). No raw console.log in production code.
- NEVER log secrets, tokens, passwords, or full PII.
- DO log auth events, data mutations, and errors with context.

### Static Analysis (Semgrep)
- Semgrep Skills (`npx skills add semgrep/skills`) must be installed on every project.
- Use `code-security` skill knowledge when writing or reviewing code.
- Use `llm-security` skill knowledge when building any LLM-powered feature.
- Run `npx semgrep scan --config auto` before deploying. Fix all critical/high findings.

### Pre-Deploy Check
Before marking any task complete, verify:
1. No hardcoded secrets in new/modified code
2. All new API routes have auth checks (not just middleware — also in the route handler)
3. All new Supabase tables have RLS enabled
4. All user inputs are validated
5. Error responses don't leak internal details
6. No new unvetted dependencies (verify they exist on npm with >1K weekly downloads)
7. Semgrep scan passes with no critical/high findings
```

---

## For Project-Level CLAUDE.md

Add project-specific security rules in each project's `.claude/CLAUDE.md`. Tailor them to what the project handles.

### Example: BI Dashboard (business intelligence)
```markdown
## Security (Project-Specific)
- BigQuery/Snowflake service account keys must never be in client code
- Dashboard data is company-confidential — verify auth on every API route
- Vercel deployment protection must be enabled for preview deploys
- CORS must be restricted to the production domain only
- Data exports must respect user permission levels — no admin data in analyst views
```

### Example: Internal Operations Tool
```markdown
## Security (Project-Specific)
- All database connections use read-only credentials unless write is explicitly needed
- Webhook endpoints verify signatures from upstream services
- PII fields are redacted in API responses unless the requesting user has admin role
- AI-powered features strip customer names and emails before sending to LLM APIs
```

### Example: Customer-Facing Analytics
```markdown
## Security (Project-Specific)
- Multi-tenant data isolation — every query must be scoped to the customer's org
- Rate limiting on all public endpoints (100 req/min per user)
- File uploads validated by content type (not extension) and capped at 10MB
- All data exports logged with user ID, timestamp, and row count
```
