<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-02 | Updated: 2026-03-02 -->

# dashboard/ — HIVE Factory Floor Visual

## Purpose
Real-time web dashboard showing the agent fleet working. Factory floor metaphor:
agent workstations, task pipeline kanban (OPEN→CLAIMED→COMPLETE), live cell feed.
FastAPI backend on port 7842. Auto-refreshes every 5 seconds.

## Key Files
| File | Description |
|------|-------------|
| `server.py` | FastAPI server — 5 REST endpoints reading HIVE JSONL/SQLite data |
| `index.html` | Self-contained factory floor UI — no build step, open directly in browser |
| `requirements.txt` | fastapi + uvicorn only |
| `start.sh` | pip install + launch server |

## API Endpoints
| Endpoint | Returns |
|----------|---------|
| GET /api/agents | Roster: online/offline status, current task, role, last seen |
| GET /api/tasks?channel=X | Task cells with status (open/claimed/complete) |
| GET /api/feed?channel=X&limit=50 | Last N cells, newest first |
| GET /api/stats | Per-agent cell counts, pass rates, active channels |
| GET /api/channels | All channel files with cell counts |

## For AI Agents

### Starting the Dashboard
```bash
bash /c/tools/agent-comms/dashboard/start.sh
# Open http://localhost:7842
```

### Cloudflare Tunnel (TODO)
Currently localhost-only. Expose via named Cloudflare Tunnel for remote access.
See FLEET-OPS.md Known Limitations item 4.

### Data Source
Reads from: C:/Users/Brady.EAGLE/.ai/channels/*.jsonl
Falls back gracefully if hive.db doesn't exist.

## Dependencies
- fastapi, uvicorn (pip install)
- Python 3.11+
