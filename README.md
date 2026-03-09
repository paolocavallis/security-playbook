# Security Playbook for AI-Assisted Development

One command to set up CI security checks, AI agent rules, and dependency monitoring on any project.

No blockers. No hooks. No friction.

## Quick Start

```bash
cd /path/to/your-project
bash /path/to/security-playbook/setup.sh
```

That's it. Run it once, security runs forever.

## How It Works

```
setup.sh runs in your project
         │
         ├─→ .github/workflows/security.yml    CI checks on every PR (warnings only)
         ├─→ .github/dependabot.yml             Auto-updates vulnerable dependencies
         ├─→ .claude/CLAUDE.md                  Security rules for Claude Code
         ├─→ AGENTS.md                          Security rules for Codex
         ├─→ .cursorrules                       Security rules for Cursor
         ├─→ .gitignore                         Blocks .env files from commits
         ├─→ .gitleaks.toml                     Secret scanner config
         └─→ Semgrep Skills                     Static analysis for AI agents
```

## CI: 4 Security Checks on Every PR

All checks are **advisory** — they flag issues but never block merging or deploying.

```
  PR opened
     │
     ▼
┌─────────────┐  ┌──────────────────┐  ┌─────────┐  ┌────────────────────┐
│ Secret Scan │  │ Dependency Audit │  │ Semgrep │  │ Environment Safety │
│  (gitleaks) │  │ (npm/pnpm/yarn)  │  │ (OWASP) │  │  (.env, secrets)   │
└──────┬──────┘  └────────┬─────────┘  └────┬────┘  └─────────┬──────────┘
       │                  │                  │                 │
       ▼                  ▼                  ▼                 ▼
   ✅ or ⚠️           ✅ or ⚠️          ✅ or ⚠️          ✅ or ⚠️
       │                  │                  │                 │
       └──────────────────┴──────────────────┴─────────────────┘
                                  │
                                  ▼
                    Results in PR job summary
                    AI agents read & fix warnings
```

## AI Agent Integration

Your AI coding tool automatically follows security rules and reviews CI results:

| Agent | Reads | What It Does |
|-------|-------|-------------|
| Claude Code | `.claude/CLAUDE.md` | Follows rules + runs `gh pr checks` to review CI |
| Codex | `AGENTS.md` | Follows rules + checks PR job summaries |
| Cursor | `.cursorrules` | Follows rules + checks PR job summaries |

Each agent's pre-deploy checklist includes reviewing CI warnings and fixing them before reporting a task as complete.

## Anti-Fragility Loop

Every security finding strengthens the system:

```
Finding → LESSONS-LEARNED.md → New rule in CLAUDE.md or new CI check → Immune
```

## Docs

| File | What |
|------|------|
| [`SECURITY-PLAYBOOK.md`](SECURITY-PLAYBOOK.md) | Full reference — 10 security domains, 50+ rules |
| [`CI-SECURITY-SETUP.md`](CI-SECURITY-SETUP.md) | CI workflow details and enforcement options |
| [`SECURITY-REVIEW-PROCESS.md`](SECURITY-REVIEW-PROCESS.md) | Monthly audit process |
| [`LESSONS-LEARNED.md`](LESSONS-LEARNED.md) | Finding log and feedback loop |
| [`APPENDIX-MCP-INTEGRATIONS.md`](APPENDIX-MCP-INTEGRATIONS.md) | Rules for Google, Slack, BigQuery, GitHub, AWS |

## License

MIT
