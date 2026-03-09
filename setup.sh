#!/bin/bash
# ============================================================
# Security Playbook Setup
# Run this in any project directory to apply all security layers.
# Usage: bash /path/to/security-playbook/setup.sh
#
# All CI checks run as WARNINGS by default (non-blocking).
# Nothing prevents you from building, committing, or deploying.
# ============================================================

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'

PLAYBOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

echo ""
echo -e "${BOLD}Security Playbook Setup${NC}"
echo -e "Project: ${BLUE}$PROJECT_NAME${NC}"
echo -e "Directory: ${BLUE}$PROJECT_DIR${NC}"
echo ""

# ---- Preflight checks ----

if [ ! -d ".git" ]; then
  echo -e "${RED}ERROR: Not a git repository. Run this from a project root with git init'd.${NC}"
  exit 1
fi

# ---- Helper ----

created_files=()

write_file() {
  local filepath="$1"
  local dir="$(dirname "$filepath")"
  mkdir -p "$dir"
  if [ -f "$filepath" ]; then
    echo -e "  ${YELLOW}EXISTS${NC} $filepath (skipped)"
    return 1
  fi
  return 0
}

track() {
  created_files+=("$1")
  echo -e "  ${GREEN}CREATED${NC} $1"
}

# ============================================================
echo -e "${BOLD}[1/8] GitHub Actions: Security Checks${NC}"
# ============================================================

if write_file ".github/workflows/security.yml"; then
cat > .github/workflows/security.yml << 'WORKFLOW'
name: Security Checks

