<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-02 | Updated: 2026-03-02 -->

# channels/ — Legacy Channel Directory

## Purpose
Original channel JSONL files from before the unified ~/.ai/channels directory.
This directory is NO LONGER the active write target.

## CRITICAL: Active Channel Location
The canonical channels directory is: C:/Users/Brady.EAGLE/.ai/channels
Symlinked from: ~/.claude/channels, ~/.gemini/channels, ~/.codex/channels → C:/Users/Brady.EAGLE/.ai/channels

comms.sh writes to C:/Users/Brady.EAGLE/.ai/channels (not this directory).
This directory contains legacy/historical cells only.

## Channels (13 total)
| Channel | Purpose |
|---------|---------|
| `roster.jsonl` | Agent clock-in/clock-out, fleet availability log |
| `general.jsonl` | Catch-all coordination messages |
| `ops.jsonl` | Operations and infrastructure tasks |
| `audit.jsonl` | Verification requests and results |
| `backfill.jsonl` | Data extraction and migration tasks |
| `deploy.jsonl` | Deployment and release coordination |
| `handoff.jsonl` | Agent-to-agent task transfers |
| `ingest.jsonl` | Data ingestion pipeline tasks |
| `keyedin.jsonl` | KeyedIn ERP extraction tasks |
| `kimco.jsonl` | Kimco ERP migration tasks |
| `signx-intel.jsonl` | SignX intelligence and active fleet tasks |
| `signx-takeoff.jsonl` | SignX takeoff/estimation tasks |
| `signx-warehouse.jsonl` | SignX warehouse analytics tasks |

## For AI Agents
- DO NOT write to this directory's JSONL files
- Read from C:/Users/Brady.EAGLE/.ai/channels instead
- Use: export COMMS_CHANNELS=C:/Users/Brady.EAGLE/.ai/channels before sourcing comms.sh
