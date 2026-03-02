# HIVE Fleet Operations — Lessons Learned
# Real-world mistakes from 2026-03-02 first live run. Never repeat these.

---

## Session Post-Mortem: 2026-03-02

First real test of the fleet: Claude (architect), Gemini (researcher), Codex (deployer)
working on SignX codebase bugs via shared HIVE channels.

---

## MISTAKES MADE — and why they'll never happen again

---

### MISTAKE 1: Fictional Protocol Commands
**What happened:** Gemini's suggested setup protocol included `comms join`, `comms broadcast`,
`/hive-clock-in`, `gemini clock-in --as researcher`. None of these exist.

**Root cause:** Gemini hallucinated plausible-sounding commands that fit the pattern
of real commands but were never built.

**Cost:** Wasted setup time, confusion about what's real.

**Fix:** PROTOCOL.md now has an explicit "DOES NOT EXIST" section.
agent-runner.sh handles everything the fictional commands were supposed to do.

**Rule:** If a command isn't in comms.sh or this document, it does not exist. Do not try it.

---

### MISTAKE 2: Task-Scoped Prompts → Agents Going Idle
**What happened:** Pasted "do TASK-1" to Claude. Claude did TASK-1 and stopped.
Two other agents sat completely idle for 30+ minutes.

**Root cause:** Prompts were task-scoped ("do this specific thing") not role-scoped
("you are an architect who always finds work"). Agents have no persistent loop.
When the task was done, the context ended.

**Cost:** ~30 minutes of zero throughput from 2 of 3 agents.

**Fix:** Role-based prompts (see ROLE-PROMPTS.md). agent-runner.sh for persistent loops.

**Rule:** Never give an agent a single-task prompt. Always give them their role + "never stop" directive.

---

### MISTAKE 3: Codex Empty Status Cells
**What happened:** Codex posted 7 cells with content like "TASK-3", "deployer",
"codex/deployer", "@claude/architect:" (truncated). Zero actionable content.

**Root cause:** No schema enforcement. Codex was confused about how to use comms.sh.
It was echoing task names as if acknowledging receipt, not actually communicating.

**Specific broken cells:**
- [12:00] codex/deployer | status | "TASK-3"
- [12:11] codex/deployer | status | "TASK-3"
- [12:12] codex/deployer | result | "TASK-3"  ← result cell with no content
- [12:13] codex/deployer | status | "deployer"
- [12:14] codex/deployer | status | "codex/deployer"
- [12:17] codex/deployer | status | "@claude/architect:"  ← truncated, no body
- [12:18] codex/deployer | status | "TASK-6"

**Cost:** Cannot tell from the channel whether Codex did any real work.

**Fix:** PROTOCOL.md schema requires non-empty msg with actual content.
agent-runner.sh validates output before posting.
Codex needs explicit examples of what a valid status/result looks like.

**Rule:** Any cell with msg shorter than 20 characters is a protocol violation.
agent-runner.sh rejects these before writing.

---

### MISTAKE 4: No Dependency Enforcement
**What happened:** TASK-3 explicitly said "After TASK-1+2 are done."
Codex started posting TASK-3 status cells at 11:57 — before TASK-2 was posted at 12:04.

**Root cause:** Dependencies were in the task description text but not enforced
by the protocol. Codex parsed "TASK-3" out of its instructions and started posting
without checking if its dependencies were complete.

**Cost:** Potential for Codex to run calibrate.py on unfixed code, producing wrong baseline.

**Fix:** A2A `depends_on` field in task data. agent-runner.sh checks dependency state
before claiming. BLOCKED cell type for explicit "I'm waiting for X" communication.

**Rule:** If a task has depends_on, the runner will not claim it until all dependencies
reach COMPLETE state. Agents post BLOCKED instead of ghost-posting task names.

---

### MISTAKE 5: CHANNELS_DIR Mismatch
**What happened:** comms.sh was pointing to C:/tools/agent-comms/channels but
symlinks pointed all three agent dirs to C:/Users/Brady.EAGLE/.ai/channels.
Fleet was split — some cells going to old location, some to new.

**Root cause:** comms.sh had a hardcoded path that wasn't updated when the unified
channel directory was created.

**Cost:** Early session cells were in the wrong location. Had to migrate.

**Fix:** comms.sh now uses COMMS_CHANNELS env override with correct default.
CHANNELS_DIR = C:/Users/Brady.EAGLE/.ai/channels

**Rule:** There is exactly ONE canonical channels directory. It is:
  C:/Users/Brady.EAGLE/.ai/channels
Symlinked from: ~/.claude/channels, ~/.gemini/channels, ~/.codex/channels
Never write to the old path. Never create a second channels location.

---

### MISTAKE 6: Duplicate Results
**What happened:** Gemini posted TASK-2 result twice (12:04 and 12:07).
Both cells have slightly different content — Gemini re-ran analysis and posted again.

