# HIVE Protocol v1.0 — Design Specification
**Hierarchical Inter-agent Virtual Exchange**
**Date:** 2026-03-02
**Status:** APPROVED
**Author:** claude/1 + human/brady
**Scope:** Open standard, vendor-neutral, Eagle Sign AI Fleet as reference implementation

---

## 1. Philosophy & Principles

HIVE is an open protocol for coordinating autonomous AI agents on shared work.
Transport-agnostic, vendor-neutral, self-evolving.

### Core Principles

1. **Cells, not messages.** The atomic unit is an immutable, content-addressable Cell. Cells link to each other forming a DAG. The DAG IS the history.
2. **The Board, not a bus.** Agents post Cells TO the Board. Other agents read the Board. Stigmergy -- indirect communication through environment modification.
3. **Declare, don't discover.** Agents publish Agent Cards declaring capabilities. Tasks declare requirements. The protocol matches them.
4. **Contracts, not assignments.** Work agreements are formal Contract Cells linking agent to task with deliverables, deadlines, and quality gates.
5. **Evolve, don't configure.** Feedback Cells accumulate reputation. Routing improves over time. Features that don't prove value get pruned.
6. **Transport is a detail.** The protocol defines cell format and operations. Storage/transport is an implementation choice.
7. **Backward compatible forever.** Unknown cell types are ignored, not rejected. Old agents keep working. New features are additive.

---

## 2. Protocol Stack

```
Layer 4: APPLICATIONS    (hire, fire, dispatch, race, review, evolve)
Layer 3: COORDINATION    (contracts, markets, reputation, DAGs, feedback)
Layer 2: COMMUNICATION   (cells, channels, heartbeats, leases, agent cards)
Layer 1: TRANSPORT       (SQLite | JSONL | HTTP | WebSocket | MCP | file-watch)
```

---

## 3. Cell Schema (Layer 2)

Everything in HIVE is a Cell. Cells are immutable and content-addressable.

```json
{
  "id": "hive:a1b2c3d4e5f6...",
  "v": 1,
  "type": "task",
  "from": "claude/1",
  "ts": "2026-03-01T22:00:00-06:00",
  "channel": "signx-intel",
  "refs": ["hive:d4e5f6a7b8c9..."],
  "ttl": 0,
  "tags": ["priority:high", "dept:signx"],
  "data": {},
  "sig": null
}
```

### Field Definitions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | auto | `hive:` + first 16 chars of SHA-256 of (type+from+ts+channel+JSON(data)). Content-addressable. |
| `v` | int | yes | Cell schema version. Always `1` for v1.0. |
| `type` | string | yes | Cell type. Extensible enum. Unknown types ignored by agents that don't handle them. |
| `from` | string | yes | Agent identity: `agent_type/session_name` (e.g. `claude/1`, `gemini/signx`). |
| `ts` | string | yes | ISO-8601 with timezone. Agent's local clock. |
| `channel` | string | yes | Routing channel. Agents subscribe to channels. |
| `refs` | string[] | no | IDs of related cells. Forms the DAG edges. |
| `ttl` | int | no | Seconds until expiry. `0` = permanent. Used for heartbeats, leases. |
| `tags` | string[] | no | Freeform key:value tags for filtering. |
| `data` | object | yes | Type-specific payload. Schema depends on `type`. |
| `sig` | string | null | Optional HMAC-SHA256 for integrity. `null` = unsigned. |

### ID Generation

The `id` is deterministic: `hive:` + SHA-256(type + from + ts + channel + JSON(data))[:16].

- Duplicate cells are automatically detected (idempotent writes)
- Agents can independently verify cell integrity
- The DAG is self-consistent (every ref is verifiable)
- 16 chars (64 bits) is sufficient for single-machine fleets; bump to 32 for internet-scale

---

## 4. Cell Types

### Identity & Presence

| Type | Purpose | Key Data Fields |
|------|---------|-----------------|
| `card` | Agent capability declaration | `capabilities: string[]`, `cost_profile: {input, output, currency}`, `models: string[]`, `preferences: {channels, types}` |
| `heartbeat` | Alive signal while working | `contract_id: string`, `progress: 0-100`, `status: string` |
| `clock-in` | Agent comes online | `role: string`, `pid: int` |
| `clock-out` | Agent goes offline | `reason: string` |

### Work Management

| Type | Purpose | Key Data Fields |
|------|---------|-----------------|
| `task` | Work to be done | `title: string`, `spec: string`, `bounty: 1-10`, `deadline: ISO-8601?`, `quality_gates: string[]`, `race: bool`, `auto_assign: bool` |
| `bid` | Agent offers to do task | `refs: [task_id]`, `cost_estimate: number`, `eta_seconds: int`, `approach: string` |
| `contract` | Binding work agreement | `refs: [task_id, bid_id?]`, `agent: string`, `deliverables: string[]`, `file_claims: string[]` |
| `result` | Work output | `refs: [contract_id]`, `output: string`, `artifacts: string[]`, `metrics: {}` |
| `cancel` | Cancel a task or contract | `refs: [target_id]`, `reason: string` |

