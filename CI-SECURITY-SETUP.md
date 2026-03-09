# Phase 2: CI Security Detection

> Move from "please remember to check" to "CI flags it automatically on every PR."

---

## Overview

Phase 1 (the playbook) gives you standards and manual processes.
Phase 2 makes them automatic. These checks run on every PR and report findings as **warnings** — they do NOT block merging or deploying by default.

**Time to set up:** Run `setup.sh` once. It creates everything below.

---

## 1. GitHub Actions: Security Checks

Created at `.github/workflows/security.yml`:

```yaml
name: Security Checks

# Runs on every PR and push to main.
# All checks are ADVISORY (non-blocking) by default.
# They report findings as warnings in the PR, but do NOT prevent merging.
# To make any check blocking, remove its "continue-on-error: true" line.
#
# All results are written to BOTH stdout (for CLI/agent visibility via
# `gh run view --log`) AND $GITHUB_STEP_SUMMARY (for the web UI).

permissions:
  contents: read

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  secrets-scan:
    name: Secret Scanning
    runs-on: ubuntu-latest
    continue-on-error: true
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
        with:
          fetch-depth: 0
          persist-credentials: false
      - uses: gitleaks/gitleaks-action@ff98106e4c7b2bc287b24eaf42907196329070c7 # v2.3.9
        id: gitleaks
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      - name: Summary
        if: always()
        run: |
          report() { echo "$1" | tee -a $GITHUB_STEP_SUMMARY; }
          report "## Secret Scanning Results"
          if [ "${{ steps.gitleaks.outcome }}" = "success" ]; then
            report "✅ No secrets detected"
          else
            report "⚠️ Potential secrets found — review gitleaks output above"
          fi

  dependency-audit:
    name: Dependency Audit
    runs-on: ubuntu-latest
    continue-on-error: true
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
        with:
          persist-credentials: false
      - uses: actions/setup-node@53b83947a5a98c8d113130e565377fae1a50d02f # v6.3.0
        with:
          node-version: 20
      - name: Detect package manager and audit
        run: |
          report() { echo "$1" | tee -a $GITHUB_STEP_SUMMARY; }
          report "## Dependency Audit Results"
          if [ -f "pnpm-lock.yaml" ]; then
            npm install -g pnpm
            pnpm install --frozen-lockfile --ignore-scripts
            pnpm audit --audit-level=high 2>&1 | tee audit-output.txt || true
          elif [ -f "yarn.lock" ]; then
            yarn install --frozen-lockfile --ignore-scripts
            yarn audit --level high 2>&1 | tee audit-output.txt || true
          elif [ -f "package-lock.json" ]; then
            npm ci --ignore-scripts
            npm audit --audit-level=high 2>&1 | tee audit-output.txt || true
          else
            report "⚠️ No lockfile found — skipping dependency audit"
            exit 0
          fi
          if grep -qiE "found 0 vulnerabilities|0 vulnerabilities found" audit-output.txt; then
            report "✅ No high/critical vulnerabilities found"
          else
            report "⚠️ Vulnerabilities found — review details below"
            echo '```' >> $GITHUB_STEP_SUMMARY
            cat audit-output.txt | tee -a $GITHUB_STEP_SUMMARY
            echo '```' >> $GITHUB_STEP_SUMMARY
          fi

  semgrep:
    name: Semgrep Static Analysis
    runs-on: ubuntu-latest
    continue-on-error: true
    container:
      image: semgrep/semgrep@sha256:50b839b576d76426efd3e5cffda2db0d8c403f53aa76e91d42ccf51485ac336c
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
        with:
          persist-credentials: false
      - name: Run Semgrep
        run: |
          report() { echo "$1" | tee -a $GITHUB_STEP_SUMMARY; }
          semgrep scan --config auto --severity ERROR --severity WARNING --json > semgrep-results.json 2>/dev/null || true
          FINDINGS=$(cat semgrep-results.json | python3 -c "import sys,json; r=json.load(sys.stdin); print(len(r.get('results',[])))" 2>/dev/null || echo "PARSE_ERROR")
          report "## Semgrep Results"
          if [ "$FINDINGS" = "PARSE_ERROR" ]; then
            report "⚠️ Semgrep scan or result parsing failed — review manually"
          elif [ "$FINDINGS" = "0" ]; then
            report "✅ No security findings"
          else
            report "⚠️ Found $FINDINGS security issue(s) — review in PR checks"
            semgrep scan --config auto --severity ERROR --severity WARNING 2>&1 | tail -50 | tee -a $GITHUB_STEP_SUMMARY || true
          fi
        env:
          SEMGREP_APP_TOKEN: ${{ secrets.SEMGREP_APP_TOKEN }}

  env-check:
    name: Environment Safety
    runs-on: ubuntu-latest
    continue-on-error: true
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
        with:
          persist-credentials: false

      - name: Security environment checks
        run: |
          report() { echo "$1" | tee -a $GITHUB_STEP_SUMMARY; }
          report "## Environment Safety"
          ISSUES=0

          # Check for .env files
          ENVFILES=$(find . -name '.env' -o -name '.env.local' -o -name '.env.production' | grep -v node_modules | grep -v .env.example || true)
          if [ -n "$ENVFILES" ]; then
            report "⚠️ Found .env files that should not be committed:"
            echo "$ENVFILES" | tee -a $GITHUB_STEP_SUMMARY
            ISSUES=$((ISSUES+1))
          fi

          # Check for service_role in app code
          MATCHES=$(grep -r "service_role" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" -l . | grep -v node_modules | grep -v migrations | grep -v supabase/migrations | grep -v '\.test\.' | grep -v "__tests__" || true)
          if [ -n "$MATCHES" ]; then
            report "⚠️ Found service_role references in application code:"
            echo "$MATCHES" | tee -a $GITHUB_STEP_SUMMARY
            ISSUES=$((ISSUES+1))
          fi

          # Check for NEXT_PUBLIC_ secrets
          MATCHES=$(grep -rn "NEXT_PUBLIC_.*SECRET\|NEXT_PUBLIC_.*KEY.*SERVICE\|NEXT_PUBLIC_.*PASSWORD\|NEXT_PUBLIC_.*TOKEN" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.env*" . | grep -v node_modules || true)
          if [ -n "$MATCHES" ]; then
            report "⚠️ Found potential secrets with NEXT_PUBLIC_ prefix:"
            echo "$MATCHES" | tee -a $GITHUB_STEP_SUMMARY
            ISSUES=$((ISSUES+1))
          fi

          # Check for error message leakage in API responses
          MATCHES=$(grep -rn "error\.message\|error\.stack\|err\.message\|err\.stack" --include="*.ts" --include="*.tsx" --include="*.js" . | grep -v node_modules | grep -v "console\.\|logger\.\|log\.\|\/\/" || true)
          if [ -n "$MATCHES" ]; then
            report "⚠️ API responses may leak error details to clients:"
            echo "$MATCHES" | tee -a $GITHUB_STEP_SUMMARY
            ISSUES=$((ISSUES+1))
          fi

          if [ $ISSUES -eq 0 ]; then
            report "✅ All environment checks passed"
          fi
```

### What each job does:

| Job | What It Catches | Blocks PR? |
|-----|----------------|------------|
| `secrets-scan` | API keys, tokens, passwords in code or git history | No (warning) |
| `dependency-audit` | Known CVEs in npm packages (high/critical) — auto-detects pnpm/yarn/npm | No (warning) |
| `semgrep` | OWASP Top 10 vulnerabilities, insecure patterns | No (warning) |
| `env-check` | Committed .env files, service_role in app code, NEXT_PUBLIC_ secrets, error.message leakage | No (warning) |

All jobs write results to `$GITHUB_STEP_SUMMARY` so findings appear in the PR job summary for AI agents and developers to review.

**To make any check blocking:** remove `continue-on-error: true` from that job.

---

## 2. Pre-commit Hook (Optional)

Catches secrets before they even reach git history. Not installed by setup.sh — add when ready:

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

## 3. Dependabot: Automated Dependency Updates

Created at `.github/dependabot.yml` by setup.sh:

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
    groups:
      minor-and-patch:
        update-types:
          - "minor"
          - "patch"
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    labels:
      - "dependencies"
      - "ci"
```

---

## 4. Branch Protection Rules (Optional)

When ready to enforce, go to GitHub repo -> Settings -> Branches -> Add rule for `main`:

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

## 6. Vercel Deployment Checks (Optional)

Vercel automatically runs GitHub checks. Combine with the above:

1. In Vercel project settings -> Git -> Enable "Require status checks"
2. Preview deployments only succeed if the security workflow passes
3. Production deploys are gated on the same checks

---

## Setup Checklist (Per Project)

```
NEW PROJECT CI SECURITY SETUP
===============================

[ ] Run setup.sh (creates workflow, dependabot, agent rules, gitignore, gitleaks config)
[ ] First PR opened and verified that checks run
[ ] SEMGREP_APP_TOKEN added to GitHub secrets (if using Semgrep App)

OPTIONAL (when ready to enforce):
[ ] Pre-commit hook installed (gitleaks)
[ ] Branch protection rules set on main
[ ] Vercel deployment gated on security checks
```

**Time estimate:** ~5 minutes with setup.sh. Then it runs forever.

---

## What This Changes

| Before (Phase 1) | After (Phase 2) |
|-------------------|-----------------|
| "Remember to run Semgrep before deploying" | Semgrep runs automatically on every PR |
| "Don't commit secrets" | gitleaks flags secrets in CI (and optionally blocks locally) |
| "Check for vulnerable dependencies" | Audit runs on every PR with auto-detected package manager |
| "Don't use service_role in app code" | env-check flags it in CI |
| "Don't expose error.message in responses" | env-check flags error.message/error.stack in non-logging code |
| "Keep dependencies updated" | Dependabot opens PRs automatically |
| "Don't push directly to main" | Branch protection makes it impossible (when enabled) |

The shift: **security is no longer dependent on human memory. It's infrastructure.**
