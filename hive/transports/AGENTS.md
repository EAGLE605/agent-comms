<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-02 | Updated: 2026-03-02 -->

# hive/transports/ — Storage Backends

## Purpose
Dual-write storage: every cell written to both SQLite (primary, queryable) and JSONL
(secondary, append-only, backward compat with comms.sh). HiveBoard handles both —
callers never import transports directly.

## Key Files
| File | Description |
|------|-------------|
| `sqlite.py` | Primary storage — WAL mode, thread-local connections, full query/watch API |
| `jsonl.py` | Secondary storage — append-only channel files, write-only (no read API) |

## For AI Agents

### Never Import Transports Directly
```python
# WRONG
from hive.transports.sqlite import SQLiteTransport

# CORRECT
from hive.board import HiveBoard
board = HiveBoard(db_path="hive.db", channels_dir="channels/")
```

### SQLite Details
- WAL mode enabled for concurrent readers
- Thread-local connections (safe for multi-threaded use)
- Tables: cells (primary), watchers (in-memory only)
- Indexes on: type, channel, from_agent, ts

### JSONL Details
- One file per channel: channels/{channel_name}.jsonl
- Append-only — never modify existing lines
- Same JSON schema as SQLite cells
- Used by comms.sh for shell access to the bus

## Dependencies
- Python stdlib: sqlite3, json, threading, pathlib