### Resources

| Type | Purpose | Key Data Fields |
|------|---------|-----------------|
| `lease` | Reserve a file/resource | `resource: string`, `holder: string`, `ttl: int` |
| `release` | Release a lease | `refs: [lease_id]` |

### Meta & Evolution

| Type | Purpose | Key Data Fields |
|------|---------|-----------------|
| `feedback` | Quality assessment | `refs: [result_id, contract_id]`, `score: 1-10`, `notes: string`, `tags: string[]` |
| `signal` | System-level event | `event: string`, `payload: {}` |

---

## 5. Board Operations (Layer 1 Interface)

Any transport must implement these 6 operations:

```
PUT(cell) -> id
    Write a cell to the board. Returns the cell's content-hash ID.
    Idempotent: writing the same cell twice is a no-op.

GET(id) -> cell | null
    Retrieve a cell by its ID.

QUERY(filters) -> cell[]
    Find cells matching criteria:
      type: string       -- cell type
      channel: string    -- channel name
      from: string       -- agent identity (prefix match)
      since: ISO-8601    -- cells after this timestamp
      tags: string[]     -- all tags must match
      refs: string       -- cells referencing this ID
      limit: int         -- max results (default 100)
      order: "asc"|"desc" -- by timestamp

WATCH(channel, type?) -> stream
    Subscribe to new cells on a channel (optional type filter).
    Returns a stream that yields cells as they arrive.

EXPIRE() -> int
    Remove all cells past their TTL. Returns count removed.
    Called periodically by the runtime.

REFS(id) -> cell[]
    Return all cells that reference the given ID (reverse DAG traversal).
    "Show me all bids on this task", "all heartbeats for this contract".
```

### Transport Implementations (v1.0)

1. **SQLite** (primary): `cells` table with indexed columns for all query fields. WAL mode for concurrent reads.
2. **JSONL** (projection): After every PUT, cell appended to `channels/{channel}.jsonl`. Read-only for backward compat.
3. **MCP** (integration): Each operation becomes an MCP tool. Any MCP-capable agent participates natively.

---

## 6. Coordination Protocols (Layer 3)

### 6a. Task Lifecycle

```
[task] --bid--> [bid] --accept--> [contract] --work--> [heartbeat]*
                                       |
                                  [result] --review--> [feedback]
```

1. Orchestrator creates a `task` cell
2. Capable agents create `bid` cells referencing the task
3. Orchestrator selects a bid, creates a `contract` cell
4. Agent publishes `heartbeat` cells every 60s while working
5. Agent publishes `result` cell when done
6. Reviewer creates `feedback` cell scoring the result

**Self-assignment:** If `task.data.auto_assign: true`, first agent to create a contract gets it. No bid phase.

**Racing:** If `task.data.race: true`, multiple contracts accepted. First N results compared.

### 6b. File Leases

```
Agent checks:   QUERY(type="lease", tags=["resource:path/to/file"], since=now-ttl)
If no active:   PUT(lease{resource: "path/to/file", holder: "claude/1", ttl: 300})
On completion:  PUT(release{refs: [lease_id]})
On timeout:     EXPIRE() removes stale leases automatically
```

Leases are advisory (like `flock` in Unix). The contract feedback reflects conflicts.

### 6c. Reputation & Routing

```python
def reputation(agent_id, capability=None):
    feedbacks = QUERY(type="feedback", refs=agent_contracts(agent_id))
    if capability:
        feedbacks = [f for f in feedbacks if capability in f.tags]
    weights = [0.95 ** i for i in range(len(feedbacks))]  # exponential decay
    return weighted_avg([f.data.score for f in feedbacks], weights)

def route_task(task):
    cards = QUERY(type="card")
    scores = []
    for card in cards:
        cap_match = overlap(task.data.required_capabilities, card.data.capabilities)
        cost = card.data.cost_profile.output
        rep = reputation(card.from)
        score = cap_match * rep / (1 + cost)
        scores.append((card.from, score))
    return sorted(scores, key=lambda x: -x[1])
```

Routing function is pluggable. This is the default.

### 6d. Task DAGs

Tasks reference other tasks via `refs`:
```json
{"type": "task", "id": "hive:aaa", "data": {"title": "Extract labor data"}}
{"type": "task", "id": "hive:bbb", "data": {"title": "Analyze trends"}, "refs": ["hive:aaa"]}
{"type": "task", "id": "hive:ccc", "data": {"title": "Generate report"}, "refs": ["hive:bbb"]}
```

Agent won't start `bbb` until `aaa` has a `result` cell. The DAG is implicit in refs.

