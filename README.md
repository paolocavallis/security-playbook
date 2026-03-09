# Security Playbook for AI-Assisted Development

One-command security setup for any project using AI coding tools (Claude Code, Codex, Cursor, etc.).

## Quick Start

```bash
cd /path/to/your-project
bash ~/Documents/security-playbook/setup.sh
```

Or, after publishing to npm:

```bash
npx @graphite-bi/security-playbook
```

## What It Does

`setup.sh` creates 8 things in your project — none of them block builds, deploys, or merges:

| File | Purpose |
|------|---------|
| `.github/workflows/security.yml` | CI security checks (non-blocking warnings) |
| `.github/dependabot.yml` | Auto-updates vulnerable dependencies |
| `.claude/CLAUDE.md` | Security rules for Claude Code |
| `AGENTS.md` | Security rules for OpenAI Codex |
| `.cursorrules` | Security rules for Cursor |
| `.gitignore` | Blocks `.env` files from commits |
| `.gitleaks.toml` | Gitleaks false-positive config |
| Semgrep Skills | Static analysis knowledge for AI agents |

## CI Security Checks

Four checks run on every PR as **advisory warnings** (never blocking):

- **Secret Scanning** (gitleaks) — leaked API keys, tokens, passwords
- **Dependency Audit** (npm/pnpm/yarn) — vulnerable packages
- **Semgrep** — insecure code patterns (OWASP Top 10)
- **Environment Safety** — `.env` files, `service_role` in app code, `NEXT_PUBLIC_` secrets, `error.message` leakage

## Documentation

- `SECURITY-PLAYBOOK.md` — Full reference (10 security domains)
- `SECURITY-REVIEW-PROCESS.md` — How to run security reviews
- `LESSONS-LEARNED.md` — Anti-fragility feedback loop
- `APPENDIX-MCP-INTEGRATIONS.md` — Google, Slack, BigQuery, GitHub, AWS rules
- `CI-SECURITY-SETUP.md` — Phase 2 enforcement guide
