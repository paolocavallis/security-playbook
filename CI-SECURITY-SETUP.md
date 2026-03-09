# Phase 2: CI Security Enforcement

> Move from "please remember to check" to "the code cannot ship if it fails."

---

## Overview

Phase 1 (the playbook) gives you standards and manual processes.
Phase 2 makes them automatic. These checks run on every PR and block merging if they fail.

**Time to set up:** ~1 hour per project, then it runs forever.

---

## 1. GitHub Actions: Security Gate

Create `.github/workflows/security.yml` in your project:

```yaml
name: Security Checks

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  secrets-scan:
    name: Secret Scanning
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
        with:
          fetch-depth: 0
      - uses: gitleaks/gitleaks-action@ff98106e4c7b2bc287b24eaf42907196329070c7 # v2.3.9
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  dependency-audit:
    name: Dependency Audit
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - uses: pnpm/action-setup@fe02b34f77f8bc703c22d82ef19c587e31793dd0 # v4.0.0
      - uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4.4.0
        with:
          node-version: 20
          cache: 'pnpm'
      - run: pnpm install --frozen-lockfile
      - run: pnpm audit --audit-level=high
        continue-on-error: false

  semgrep:
    name: Semgrep Static Analysis
    runs-on: ubuntu-latest
    container:
      image: semgrep/semgrep
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - run: semgrep scan --config auto --error --severity ERROR --severity WARNING
        env:
          SEMGREP_APP_TOKEN: ${{ secrets.SEMGREP_APP_TOKEN }}

  env-check:
    name: Environment Safety
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2

      - name: Check for .env files that should not be committed
        run: |
          ENVFILES=$(find . -name '.env' -o -name '.env.local' -o -name '.env.production' | grep -v node_modules | grep -v .env.example || true)
          if [ -n "$ENVFILES" ]; then
            echo "::error::Found .env files that should not be committed:"
            echo "$ENVFILES"
            exit 1
          fi

      - name: Check for service_role key in non-migration code
        run: |
          MATCHES=$(grep -r "service_role" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" -l . | grep -v node_modules | grep -v migrations | grep -v supabase/migrations || true)
          if [ -n "$MATCHES" ]; then
            echo "::error::Found service_role references in application code:"
            echo "$MATCHES"
            exit 1
          fi

      - name: Check for NEXT_PUBLIC_ secrets
        run: |
          MATCHES=$(grep -rn "NEXT_PUBLIC_.*SECRET\|NEXT_PUBLIC_.*KEY.*SERVICE\|NEXT_PUBLIC_.*PASSWORD\|NEXT_PUBLIC_.*TOKEN" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.env*" . | grep -v node_modules || true)
          if [ -n "$MATCHES" ]; then
            echo "::error::Found potential secrets with NEXT_PUBLIC_ prefix:"
            echo "$MATCHES"
            exit 1
          fi
```

### What each job does:

| Job | What It Catches | Blocks PR? |
|-----|----------------|------------|
| `secrets-scan` | API keys, tokens, passwords in code or git history | Yes |
| `dependency-audit` | Known CVEs in npm packages (high/critical) | Yes |
| `semgrep` | OWASP Top 10 vulnerabilities, insecure patterns | Yes |
| `env-check` | Committed .env files, service_role in app code, secrets in NEXT_PUBLIC_ | Yes |

---

## 2. Pre-commit Hook: Local Secrets Scan

Catches secrets before they even reach git history. Add to your project:

```bash
# Install gitleaks
brew install gitleaks

# Create pre-commit hook
cat > .git/hooks/pre-commit << 'HOOK'
#!/bin/sh
gitleaks protect --staged --verbose
if [ $? -ne 0 ]; then
  echo ""
  echo "ERROR: gitleaks found secrets in staged files."
  echo "Remove the secrets and try again."
  exit 1
fi
HOOK
chmod +x .git/hooks/pre-commit
```

Or use a shared hook config with `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.24.0
    hooks:
      - id: gitleaks
```

Then: `pip install pre-commit && pre-commit install`

---

## 3. Dependabot / Renovate: Automated Dependency Updates

### Option A: GitHub Dependabot (simpler)

Create `.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
    labels:
      - "dependencies"
      - "security"
    # Group minor/patch updates to reduce PR noise
    groups:
      minor-and-patch:
        update-types:
          - "minor"
          - "patch"
```

### Option B: Renovate (more control, better for monorepos)

Create `renovate.json`:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:recommended",
    "group:monorepos",
    ":automergeMinor",
    ":automergePatch",
    "security:openssf-scorecard"
  ],
  "packageRules": [
    {
      "matchUpdateTypes": ["major"],
      "automerge": false,
      "labels": ["dependencies", "major"]
    },
    {
      "matchUpdateTypes": ["minor", "patch"],
      "automerge": true,
      "labels": ["dependencies", "auto-merge"]
    }
  ]
}
```

**Recommendation:** Start with Dependabot. Switch to Renovate if you find Dependabot too noisy or need monorepo grouping.

---

## 4. Branch Protection Rules

Go to GitHub repo → Settings → Branches → Add rule for `main`:

- [x] Require a pull request before merging
- [x] Require status checks to pass before merging
  - Select: `secrets-scan`, `dependency-audit`, `semgrep`, `env-check`
- [x] Require branches to be up to date before merging
- [x] Do not allow bypassing the above settings

This means: **no one can push directly to main, and all 4 security checks must pass.**

---

## 5. Semgrep App (Optional but Recommended)

For a dashboard of findings across all projects:

1. Sign up at [semgrep.dev](https://semgrep.dev) (free tier covers most needs)
2. Get a `SEMGREP_APP_TOKEN` from the dashboard
3. Add it as a GitHub Actions secret
4. Semgrep CI will report findings to the dashboard with trends over time

This gives you **metrics** — how many findings per project, trending up or down, which categories. Useful for presenting to engineering and exec team.

---

## 6. Vercel Deployment Checks

Vercel automatically runs GitHub checks. Combine with the above:

1. In Vercel project settings → Git → Enable "Require status checks"
2. Preview deployments only succeed if the security workflow passes
3. Production deploys are gated on the same checks

---

## Setup Checklist (Per Project)

```
NEW PROJECT CI SECURITY SETUP
===============================

[ ] .github/workflows/security.yml created and committed
[ ] Pre-commit hook installed (gitleaks)
[ ] Dependabot or Renovate configured
[ ] Branch protection rules set on main
[ ] All 4 security checks required for merge
[ ] SEMGREP_APP_TOKEN added to GitHub secrets (if using Semgrep App)
[ ] Vercel deployment gated on security checks
[ ] First PR opened and verified that checks run
```

**Time estimate:** ~1 hour for the first project. ~15 minutes for each subsequent project (copy the workflow file and config).

---

## What This Changes

| Before (Phase 1) | After (Phase 2) |
|-------------------|-----------------|
| "Remember to run Semgrep before deploying" | Semgrep runs automatically on every PR |
| "Don't commit secrets" | gitleaks blocks the commit locally AND in CI |
| "Check for vulnerable dependencies" | pnpm audit fails the PR if high/critical CVEs exist |
| "Don't use service_role in app code" | grep check fails the PR if it's found |
| "Keep dependencies updated" | Dependabot opens PRs automatically |
| "Don't push directly to main" | Branch protection makes it impossible |

The shift: **security is no longer dependent on human memory. It's infrastructure.**