### 6e. Stall Detection

```python
def detect_stalls(timeout_seconds=300):
    contracts = QUERY(type="contract", since="-24h")
    for contract in contracts:
        if has_result(contract.id): continue
        last_hb = QUERY(type="heartbeat", refs=contract.id, limit=1, order="desc")
        if not last_hb or age(last_hb[0]) > timeout_seconds:
            PUT(signal{event: "stall_detected", payload: {
                contract_id: contract.id,
                agent: contract.data.agent,
                last_heartbeat: last_hb[0].ts if last_hb else None
            }})
```

Runs on a 60s interval. Emits signals that the orchestrator reacts to.

### 6f. Self-Improvement (Evolution)

```python
def evolve():
    for agent in active_agents():
        recent = reputation(agent, window="7d")
        older = reputation(agent, window="30d")
        if recent < older * 0.8:  # 20% decline
            PUT(signal{event: "performance_decline", payload: {
                agent: agent, recent: recent, baseline: older
            }})

    for task_type in task_types():
        results = QUERY(type="feedback", tags=[f"task_type:{task_type}"])
        fail_rate = sum(1 for r in results if r.data.score < 5) / len(results)
        if fail_rate > 0.3:
            PUT(signal{event: "high_failure_rate", payload: {
                task_type: task_type, fail_rate: fail_rate
            }})
```

Runs daily or on-demand. Signals feed back into routing.

---

## 7. Implementation Architecture

```
C:/tools/agent-comms/
  hive/                          # Python package
    __init__.py                  # HiveBoard class (facade)
    cell.py                      # Cell dataclass + ID generation
    board.py                     # Board operations (PUT/GET/QUERY/WATCH/EXPIRE/REFS)
    transports/
      sqlite.py                  # SQLite transport (primary)
      jsonl.py                   # JSONL projection (backward compat)
    coordination/
      router.py                  # Capability-based task routing
      reputation.py              # Reputation scoring from feedback
      stall_detector.py          # Heartbeat monitoring
      dag.py                     # Task DAG resolution
      leases.py                  # File lease management
      racing.py                  # Multi-agent racing
      evolution.py               # Self-improvement feedback loops
    mcp/
      server.py                  # MCP server wrapping Board operations
      tools.py                   # MCP tool definitions
  comms.sh                       # Bash CLI (updated, delegates to Python)
  hive.db                        # SQLite database (gitignored)
  channels/                      # JSONL projections (gitignored)
  org.json                       # Fleet configuration (Eagle instance)
  manifest.json                  # Protocol manifest
  standards.md                   # Fleet operating standards
  PROTOCOL.md                    # The HIVE protocol specification
```

---

## 8. Migration Path (v2.0 -> HIVE v1.0)

| Phase | What | Breaking? | Effort |
|-------|------|-----------|--------|
| 0 | Install `hive` Python package alongside existing `comms.sh` | No | Low |
| 1 | Update `comms.sh` to write through Python (dual-write SQLite + JSONL) | No | Medium |
| 2 | Add new cell types (cards, leases, heartbeats, contracts) | No | Medium |
| 3 | Add MCP server for native agent integration | No | Medium |
| 4 | Enable reputation tracking, routing, stall detection | No | Medium |
| 5 | Prune: review 30 days of data, kill unused features | No | Low |

Each phase is independently deployable. No big bang migration.

---

## 9. Design Decisions & Rationale

| Decision | Rationale | Alternative Considered |
|----------|-----------|----------------------|
| Content-addressable IDs | Git proved this works. Enables dedup, verification, replay. | Sequential IDs (simpler but no integrity guarantees) |
| Immutable cells | Prevents silent edits. History is trustworthy. | Mutable records (simpler but lossy) |
| SQLite primary + JSONL projection | SQLite gives transactions/queries. JSONL gives human readability + v2 compat. | JSONL only (no queries), SQLite only (no backward compat) |
| Advisory file leases | Simple, no daemon needed. Bad actors get bad feedback scores. | Mandatory locks (requires daemon, complex failure modes) |
| Market-driven routing | Scales without central configuration. Self-optimizing. | Hardcoded routing table (simpler but brittle) |
| MCP server integration | MCP already won. All major agent CLIs support it. Native participation. | Custom IPC (reinventing the wheel) |

---

## 10. Research Sources

Design informed by 200+ searches across 10 research domains (2026-03-01/02):
- **MCP Agent Mail** (file leases, agent identities)
- **A2A Protocol** (Agent Cards, capability declaration)
- **Don Syme's compiler swarm** (progress heartbeats)
- **GitHub Agent HQ** (agent racing)
- **Confluent** (blackboard pattern)
- **Spotify Honk** (production fleet at scale)
- **Ant colony optimization** (stigmergy principle)
- **TCP/IP, HTTP, Git** (layered protocol design)

Full research report: `RESEARCH.md`