**Root cause:** No idempotency. No check "have I already posted a result for this task?"
Agent ran twice, posted twice.

**Cost:** Channel noise. Downstream agents don't know which result to trust.

**Fix:** agent-runner.sh tracks processed task IDs in state file. Once a result is
posted for a task_id, that task_id is marked done and never processed again.

**Rule:** One result per task. If a result already exists for a task_id, skip it.

---

### MISTAKE 7: No Formal Agent Identity at Registration
**What happened:** The "unknown" agent clocked out at 11:51 with no identity.
Could be a test session, could be a misconfigured agent. Cannot tell.

**Root cause:** COMMS_AGENT defaulted to "unknown" when not set.

**Fix:** agent-runner.sh exits immediately if COMMS_AGENT is "unknown" or empty.
Clock-in requires a valid identity format: "name/role".

**Rule:** COMMS_AGENT must be set before any comms command. Format: "agent/role".
Agents with identity "unknown" are rejected at clock-in.

---

## WHAT WORKED WELL

### Gemini's Proactive Research Loop
Once given the role-based "never stop" prompt, Gemini completed TASK-2,
self-assigned TASK-4 (variance triage), completed that, self-assigned TASK-5 (RTLT/ILLUM),
completed that — all without being prompted.

This is the target behavior. 10 cells, 6 substantive results. Zero idle time.

**Why it worked:** Role-scoped prompt + capable model + clear output format.

### Claude's Architect Pattern
Claude fixed TASK-1 with full root-cause analysis (248 passed, 0 failed),
then created TASK-4, TASK-5, TASK-6 for the other agents.
True orchestrator behavior — fix what you can, delegate what needs investigation.

### Channel Symlinks
Three agents reading/writing to the same JSONL files via symlinks worked perfectly.
File-based bus requires zero infrastructure. Any CLI tool can participate.

---

## FLEET PERFORMANCE METRICS (session 11:51 - 12:20)

| Agent | Cells Posted | Results | Empty Cells | Idle Time |
|-------|-------------|---------|-------------|-----------|
| claude/architect | 10 | 2 | 0 | ~0 min |
| gemini/researcher | 10 | 6 | 0 | ~0 min |
| codex/deployer | 8 | 1 | 7 | ~25 min |

Gemini and Claude: excellent. Codex: needs agent-runner.sh and better prompting.

---

## OPERATING PROCEDURES

### Starting a New Session

1. Verify channels directory:
   ls C:/Users/Brady.EAGLE/.ai/channels/*.jsonl

2. Start agent-runner in each terminal:
   COMMS_AGENT="gemini/researcher" AGENT_CMD="gemini" \
     bash /c/tools/agent-comms/agent-runner.sh signx-intel

3. Start dashboard:
   bash /c/tools/agent-comms/dashboard/start.sh

4. Post tasks from architect with context_id:
   CTX=$(python -c "import uuid; print(uuid.uuid4())")
   export COMMS_AGENT="claude/architect"
   source /c/tools/agent-comms/comms.sh
   comms task signx-intel "TASK-1 [gemini/researcher] ..."

5. Monitor at http://localhost:7842

### Diagnosing a Stuck Agent

Check for empty cells:
  python -c "
import json
with open('C:/Users/Brady.EAGLE/.ai/channels/signx-intel.jsonl') as f:
    for line in f:
        c = json.loads(line.strip())
        if len(c.get('msg','')) < 20:
            print(c['ts'][:19], c['from'], c['type'], repr(c['msg']))
"

If agent has 3+ empty cells in a row: restart with agent-runner.sh.

### Adding a New Agent

1. Create agent-card.json in agent's config dir
2. Ensure ~/.{agent}/channels symlinks to C:/Users/Brady.EAGLE/.ai/channels
3. Run agent-runner.sh with correct COMMS_AGENT and AGENT_CMD
4. Verify it appears in comms roster

---

## KNOWN LIMITATIONS (build these next)

1. **No dependency graph enforcement** — agent-runner.sh needs to check depends_on
   before claiming. Currently just checks if task is unresolved.

2. **No schema validation** — empty/bad cells get written. Add validation to
   _comms_write() that rejects cells with msg < 20 chars or missing required fields.

3. **Codex CLI output format** — codex output needs to be parsed and formatted
   as a proper result cell. Current agent-runner.sh captures raw stdout.

4. **Dashboard Cloudflare exposure** — server runs on localhost:7842 only.
   Need named Cloudflare tunnel to access from outside the machine.

5. **No context_id threading** — related tasks aren't grouped. Dashboard shows
   flat task list instead of sprint/batch view.

6. **No BLOCKED state handling** — agents try tasks and fail silently instead
   of posting explicit BLOCKED cells with depends_on references.

7. **A2A Agent Cards not wired to router** — router.py still takes a hardcoded
   agents dict. Should read agent-card.json files from ~/.{agent}/ dirs.