# Runs on every PR and push to main.
# All checks are ADVISORY (non-blocking) by default.
# They report findings as warnings in the PR, but do NOT prevent merging.
# To make any check blocking, remove its "continue-on-error: true" line.

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
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
        with:
          fetch-depth: 0
      - uses: gitleaks/gitleaks-action@ff98106e4c7b2bc287b24eaf42907196329070c7 # v2.3.9
        id: gitleaks
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      - name: Summary
        if: always()
        run: |
          echo "## Secret Scanning Results" >> $GITHUB_STEP_SUMMARY
          if [ "${{ steps.gitleaks.outcome }}" = "success" ]; then
            echo "✅ No secrets detected" >> $GITHUB_STEP_SUMMARY
          else
            echo "⚠️ Potential secrets found — review gitleaks output above" >> $GITHUB_STEP_SUMMARY
          fi

  dependency-audit:
    name: Dependency Audit
    runs-on: ubuntu-latest
    continue-on-error: true
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4.4.0
        with:
          node-version: 20
      - name: Detect package manager and audit
        run: |
          echo "## Dependency Audit Results" >> $GITHUB_STEP_SUMMARY
          if [ -f "pnpm-lock.yaml" ]; then
            npm install -g pnpm
            pnpm install --frozen-lockfile
            pnpm audit --audit-level=high 2>&1 | tee audit-output.txt || true
          elif [ -f "yarn.lock" ]; then
            yarn install --frozen-lockfile
            yarn audit --level high 2>&1 | tee audit-output.txt || true
          elif [ -f "package-lock.json" ]; then
            npm ci
            npm audit --audit-level=high 2>&1 | tee audit-output.txt || true
          else
            echo "⚠️ No lockfile found — skipping dependency audit" >> $GITHUB_STEP_SUMMARY
            exit 0
          fi
          if grep -qiE "found 0 vulnerabilities|0 vulnerabilities found" audit-output.txt; then
            echo "✅ No high/critical vulnerabilities found" >> $GITHUB_STEP_SUMMARY
          else
            echo "⚠️ Vulnerabilities found — review details below" >> $GITHUB_STEP_SUMMARY
            echo '```' >> $GITHUB_STEP_SUMMARY
            cat audit-output.txt >> $GITHUB_STEP_SUMMARY
            echo '```' >> $GITHUB_STEP_SUMMARY
          fi

  semgrep:
    name: Semgrep Static Analysis
    runs-on: ubuntu-latest
    continue-on-error: true
    container:
      image: semgrep/semgrep
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - name: Run Semgrep
        run: |
          semgrep scan --config auto --severity ERROR --severity WARNING --json > semgrep-results.json 2>&1 || true
          FINDINGS=$(cat semgrep-results.json | python3 -c "import sys,json; r=json.load(sys.stdin); print(len(r.get('results',[])))" 2>/dev/null || echo "0")
          echo "## Semgrep Results" >> $GITHUB_STEP_SUMMARY
          if [ "$FINDINGS" = "0" ]; then
            echo "✅ No security findings" >> $GITHUB_STEP_SUMMARY
          else
            echo "⚠️ Found $FINDINGS security issue(s) — review in PR checks" >> $GITHUB_STEP_SUMMARY
            semgrep scan --config auto --severity ERROR --severity WARNING 2>&1 | tail -50 >> $GITHUB_STEP_SUMMARY || true
          fi
        env:
          SEMGREP_APP_TOKEN: ${{ secrets.SEMGREP_APP_TOKEN }}

  env-check:
    name: Environment Safety
    runs-on: ubuntu-latest
    continue-on-error: true
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2

      - name: Security environment checks
        run: |
          echo "## Environment Safety" >> $GITHUB_STEP_SUMMARY
          ISSUES=0

          # Check for .env files
          ENVFILES=$(find . -name '.env' -o -name '.env.local' -o -name '.env.production' | grep -v node_modules | grep -v .env.example || true)
          if [ -n "$ENVFILES" ]; then
            echo "⚠️ **Found .env files that should not be committed:**" >> $GITHUB_STEP_SUMMARY
            echo "$ENVFILES" >> $GITHUB_STEP_SUMMARY
            ISSUES=$((ISSUES+1))
          fi

          # Check for service_role in app code
          MATCHES=$(grep -r "service_role" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" -l . | grep -v node_modules | grep -v migrations | grep -v supabase/migrations | grep -v "*.test.*" | grep -v "__tests__" || true)
          if [ -n "$MATCHES" ]; then
            echo "⚠️ **Found service_role references in application code:**" >> $GITHUB_STEP_SUMMARY
            echo "$MATCHES" >> $GITHUB_STEP_SUMMARY
            ISSUES=$((ISSUES+1))
          fi

          # Check for NEXT_PUBLIC_ secrets
          MATCHES=$(grep -rn "NEXT_PUBLIC_.*SECRET\|NEXT_PUBLIC_.*KEY.*SERVICE\|NEXT_PUBLIC_.*PASSWORD\|NEXT_PUBLIC_.*TOKEN" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.env*" . | grep -v node_modules || true)
          if [ -n "$MATCHES" ]; then
            echo "⚠️ **Found potential secrets with NEXT_PUBLIC_ prefix:**" >> $GITHUB_STEP_SUMMARY
            echo "$MATCHES" >> $GITHUB_STEP_SUMMARY
            ISSUES=$((ISSUES+1))
          fi

          # Check for error message leakage in API responses
          # Looks for error.message/error.stack in API route files (not in logging statements)
          MATCHES=$(grep -rn "error\.message\|error\.stack\|err\.message\|err\.stack" --include="*.ts" --include="*.tsx" --include="*.js" . | grep -v node_modules | grep -v "console\.\|logger\.\|log\.\|\/\/" || true)
          if [ -n "$MATCHES" ]; then
            echo "⚠️ **API responses may leak error details to clients:**" >> $GITHUB_STEP_SUMMARY
            echo '```' >> $GITHUB_STEP_SUMMARY
            echo "$MATCHES" >> $GITHUB_STEP_SUMMARY
            echo '```' >> $GITHUB_STEP_SUMMARY
            ISSUES=$((ISSUES+1))
          fi

          if [ $ISSUES -eq 0 ]; then
            echo "✅ All environment checks passed" >> $GITHUB_STEP_SUMMARY
          fi
WORKFLOW
track ".github/workflows/security.yml"
fi

# ============================================================
echo -e "${BOLD}[2/8] Dependabot: Automated Dependency Updates${NC}"
# ============================================================

if write_file ".github/dependabot.yml"; then
cat > .github/dependabot.yml << 'DEPENDABOT'
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
DEPENDABOT
track ".github/dependabot.yml"
fi

# ============================================================
echo -e "${BOLD}[3/8] CLAUDE.md Security Rules${NC}"
# ============================================================

CLAUDE_DIR=".claude"
CLAUDE_FILE="$CLAUDE_DIR/CLAUDE.md"
SECURITY_MARKER="## Security (Enforced on All Projects)"

mkdir -p "$CLAUDE_DIR"

SECURITY_RULES='
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
- Select only needed columns. Avoid `select('"'"'*'"'"')` in production code.

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
Do NOT skip steps 7-9. CI is the primary safety net for this project — there are no pre-commit hooks or branch protection blocking insecure code. If you skip the CI review, vulnerabilities ship undetected.'

if [ -f "$CLAUDE_FILE" ]; then
  if grep -q "$SECURITY_MARKER" "$CLAUDE_FILE" 2>/dev/null; then
    echo -e "  ${YELLOW}EXISTS${NC} $CLAUDE_FILE already has security rules (skipped)"
  else
    echo "$SECURITY_RULES" >> "$CLAUDE_FILE"
    track "$CLAUDE_FILE (appended security rules)"
  fi
else
  echo "$SECURITY_RULES" > "$CLAUDE_FILE"
  track "$CLAUDE_FILE"
fi

# ============================================================
echo -e "${BOLD}[4/8] .gitignore Security Entries${NC}"
# ============================================================

GITIGNORE_ENTRIES=(
  ".env"
  ".env.local"
  ".env.production"
  ".env.*.local"
)

if [ -f ".gitignore" ]; then
  added=0
  for entry in "${GITIGNORE_ENTRIES[@]}"; do
    if ! grep -qxF "$entry" .gitignore; then
      echo "$entry" >> .gitignore
      added=1
    fi
  done
  if [ $added -eq 1 ]; then
    track ".gitignore (added .env exclusions)"
  else
    echo -e "  ${YELLOW}EXISTS${NC} .gitignore already has .env exclusions"
  fi
else
  printf '%s\n' "node_modules" ".next" "dist" ".env" ".env.local" ".env.production" ".env.*.local" > .gitignore
  track ".gitignore"
fi

# ============================================================
echo -e "${BOLD}[5/8] Semgrep Skills${NC}"
# ============================================================

if command -v npx &> /dev/null; then
  if [ -d ".skills" ] || [ -f "skills.json" ] || [ -d ".agents/skills" ] || [ -f "skills-lock.json" ]; then
    echo -e "  ${YELLOW}EXISTS${NC} Semgrep Skills appears to be installed (skipped)"
  else
    echo -e "  ${BLUE}INSTALLING${NC} semgrep/skills..."
    npx skills add semgrep/skills -y 2>/dev/null && track "semgrep/skills" || echo -e "  ${YELLOW}SKIPPED${NC} npx skills add failed (install manually: npx skills add semgrep/skills -y)"
  fi
else
  echo -e "  ${YELLOW}SKIPPED${NC} npx not found — install Node.js, then run: npx skills add semgrep/skills"
fi

# ============================================================
echo -e "${BOLD}[6/8] Gitleaks Config (Optional)${NC}"
# ============================================================

if write_file ".gitleaks.toml"; then
cat > .gitleaks.toml << 'GITLEAKS'
# Gitleaks configuration
# Run manually: gitleaks detect --source . --verbose
# This file reduces false positives. Add paths/patterns to ignore below.

title = "gitleaks config"

[allowlist]
  paths = [
    '''node_modules''',
    '''pnpm-lock.yaml''',
    '''\.test\.''',
    '''__tests__''',
    '''\.spec\.''',
    '''\.example''',
  ]
GITLEAKS
track ".gitleaks.toml"
fi

# ============================================================
echo -e "${BOLD}[7/8] Multi-Agent Security Rules (Codex, Cursor)${NC}"
# ============================================================

# Build the shared security rules content (agent-agnostic format)
AGENT_SECURITY_RULES='# Security Rules

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
- Select only needed columns. Avoid `select('"'"'*'"'"')` in production code.

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

Do NOT skip steps 7-9. There are no pre-commit hooks or branch protection on this project — CI is the ONLY automated safety net. If you skip the CI review, vulnerabilities ship to production undetected.'

# Write AGENTS.md (OpenAI Codex)
AGENTS_FILE="AGENTS.md"
AGENTS_MARKER="# Security Rules"

if [ -f "$AGENTS_FILE" ]; then
  if grep -q "$AGENTS_MARKER" "$AGENTS_FILE" 2>/dev/null; then
    echo -e "  ${YELLOW}EXISTS${NC} $AGENTS_FILE already has security rules (skipped)"
  else
    echo "" >> "$AGENTS_FILE"
    echo "$AGENT_SECURITY_RULES" >> "$AGENTS_FILE"
    track "$AGENTS_FILE (appended security rules)"
  fi
else
  echo "$AGENT_SECURITY_RULES" > "$AGENTS_FILE"
  track "$AGENTS_FILE"
fi

# Write .cursorrules (Cursor)
CURSOR_FILE=".cursorrules"
CURSOR_MARKER="# Security Rules"

if [ -f "$CURSOR_FILE" ]; then
  if grep -q "$CURSOR_MARKER" "$CURSOR_FILE" 2>/dev/null; then
    echo -e "  ${YELLOW}EXISTS${NC} $CURSOR_FILE already has security rules (skipped)"
  else
    echo "" >> "$CURSOR_FILE"
    echo "$AGENT_SECURITY_RULES" >> "$CURSOR_FILE"
    track "$CURSOR_FILE (appended security rules)"
  fi
else
  echo "$AGENT_SECURITY_RULES" > "$CURSOR_FILE"
  track "$CURSOR_FILE"
fi

# ============================================================
echo -e "${BOLD}[8/8] CLAUDE.md — CI Review Commands${NC}"
# ============================================================

# Append Claude-specific CI commands to CLAUDE.md
CI_COMMANDS_MARKER="### CI Review Commands"
CI_COMMANDS='
### CI Review Commands

Use these commands to complete steps 7-9 of the Pre-Deploy Check above:
```bash
# Step 7: Check if security workflow finished
gh pr checks

# Step 8: Read the security results
gh run view $(gh run list --workflow=security.yml --limit=1 --json databaseId -q ".[0].databaseId") --log-failed

# If no failures shown, check the full log for warnings:
gh run view $(gh run list --workflow=security.yml --limit=1 --json databaseId -q ".[0].databaseId") --log 2>&1 | grep -i "warning\|⚠️\|found.*vulnerabilit\|found.*issue\|found.*secret"
```'

if grep -q "$CI_COMMANDS_MARKER" "$CLAUDE_FILE" 2>/dev/null; then
  echo -e "  ${YELLOW}EXISTS${NC} $CLAUDE_FILE already has CI review commands (skipped)"
else
  echo "$CI_COMMANDS" >> "$CLAUDE_FILE"
  track "$CLAUDE_FILE (appended CI review commands)"
fi

# ============================================================
echo ""
echo -e "${BOLD}${GREEN}Setup complete.${NC}"
echo ""
# ============================================================

if [ ${#created_files[@]} -gt 0 ]; then
  echo -e "${BOLD}Files created/modified:${NC}"
  for f in "${created_files[@]}"; do
    echo "  - $f"
  done
  echo ""
fi

echo -e "${BOLD}What happens now:${NC}"
echo ""
echo "  CI security checks will run on every PR as ${YELLOW}warnings${NC}."
echo "  They will NOT block merging or deploying."
echo "  Results appear in the PR's 'Checks' tab and job summary."
echo ""
echo "  AI agent rules are installed for:"
echo "    - Claude Code (.claude/CLAUDE.md)"
echo "    - OpenAI Codex (AGENTS.md)"
echo "    - Cursor (.cursorrules)"
echo "  Each agent will follow security rules AND check CI results after PRs."
echo ""
echo "  Dependabot will open PRs for vulnerable dependencies automatically."
echo "  Merge them when convenient — they won't block anything."
echo ""

echo -e "${BOLD}Optional (when ready to enforce):${NC}"
echo ""
echo "  To make a specific check BLOCKING (fails the PR):"
echo "    Edit .github/workflows/security.yml"
echo "    Remove 'continue-on-error: true' from that job"
echo ""
echo "  To add a local pre-commit secret scan:"
echo "    brew install gitleaks"
echo "    brew install pre-commit"
echo "    Create .pre-commit-config.yaml with gitleaks hook"
echo "    pre-commit install"
echo ""
echo "  To require PRs for main branch:"
echo "    GitHub repo → Settings → Branches → Add rule for 'main'"
echo ""
echo -e "  ${BLUE}Playbook:${NC} $PLAYBOOK_DIR/SECURITY-PLAYBOOK.md"
echo -e "  ${BLUE}MCP integrations:${NC} $PLAYBOOK_DIR/APPENDIX-MCP-INTEGRATIONS.md"
echo -e "  ${BLUE}Lessons learned:${NC} $PLAYBOOK_DIR/LESSONS-LEARNED.md"
echo ""
