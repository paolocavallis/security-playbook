# Security Lessons Learned

> **The Rule:** Every entry here MUST result in either a new CLAUDE.md rule OR a new CI check.
> If a lesson doesn't change the system, it's just a note — and notes don't prevent recurrence.

---

## How to Use This File

When a security issue is found — by engineering, by Semgrep, by an audit, by anyone:

1. **Add an entry** below with the date, what happened, and the root cause
2. **Determine the fix category:**
   - **CLAUDE.md rule** → prevents the AI from generating this pattern again
   - **CI check** → blocks the code from shipping even if the AI misses it
   - **Playbook update** → adds to the checklist or audit process
   - **Stack appendix** → adds a stack-specific gotcha
3. **Implement the fix** — don't just document it, ship the change
4. **Mark the status** as IMPLEMENTED with a link to what changed

This file is the engine that makes the security playbook anti-fragile. Every failure strengthens the system.

---

## Template

```markdown
### [YYYY-MM-DD] Short description of the issue

**Found by:** [Engineering review / Semgrep scan / Monthly audit / Production incident / Other]
**Project:** [Project name]
**Severity:** [Critical / High / Medium / Low]

**What happened:**
[Describe the issue in 2-3 sentences]

**Root cause:**
[Why did this happen? What allowed it?]

**Fix applied:**
- [ ] CLAUDE.md rule added: [describe the rule]
- [ ] CI check added: [describe the check]
- [ ] Playbook updated: [describe what changed]
- [ ] Stack appendix updated: [describe what changed]

**Status:** PENDING / IMPLEMENTED
```

---

## Lessons

_No entries yet. The first entry will come from your first security audit or engineering review._

<!--
Example of what a real entry looks like:

### [2026-03-15] Supabase service_role key found in edge function

**Found by:** Engineering code review
**Project:** BI Hub
**Severity:** Critical

**What happened:**
An API route used the service_role key to bypass RLS for a "quick fix" to a permissions
issue. The key was in a server-side function but would have been extractable from the
Vercel function bundle.

**Root cause:**
The AI suggested using service_role when the RLS policy was blocking a query, instead
of fixing the policy. The developer accepted the suggestion without recognizing the risk.

**Fix applied:**
- [x] CLAUDE.md rule added: "When RLS blocks a query, ALWAYS fix the policy. NEVER
      switch to service_role as a workaround. Explain why to the developer."
- [x] CI check added: grep for `service_role` in all non-migration files, fail if found
- [x] Playbook updated: Added to Section 3 common mistakes
- [ ] Stack appendix updated: N/A

**Status:** IMPLEMENTED
-->
