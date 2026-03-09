# Security Review Process

## Overview

This document defines how our team performs security reviews without depending on the engineering team. It uses Claude Code's built-in capabilities to automate what would traditionally require a senior security engineer.

---

## When to Run Security Reviews

| Trigger | Review Type | Time |
|---------|-------------|------|
| Every PR / before deploy | Quick scan (pre-deploy checklist) | ~5 min |
| New feature complete | Feature security review | ~15 min |
| New project setup | Initial security baseline | ~30 min |
| Monthly schedule | Full security audit | ~45 min |
| After any incident | Incident-focused review | As needed |

---

## Quick Scan (Pre-Deploy)

Run this before every deployment:

**Step 1: Semgrep scan**
```bash
npx semgrep scan --config auto
```
Fix any critical or high findings before proceeding.

**Step 2: Claude Code review**
```
/review-pr
```

**Step 3: Ask Claude Code for security-specific review**
```
Run the pre-deploy security checklist on the changes in this PR.
Check for: hardcoded secrets, missing auth on API routes, missing input
validation, RLS on new tables, console.log with sensitive data,
unvetted dependencies, error messages that leak internals, and any
issues that Semgrep's code-security or llm-security rules would flag.
```

**Pass criteria**: Zero critical or high findings from both Semgrep and Claude Code review.

---

## Feature Security Review

When a new feature is complete, ask Claude Code:

```
Security review for [feature name]:

1. Trace the data flow from user input to database and back. Identify
   where data is validated, transformed, stored, and returned.
2. Check auth: can an unauthenticated user reach any part of this feature?
3. Check authorization: can User A access User B's data through this feature?
4. Check inputs: what happens if malformed/malicious input is sent?
5. Check outputs: do any responses leak data they shouldn't?
6. Check AI calls: is PII being sent to AI APIs? Are outputs sanitized?
7. Check dependencies: were any new packages added? Are they vetted?
8. Check error handling: do errors leak stack traces or internal paths?
```

**Pass criteria**: All questions answered satisfactorily, no unresolved findings.

---

## Initial Security Baseline (New Projects)

When starting a new project, verify these are in place before writing any features:

```
New project security baseline check:

1. .gitignore includes .env*, node_modules, .next, dist
2. Environment variables are configured (not hardcoded)
3. Supabase RLS is enabled on all existing tables
4. Auth provider is configured (not custom-built)
5. Security headers are configured in middleware or next.config
6. CORS is set to explicit origins (not wildcard)
7. pnpm-lock.yaml is committed
8. Structured logging is set up
9. Error handling returns generic messages to clients
10. AI API accounts have billing limits configured
```

---

## Monthly Full Audit

Run once per month. Document findings in a report.

### Step 1: Semgrep Full Scan
```bash
npx semgrep scan --config auto --severity ERROR --severity WARNING
```
Review all findings. Fix critical/high immediately. Document medium/low for follow-up.

### Step 2: Secrets Scan
```
Search the entire codebase for potential hardcoded secrets:
- API keys, tokens, passwords in any file
- .env files that shouldn't be committed
- Secrets in comments or documentation
- NEXT_PUBLIC_ variables that shouldn't be public
```

### Step 3: Dependency Audit
```bash
pnpm audit
pnpm outdated
```
Review results. Fix critical/high vulnerabilities. Plan updates for outdated packages.

### Step 4: Supabase RLS Audit
```
List every Supabase table and verify:
- RLS is enabled
- Policies exist and are appropriate
- No overly permissive policies (e.g., allowing all reads)
- No SECURITY DEFINER functions without justification
```

### Step 5: API Surface Audit
```
List every API route in the project:
- Verify each has authentication
- Verify input validation on each
- Verify error handling doesn't leak internals
- Check for rate limiting on public endpoints
```

### Step 6: Environment & Access Review
```
Check Vercel dashboard:
- Environment variable scoping (production vs preview vs development)
- Deployment protection settings
- Team access (who has deploy permissions?)

Check Supabase dashboard:
- Who has dashboard access?
- Are any API keys exposed in logs or client code?
- Database backup status

Check GitHub:
- Branch protection rules
- Who has write access?
```

### Step 7: AI & Cost Review
```
Review AI API dashboards:
- Current monthly spend vs budget
- Usage trends (any spikes?)
- Billing alerts configured?
- Per-user limits in place?
```

### Step 8: Generate Report
Document findings in this format:

```markdown
# Security Audit Report — [Project Name]
**Date**: YYYY-MM-DD
**Auditor**: [Name]
**Scope**: Full monthly audit

## Executive Summary
[2-3 sentences on overall security posture]

## Findings

### Critical
[List with description, location, and fix recommendation]

### High
[List with description, location, and fix recommendation]

### Medium
[List with description, location, and fix recommendation]

### Low
[List with description, location, and fix recommendation]

## Actions Taken
[What was fixed during the audit]

## Open Items
[What needs follow-up, with owners and deadlines]
```

---

## Presenting to Engineering

When engineering reviews our code, proactively share:

1. **Semgrep scan results** — this is the tool they already use and trust. Showing clean Semgrep output on our PRs speaks their language immediately.
2. **The latest monthly audit report** — shows we're doing systematic reviews
3. **The CLAUDE.md security rules** — shows we have enforceable standards
4. **The pre-deploy checklist results** — shows every PR was reviewed
5. **Dependency audit results** — shows we're managing supply chain risk

**Why Semgrep is the key to this conversation:** Engineering already trusts Semgrep. By running the same Semgrep rules they use (via `semgrep/skills`) as part of our AI-assisted workflow, we're applying their standards at development time — not just at review time. This shifts the conversation from "you need us to review everything" to "we're already running your tools, here are the results."

---

## Escalation

Some things still need engineering team review:

- **Custom cryptography** — never build it, but if we somehow need it, escalate
- **Payment processing changes** — PCI compliance requires expert review
- **Infrastructure changes** — DNS, CDN, networking configuration
- **Major auth flow changes** — new auth providers, SSO integration
- **Compliance questions** — GDPR data requests, legal requirements

These are not failures of our process — they're appropriate boundaries. The goal is to handle 90% of security reviews ourselves and escalate the 10% that truly needs expert eyes.
