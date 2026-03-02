# Fleet Operating Standards
**ALL agents read this on clock-in. No exceptions.**

## Check-In Protocol
- **Clock in:** `comms clock-in "role"` — every session start
- **Task start:** `comms send <channel> "starting task N: title"`
- **Task done:** `comms result <channel> "task N done" --data '{"output":"filepath"}'`
- **Blocked:** `comms phone-home "blocked - need X" --data '{"blocked_on":"description"}'`
- **Error:** `comms error <channel> "what failed" --data '{"tried":"what you attempted"}'`
- **Clock out:** `comms clock-out "session complete"`
- **10 min rule:** If you've been working 10+ minutes with no check-in, you've gone dark. Check in.

## Git Discipline
- Commit BEFORE moving to next task. Don't accumulate uncommitted changes.
- Commit messages: `type: description` (feat:, fix:, docs:, refactor:, test:)
- Push after each logical unit. Don't hoard.
- NEVER: commit secrets, force push main, commit untested code, go idle with uncommitted changes.

## Learn From Mistakes (ZERO TOLERANCE for repeats)
After ANY bug, failure, or correction:
1. Document what happened, why, and the fix
2. Write a clear "never do X, always do Y" rule
3. `comms send <channel> "lesson learned: description" --data '{"rule":"never/always statement"}'`
4. Check your lessons at session start

Known fleet lessons:
- CSV work codes have NO leading zeros ("270" not "0270"). Verify data format BEFORE filtering.
- FastAPI route handlers appear "DEAD" by grep — they're framework-called. Know your framework.
- Verify row counts with `wc -l` before analysis. If count doesn't match expectations, STOP.

## Quality Gates (before marking ANY task COMPLETE)
1. Verify output exists: `ls -la {output_file}`
2. Verify non-empty: `wc -l {output_file}`
3. Spot-check: read 5-10 lines, do numbers make sense?
4. Cross-reference: verify formats match external data
5. Run the code: execute SQL/Python/bash and show output

Data analysis gates:
- Row counts: verify with `wc -l` independently
- Column names: `head -1` to check exact names
- Key metrics: sanity-check against known values
- NULL handling: always report NULL counts

## Stay In Your Lane
| Agent | Strengths | Avoid |
|-------|-----------|-------|
| Claude Code | Architecture, complex code, protocol work, multi-file refactors | Bulk scanning (slow, expensive) |
| Gemini CLI | Fast scanning, data analysis, auditing, report generation | Complex protocol reverse engineering |
| OpenClaw | Orchestration, automation | Deep domain work |

If a task doesn't match your strengths, escalate:
`comms error <channel> "outside my lane - recommending reassignment to X"`

## Escalation
3 failed attempts on the same problem = STOP and escalate.
`comms error <channel> "escalation: problem. tried: X, Y, Z. need: what would unblock"`

## TL;DR
Check in. Push your work. Learn from mistakes. Verify output. Stay in your lane. No silent failures.
