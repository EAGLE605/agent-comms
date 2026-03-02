# HIVE Protocol v1.0 — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement the HIVE protocol as a Python package at `C:/tools/agent-comms/hive/`, providing content-addressable immutable Cells, a SQLite-backed Board, JSONL backward-compatible projections, coordination protocols (routing, reputation, leases, stall detection), and an MCP server — all while keeping the existing `comms.sh` CLI working throughout migration.

**Architecture:** 4-layer protocol stack. Layer 1 (Transport) is SQLite primary + JSONL projection. Layer 2 (Communication) is Cell dataclass + Board operations (PUT/GET/QUERY/WATCH/EXPIRE/REFS). Layer 3 (Coordination) is routing, reputation, leases, heartbeats, DAGs, racing, evolution. Layer 4 (Applications) is the MCP server + updated `comms.sh` CLI.

**Tech Stack:** Python 3.13 (stdlib only — no pip deps). SQLite WAL mode. `dataclasses` for Cell. `hashlib` for SHA-256. `json` for serialization. `threading` for WATCH. `http.server` or FastMCP for MCP server.

**Design doc:** `docs/plans/2026-03-02-hive-protocol-design.md`

**Key constraints:**
- Zero external dependencies (stdlib only for core package)
- Windows 11 + Git Bash environment
- Must coexist with existing `comms.sh` — no breaking changes until migration complete
- UTF-8 everywhere, ASCII-only in print() output (cp1252 terminal compat)
- All tests must use `--timeout=30` (per execution standard)

---

## Phase 0: Project Scaffolding

### Task 1: Create Python package structure

**Files:**
- Create: `hive/__init__.py`
- Create: `hive/cell.py`
- Create: `hive/board.py`
- Create: `hive/transports/__init__.py`
- Create: `hive/transports/sqlite.py`
- Create: `hive/transports/jsonl.py`
- Create: `hive/coordination/__init__.py`
- Create: `hive/coordination/router.py`
- Create: `hive/coordination/reputation.py`
- Create: `hive/coordination/stall_detector.py`
- Create: `hive/coordination/dag.py`
- Create: `hive/coordination/leases.py`
- Create: `hive/coordination/racing.py`
- Create: `hive/coordination/evolution.py`
- Create: `hive/mcp/__init__.py`
- Create: `hive/mcp/server.py`
- Create: `hive/mcp/tools.py`
- Create: `tests/__init__.py`
- Create: `tests/test_cell.py`
- Create: `pyproject.toml`
- Modify: `.gitignore` (add `hive.db`, `__pycache__`, `*.pyc`, `.pytest_cache`)

**Step 1: Create pyproject.toml**

```toml
[project]
name = "hive-protocol"
version = "1.0.0"
description = "HIVE: Hierarchical Inter-agent Virtual Exchange protocol"
requires-python = ">=3.11"

[tool.pytest.ini_options]
timeout = 30
testpaths = ["tests"]
```

**Step 2: Create all empty `__init__.py` files and directory structure**

```bash
mkdir -p hive/transports hive/coordination hive/mcp tests
touch hive/__init__.py hive/transports/__init__.py hive/coordination/__init__.py hive/mcp/__init__.py tests/__init__.py
```

**Step 3: Update .gitignore**

Append to existing `.gitignore`:
```
# Python
__pycache__/
*.pyc
.pytest_cache/

# HIVE database
hive.db
```

**Step 4: Create placeholder test file**

```python
# tests/test_cell.py
"""Tests for hive.cell module."""


def test_placeholder():
    """Placeholder — replaced in Task 2."""
    assert True
```

**Step 5: Run tests to verify scaffolding**

Run: `cd C:/tools/agent-comms && timeout 30 python -m pytest tests/ -v --timeout=30`
Expected: 1 passed

**Step 6: Commit**

```bash
git add hive/ tests/ pyproject.toml .gitignore
git commit -m "feat: HIVE v1.0 project scaffolding"
```

---

## Phase 1: Cell Dataclass + ID Generation (Layer 2 Core)

### Task 2: Implement Cell dataclass with content-addressable IDs

**Files:**
- Create: `hive/cell.py`
- Create: `tests/test_cell.py`

The Cell is the atomic unit of HIVE. Immutable. Content-addressable via SHA-256.

**Step 1: Write failing tests for Cell**

```python
# tests/test_cell.py
"""Tests for hive.cell — the atomic unit of HIVE."""
import json
from hive.cell import Cell, make_cell, cell_to_dict, cell_from_dict


class TestCellCreation:
    def test_make_cell_returns_cell(self):
        c = make_cell(type="task", from_agent="claude/1", channel="general", data={"title": "test"})
        assert isinstance(c, Cell)

    def test_cell_has_hive_prefix_id(self):
        c = make_cell(type="task", from_agent="claude/1", channel="general", data={"title": "test"})
        assert c.id.startswith("hive:")

    def test_cell_id_is_16_hex_chars_after_prefix(self):
        c = make_cell(type="task", from_agent="claude/1", channel="general", data={"title": "test"})
        hex_part = c.id[5:]  # after "hive:"
        assert len(hex_part) == 16
        int(hex_part, 16)  # should not raise

    def test_cell_id_is_deterministic(self):
        """Same inputs at same timestamp produce same ID."""
        ts = "2026-03-01T22:00:00-06:00"
        c1 = make_cell(type="task", from_agent="claude/1", channel="general", data={"title": "test"}, ts=ts)
        c2 = make_cell(type="task", from_agent="claude/1", channel="general", data={"title": "test"}, ts=ts)
        assert c1.id == c2.id

    def test_different_data_produces_different_id(self):
        ts = "2026-03-01T22:00:00-06:00"
        c1 = make_cell(type="task", from_agent="claude/1", channel="general", data={"title": "A"}, ts=ts)
        c2 = make_cell(type="task", from_agent="claude/1", channel="general", data={"title": "B"}, ts=ts)
        assert c1.id != c2.id

    def test_cell_version_is_1(self):
        c = make_cell(type="task", from_agent="claude/1", channel="general", data={})
        assert c.v == 1

    def test_cell_ts_is_iso8601(self):
        c = make_cell(type="task", from_agent="claude/1", channel="general", data={})
        # Should contain T separator and timezone
        assert "T" in c.ts

    def test_cell_defaults(self):
        c = make_cell(type="task", from_agent="claude/1", channel="general", data={})
        assert c.refs == []
        assert c.ttl == 0
        assert c.tags == []
        assert c.sig is None


class TestCellSerialization:
    def test_cell_to_dict_roundtrip(self):
        c = make_cell(type="task", from_agent="claude/1", channel="general", data={"title": "test"})
        d = cell_to_dict(c)
        c2 = cell_from_dict(d)
        assert c.id == c2.id
        assert c.type == c2.type
        assert c.data == c2.data

    def test_cell_to_dict_is_json_serializable(self):
        c = make_cell(type="task", from_agent="claude/1", channel="general", data={"x": 1})
        d = cell_to_dict(c)
        s = json.dumps(d)
        assert isinstance(s, str)

    def test_cell_from_dict_handles_missing_optional_fields(self):
        d = {
            "id": "hive:abc123def456abcd",
            "v": 1,
            "type": "task",
            "from": "claude/1",
            "ts": "2026-03-01T22:00:00-06:00",
            "channel": "general",
            "data": {},
        }
        c = cell_from_dict(d)
        assert c.refs == []
        assert c.ttl == 0
        assert c.tags == []
        assert c.sig is None


class TestCellIDGeneration:
    def test_id_formula_matches_spec(self):
        """ID = hive: + SHA256(type + from + ts + channel + JSON(data))[:16]"""
        import hashlib
        ts = "2026-03-01T22:00:00-06:00"
        c = make_cell(type="task", from_agent="claude/1", channel="general", data={"a": 1}, ts=ts)
        payload = "task" + "claude/1" + ts + "general" + json.dumps({"a": 1}, separators=(",", ":"), sort_keys=True)
        expected_hash = hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]
        assert c.id == f"hive:{expected_hash}"
```

**Step 2: Run tests to verify they fail**

Run: `cd C:/tools/agent-comms && timeout 30 python -m pytest tests/test_cell.py -v --timeout=30`
Expected: FAIL — `ModuleNotFoundError: No module named 'hive.cell'` or `ImportError`

**Step 3: Implement Cell**

```python
# hive/cell.py
"""Cell — the atomic, immutable, content-addressable unit of HIVE.

Every piece of data in the protocol is a Cell. Cells are immutable once created.
Their ID is deterministic: SHA-256 of (type + from + ts + channel + JSON(data)).
Cells link to each other via `refs`, forming a DAG.
"""
import hashlib
import json
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any


@dataclass(frozen=True)
class Cell:
    """An immutable, content-addressable HIVE cell."""
    id: str
    v: int
    type: str
    from_agent: str  # 'from' is reserved in Python
    ts: str
    channel: str
    data: dict[str, Any]
    refs: list[str] = field(default_factory=list)
    ttl: int = 0
    tags: list[str] = field(default_factory=list)
    sig: str | None = None


def _generate_id(type: str, from_agent: str, ts: str, channel: str, data: dict) -> str:
    """Generate deterministic content-addressable cell ID.

    Formula: hive: + SHA-256(type + from + ts + channel + JSON(data))[:16]
    JSON is serialized with compact separators and sorted keys for determinism.
    """
    data_json = json.dumps(data, separators=(",", ":"), sort_keys=True)
    payload = f"{type}{from_agent}{ts}{channel}{data_json}"
    digest = hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]
    return f"hive:{digest}"


def make_cell(
    *,
    type: str,
    from_agent: str,
    channel: str,
    data: dict[str, Any],
    ts: str | None = None,
    refs: list[str] | None = None,
    ttl: int = 0,
    tags: list[str] | None = None,
    sig: str | None = None,
) -> Cell:
    """Create a new Cell with auto-generated ID and timestamp."""
    if ts is None:
        ts = datetime.now(timezone.utc).astimezone().isoformat()
    cell_refs = list(refs) if refs else []
    cell_tags = list(tags) if tags else []
    cell_id = _generate_id(type, from_agent, ts, channel, data)
    return Cell(
        id=cell_id,
        v=1,
        type=type,
        from_agent=from_agent,
        ts=ts,
        channel=channel,
        data=data,
        refs=cell_refs,
        ttl=ttl,
        tags=cell_tags,
        sig=sig,
    )


def cell_to_dict(cell: Cell) -> dict[str, Any]:
    """Serialize a Cell to a JSON-compatible dict.

    Maps `from_agent` back to `from` for protocol compatibility.
    """
    return {
        "id": cell.id,
        "v": cell.v,
        "type": cell.type,
        "from": cell.from_agent,
        "ts": cell.ts,
        "channel": cell.channel,
        "refs": cell.refs,
        "ttl": cell.ttl,
        "tags": cell.tags,
        "data": cell.data,
        "sig": cell.sig,
    }


def cell_from_dict(d: dict[str, Any]) -> Cell:
    """Deserialize a dict to a Cell.

    Handles `from` -> `from_agent` mapping and missing optional fields.
    """
    return Cell(
        id=d["id"],
        v=d.get("v", 1),
        type=d["type"],
        from_agent=d["from"],
        ts=d["ts"],
        channel=d["channel"],
        data=d.get("data", {}),
        refs=d.get("refs", []),
        ttl=d.get("ttl", 0),
        tags=d.get("tags", []),
        sig=d.get("sig"),
    )
```

**Step 4: Run tests to verify they pass**

Run: `cd C:/tools/agent-comms && timeout 30 python -m pytest tests/test_cell.py -v --timeout=30`
Expected: All 12 tests PASS

**Step 5: Commit**

```bash
git add hive/cell.py tests/test_cell.py
git commit -m "feat(hive): Cell dataclass with content-addressable SHA-256 IDs"
```

---

## Phase 2: SQLite Transport (Layer 1)

### Task 3: Implement SQLite transport with WAL mode

**Files:**
- Create: `hive/transports/sqlite.py`
- Create: `tests/test_sqlite_transport.py`

The SQLite transport implements all 6 Board operations against a SQLite database.

**Step 1: Write failing tests**

```python
# tests/test_sqlite_transport.py
"""Tests for hive.transports.sqlite — SQLite Board transport."""
import os
import tempfile
from hive.cell import make_cell
from hive.transports.sqlite import SQLiteTransport


def _make_transport(path=None):
    if path is None:
        fd, path = tempfile.mkstemp(suffix=".db")
        os.close(fd)
    return SQLiteTransport(path), path


class TestPutAndGet:
    def test_put_returns_cell_id(self):
        t, _ = _make_transport()
        c = make_cell(type="task", from_agent="claude/1", channel="general", data={"title": "test"})
        result = t.put(c)
        assert result == c.id

    def test_get_returns_cell(self):
        t, _ = _make_transport()
        c = make_cell(type="task", from_agent="claude/1", channel="general", data={"title": "test"})
        t.put(c)
        got = t.get(c.id)
        assert got is not None
        assert got.id == c.id
        assert got.data == c.data

    def test_get_missing_returns_none(self):
        t, _ = _make_transport()
        assert t.get("hive:0000000000000000") is None

    def test_put_is_idempotent(self):
        t, _ = _make_transport()
        c = make_cell(type="task", from_agent="claude/1", channel="general", data={"title": "test"})
        id1 = t.put(c)
        id2 = t.put(c)  # same cell again
        assert id1 == id2


class TestQuery:
    def test_query_by_type(self):
        t, _ = _make_transport()
        t.put(make_cell(type="task", from_agent="claude/1", channel="general", data={}))
        t.put(make_cell(type="card", from_agent="claude/1", channel="general", data={}))
        results = t.query(type="task")
        assert len(results) == 1
        assert results[0].type == "task"

    def test_query_by_channel(self):
        t, _ = _make_transport()
        t.put(make_cell(type="task", from_agent="claude/1", channel="signx", data={}))
        t.put(make_cell(type="task", from_agent="claude/1", channel="general", data={}))
        results = t.query(channel="signx")
        assert len(results) == 1

    def test_query_by_from_prefix(self):
        t, _ = _make_transport()
        t.put(make_cell(type="task", from_agent="claude/1", channel="general", data={}))
        t.put(make_cell(type="task", from_agent="gemini/1", channel="general", data={}))
        results = t.query(from_prefix="claude")
        assert len(results) == 1
        assert results[0].from_agent == "claude/1"

    def test_query_by_tags(self):
        t, _ = _make_transport()
        t.put(make_cell(type="task", from_agent="claude/1", channel="general", data={}, tags=["priority:high", "dept:signx"]))
        t.put(make_cell(type="task", from_agent="claude/1", channel="general", data={}, tags=["priority:low"]))
        results = t.query(tags=["priority:high"])
        assert len(results) == 1

    def test_query_limit(self):
        t, _ = _make_transport()
        for i in range(10):
            t.put(make_cell(type="task", from_agent="claude/1", channel="general", data={"i": i}, ts=f"2026-03-01T22:00:{i:02d}-06:00"))
        results = t.query(type="task", limit=3)
        assert len(results) == 3

    def test_query_order_desc(self):
        t, _ = _make_transport()
        t.put(make_cell(type="task", from_agent="claude/1", channel="general", data={"i": 1}, ts="2026-03-01T22:00:01-06:00"))
        t.put(make_cell(type="task", from_agent="claude/1", channel="general", data={"i": 2}, ts="2026-03-01T22:00:02-06:00"))
        results = t.query(type="task", order="desc")
        assert results[0].data["i"] == 2

    def test_query_since(self):
        t, _ = _make_transport()
        t.put(make_cell(type="task", from_agent="claude/1", channel="general", data={"old": True}, ts="2026-03-01T20:00:00-06:00"))
        t.put(make_cell(type="task", from_agent="claude/1", channel="general", data={"new": True}, ts="2026-03-01T23:00:00-06:00"))
        results = t.query(type="task", since="2026-03-01T22:00:00-06:00")
        assert len(results) == 1
        assert results[0].data.get("new") is True


class TestRefs:
    def test_refs_returns_referencing_cells(self):
        t, _ = _make_transport()
        parent = make_cell(type="task", from_agent="claude/1", channel="general", data={"title": "parent"})
        t.put(parent)
        child = make_cell(type="bid", from_agent="gemini/1", channel="general", data={"approach": "fast"}, refs=[parent.id])
        t.put(child)
        referencing = t.refs(parent.id)
        assert len(referencing) == 1
        assert referencing[0].id == child.id

    def test_refs_empty_when_no_references(self):
        t, _ = _make_transport()
        c = make_cell(type="task", from_agent="claude/1", channel="general", data={})
        t.put(c)
        assert t.refs(c.id) == []


class TestExpire:
    def test_expire_removes_expired_cells(self):
        t, _ = _make_transport()
        # Cell with TTL=1 second, timestamp in the past
        c = make_cell(type="heartbeat", from_agent="claude/1", channel="general", data={}, ttl=1, ts="2020-01-01T00:00:00+00:00")
        t.put(c)
        removed = t.expire()
        assert removed >= 1
        assert t.get(c.id) is None

    def test_expire_keeps_permanent_cells(self):
        t, _ = _make_transport()
        c = make_cell(type="task", from_agent="claude/1", channel="general", data={}, ttl=0)
        t.put(c)
        t.expire()
        assert t.get(c.id) is not None
```

**Step 2: Run tests to verify they fail**

Run: `cd C:/tools/agent-comms && timeout 30 python -m pytest tests/test_sqlite_transport.py -v --timeout=30`
Expected: FAIL — ImportError

**Step 3: Implement SQLite transport**

```python
# hive/transports/sqlite.py
"""SQLite transport for the HIVE Board.

Implements all 6 Board operations: PUT, GET, QUERY, WATCH, EXPIRE, REFS.
Uses WAL mode for concurrent reads. Single-writer, multi-reader safe.
"""
import json
import sqlite3
import threading
from datetime import datetime, timezone
from typing import Any

from hive.cell import Cell, cell_from_dict, cell_to_dict


_SCHEMA = """
CREATE TABLE IF NOT EXISTS cells (
    id       TEXT PRIMARY KEY,
    v        INTEGER NOT NULL DEFAULT 1,
    type     TEXT NOT NULL,
    "from"   TEXT NOT NULL,
    ts       TEXT NOT NULL,
    channel  TEXT NOT NULL,
    refs     TEXT NOT NULL DEFAULT '[]',
    ttl      INTEGER NOT NULL DEFAULT 0,
    tags     TEXT NOT NULL DEFAULT '[]',
    data     TEXT NOT NULL DEFAULT '{}',
    sig      TEXT
);

CREATE INDEX IF NOT EXISTS idx_cells_type    ON cells(type);
CREATE INDEX IF NOT EXISTS idx_cells_channel ON cells(channel);
CREATE INDEX IF NOT EXISTS idx_cells_from    ON cells("from");
CREATE INDEX IF NOT EXISTS idx_cells_ts      ON cells(ts);
"""


class SQLiteTransport:
    """SQLite-backed HIVE Board transport."""

    def __init__(self, db_path: str = "hive.db"):
        self._db_path = db_path
        self._local = threading.local()
        self._watchers: dict[str, list] = {}  # channel -> list of callbacks
        self._watcher_lock = threading.Lock()
        # Initialize schema
        conn = self._conn()
        conn.executescript(_SCHEMA)
        conn.execute("PRAGMA journal_mode=WAL")
        conn.commit()

    def _conn(self) -> sqlite3.Connection:
        """Get thread-local connection."""
        if not hasattr(self._local, "conn") or self._local.conn is None:
            self._local.conn = sqlite3.connect(self._db_path)
            self._local.conn.row_factory = sqlite3.Row
        return self._local.conn

    def put(self, cell: Cell) -> str:
        """Write a cell to the board. Idempotent."""
        conn = self._conn()
        try:
            conn.execute(
                """INSERT OR IGNORE INTO cells (id, v, type, "from", ts, channel, refs, ttl, tags, data, sig)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    cell.id,
                    cell.v,
                    cell.type,
                    cell.from_agent,
                    cell.ts,
                    cell.channel,
                    json.dumps(cell.refs),
                    cell.ttl,
                    json.dumps(cell.tags),
                    json.dumps(cell.data, separators=(",", ":"), sort_keys=True),
                    cell.sig,
                ),
            )
            conn.commit()
        except sqlite3.Error:
            conn.rollback()
            raise
        # Notify watchers
        self._notify_watchers(cell)
        return cell.id

    def get(self, cell_id: str) -> Cell | None:
        """Retrieve a cell by ID."""
        row = self._conn().execute("SELECT * FROM cells WHERE id = ?", (cell_id,)).fetchone()
        if row is None:
            return None
        return self._row_to_cell(row)

    def query(
        self,
        *,
        type: str | None = None,
        channel: str | None = None,
        from_prefix: str | None = None,
        since: str | None = None,
        tags: list[str] | None = None,
        refs: str | None = None,
        limit: int = 100,
        order: str = "asc",
    ) -> list[Cell]:
        """Find cells matching criteria."""
        clauses: list[str] = []
        params: list[Any] = []

        if type is not None:
            clauses.append("type = ?")
            params.append(type)
        if channel is not None:
            clauses.append("channel = ?")
            params.append(channel)
        if from_prefix is not None:
            clauses.append('"from" LIKE ?')
            params.append(f"{from_prefix}%")
        if since is not None:
            clauses.append("ts > ?")
            params.append(since)
        if refs is not None:
            clauses.append("refs LIKE ?")
            params.append(f"%{refs}%")

        where = " AND ".join(clauses) if clauses else "1=1"
        order_dir = "DESC" if order == "desc" else "ASC"
        sql = f"SELECT * FROM cells WHERE {where} ORDER BY ts {order_dir} LIMIT ?"
        params.append(limit)

        rows = self._conn().execute(sql, params).fetchall()
        cells = [self._row_to_cell(row) for row in rows]

        # Post-filter by tags (all must match)
        if tags:
            cells = [c for c in cells if all(t in c.tags for t in tags)]

        return cells

    def refs(self, cell_id: str) -> list[Cell]:
        """Return all cells that reference the given ID (reverse DAG traversal)."""
        rows = self._conn().execute(
            "SELECT * FROM cells WHERE refs LIKE ? ORDER BY ts ASC",
            (f"%{cell_id}%",),
        ).fetchall()
        # Precise filter: the cell_id must be in the parsed refs list
        result = []
        for row in rows:
            cell = self._row_to_cell(row)
            if cell_id in cell.refs:
                result.append(cell)
        return result

    def expire(self) -> int:
        """Remove all cells past their TTL. Returns count removed."""
        now = datetime.now(timezone.utc).isoformat()
        conn = self._conn()
        # Find expired cells: ttl > 0 AND (ts + ttl seconds) < now
        # SQLite datetime arithmetic: use julianday for precision
        cursor = conn.execute(
            """DELETE FROM cells
               WHERE ttl > 0
               AND julianday('now') > julianday(
                   CASE
                       WHEN ts LIKE '%Z' THEN replace(ts, 'Z', '+00:00')
                       ELSE ts
                   END
               ) + (ttl / 86400.0)""",
        )
        conn.commit()
        return cursor.rowcount

    def watch(self, channel: str, callback, type_filter: str | None = None):
        """Subscribe to new cells on a channel.

        callback(cell: Cell) is called for each new cell matching the filter.
        """
        with self._watcher_lock:
            if channel not in self._watchers:
                self._watchers[channel] = []
            self._watchers[channel].append((callback, type_filter))

    def _notify_watchers(self, cell: Cell):
        """Notify watchers of a new cell."""
        with self._watcher_lock:
            watchers = self._watchers.get(cell.channel, [])
        for callback, type_filter in watchers:
            if type_filter is None or cell.type == type_filter:
                try:
                    callback(cell)
                except Exception:
                    pass  # watchers should not crash the board

    def _row_to_cell(self, row: sqlite3.Row) -> Cell:
        """Convert a SQLite row to a Cell."""
        return Cell(
            id=row["id"],
            v=row["v"],
            type=row["type"],
            from_agent=row["from"],
            ts=row["ts"],
            channel=row["channel"],
            refs=json.loads(row["refs"]),
            ttl=row["ttl"],
            tags=json.loads(row["tags"]),
            data=json.loads(row["data"]),
            sig=row["sig"],
        )
```

**Step 4: Run tests to verify they pass**

Run: `cd C:/tools/agent-comms && timeout 30 python -m pytest tests/test_sqlite_transport.py -v --timeout=30`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add hive/transports/sqlite.py tests/test_sqlite_transport.py
git commit -m "feat(hive): SQLite transport with WAL mode — all 6 Board operations"
```

---

### Task 4: Implement JSONL projection transport

**Files:**
- Create: `hive/transports/jsonl.py`
- Create: `tests/test_jsonl_transport.py`

The JSONL transport writes cells as append-only lines to channel files. Read-only query support for backward compatibility with the existing `comms.sh` readers.

**Step 1: Write failing tests**

```python
# tests/test_jsonl_transport.py
"""Tests for hive.transports.jsonl — JSONL projection transport."""
import json
import os
import tempfile
from hive.cell import make_cell
from hive.transports.jsonl import JSONLTransport


def _make_transport():
    tmpdir = tempfile.mkdtemp()
    return JSONLTransport(tmpdir), tmpdir


class TestJSONLWrite:
    def test_put_creates_channel_file(self):
        t, tmpdir = _make_transport()
        c = make_cell(type="task", from_agent="claude/1", channel="general", data={})
        t.put(c)
        assert os.path.exists(os.path.join(tmpdir, "general.jsonl"))

    def test_put_appends_json_line(self):
        t, tmpdir = _make_transport()
        c = make_cell(type="task", from_agent="claude/1", channel="general", data={"title": "test"})
        t.put(c)
        with open(os.path.join(tmpdir, "general.jsonl")) as f:
            lines = f.readlines()
        assert len(lines) == 1
        parsed = json.loads(lines[0])
        assert parsed["id"] == c.id
        assert parsed["type"] == "task"

    def test_put_multiple_cells_appends(self):
        t, tmpdir = _make_transport()
        for i in range(3):
            t.put(make_cell(type="task", from_agent="claude/1", channel="general", data={"i": i}, ts=f"2026-03-01T22:00:{i:02d}-06:00"))
        with open(os.path.join(tmpdir, "general.jsonl")) as f:
            lines = f.readlines()
        assert len(lines) == 3

    def test_put_different_channels(self):
        t, tmpdir = _make_transport()
        t.put(make_cell(type="task", from_agent="claude/1", channel="signx", data={}))
        t.put(make_cell(type="task", from_agent="claude/1", channel="general", data={}))
        assert os.path.exists(os.path.join(tmpdir, "signx.jsonl"))
        assert os.path.exists(os.path.join(tmpdir, "general.jsonl"))

    def test_serialized_cell_uses_from_not_from_agent(self):
        """Protocol wire format uses 'from', not 'from_agent'."""
        t, tmpdir = _make_transport()
        c = make_cell(type="task", from_agent="claude/1", channel="general", data={})
        t.put(c)
        with open(os.path.join(tmpdir, "general.jsonl")) as f:
            parsed = json.loads(f.readline())
        assert "from" in parsed
        assert "from_agent" not in parsed
```

**Step 2: Run tests to verify they fail**

Run: `cd C:/tools/agent-comms && timeout 30 python -m pytest tests/test_jsonl_transport.py -v --timeout=30`
Expected: FAIL

**Step 3: Implement JSONL transport**

```python
# hive/transports/jsonl.py
"""JSONL projection transport for HIVE.

Appends cells as one-JSON-per-line to channel-named files.
Provides backward compatibility with the existing comms.sh readers.
This is a write-only projection — reads go through SQLite.
"""
import json
import os

from hive.cell import Cell, cell_to_dict


class JSONLTransport:
    """Append-only JSONL file writer, one file per channel."""

    def __init__(self, channels_dir: str):
        self._dir = channels_dir
        os.makedirs(self._dir, exist_ok=True)

    def put(self, cell: Cell) -> str:
        """Append cell to the channel's JSONL file."""
        filepath = os.path.join(self._dir, f"{cell.channel}.jsonl")
        line = json.dumps(cell_to_dict(cell), ensure_ascii=False, separators=(",", ":"))
        with open(filepath, "a", encoding="utf-8") as f:
            f.write(line + "\n")
        return cell.id
```

**Step 4: Run tests to verify they pass**

Run: `cd C:/tools/agent-comms && timeout 30 python -m pytest tests/test_jsonl_transport.py -v --timeout=30`
Expected: All 5 tests PASS

**Step 5: Commit**

```bash
git add hive/transports/jsonl.py tests/test_jsonl_transport.py
git commit -m "feat(hive): JSONL projection transport for backward compat"
```

---

## Phase 3: Board Facade (Layer 2)

### Task 5: Implement HiveBoard — unified facade over both transports

**Files:**
- Create: `hive/board.py`
- Modify: `hive/__init__.py` (export HiveBoard, make_cell, Cell)
- Create: `tests/test_board.py`

The Board is the public API. It dual-writes to SQLite + JSONL and queries from SQLite.

**Step 1: Write failing tests**

```python
# tests/test_board.py
"""Tests for hive.board — the HiveBoard facade."""
import os
import tempfile
from hive.board import HiveBoard


def _make_board():
    tmpdir = tempfile.mkdtemp()
    db_path = os.path.join(tmpdir, "test.db")
    channels_dir = os.path.join(tmpdir, "channels")
    return HiveBoard(db_path=db_path, channels_dir=channels_dir), tmpdir


class TestHiveBoard:
    def test_put_and_get(self):
        board, _ = _make_board()
        cell_id = board.put(type="task", from_agent="claude/1", channel="general", data={"title": "test"})
        cell = board.get(cell_id)
        assert cell is not None
        assert cell.data["title"] == "test"

    def test_put_creates_jsonl_file(self):
        board, tmpdir = _make_board()
        board.put(type="task", from_agent="claude/1", channel="general", data={})
        assert os.path.exists(os.path.join(tmpdir, "channels", "general.jsonl"))

    def test_query_delegates_to_sqlite(self):
        board, _ = _make_board()
        board.put(type="task", from_agent="claude/1", channel="general", data={"a": 1})
        board.put(type="card", from_agent="claude/1", channel="general", data={"b": 2})
        results = board.query(type="task")
        assert len(results) == 1

    def test_refs_works(self):
        board, _ = _make_board()
        parent_id = board.put(type="task", from_agent="claude/1", channel="general", data={"title": "parent"})
        board.put(type="bid", from_agent="gemini/1", channel="general", data={}, refs=[parent_id])
        refs = board.refs(parent_id)
        assert len(refs) == 1
        assert refs[0].type == "bid"

    def test_expire_works(self):
        board, _ = _make_board()
        board.put(type="heartbeat", from_agent="claude/1", channel="general", data={}, ttl=1, ts="2020-01-01T00:00:00+00:00")
        removed = board.expire()
        assert removed >= 1

    def test_convenience_methods(self):
        """Board should have shortcut methods for common cell types."""
        board, _ = _make_board()
        board.task(from_agent="claude/1", channel="general", title="Do thing", spec="Details here")
        results = board.query(type="task")
        assert len(results) == 1
        assert results[0].data["title"] == "Do thing"
```

**Step 2: Run tests to verify they fail**

Run: `cd C:/tools/agent-comms && timeout 30 python -m pytest tests/test_board.py -v --timeout=30`
Expected: FAIL

**Step 3: Implement HiveBoard**

```python
# hive/board.py
"""HiveBoard — the public API facade for the HIVE protocol.

Dual-writes to SQLite (primary, queryable) + JSONL (projection, backward compat).
All queries go through SQLite. JSONL is write-only.
"""
from typing import Any

from hive.cell import Cell, make_cell
from hive.transports.sqlite import SQLiteTransport
from hive.transports.jsonl import JSONLTransport


class HiveBoard:
    """Unified Board interface for the HIVE protocol."""

    def __init__(
        self,
        db_path: str = "hive.db",
        channels_dir: str = "channels",
    ):
        self._sqlite = SQLiteTransport(db_path)
        self._jsonl = JSONLTransport(channels_dir)

    # --- Core Board Operations ---

    def put(
        self,
        *,
        type: str,
        from_agent: str,
        channel: str,
        data: dict[str, Any],
        ts: str | None = None,
        refs: list[str] | None = None,
        ttl: int = 0,
        tags: list[str] | None = None,
        sig: str | None = None,
    ) -> str:
        """Create a cell and write it to both transports. Returns cell ID."""
        cell = make_cell(
            type=type,
            from_agent=from_agent,
            channel=channel,
            data=data,
            ts=ts,
            refs=refs,
            ttl=ttl,
            tags=tags,
            sig=sig,
        )
        return self.put_cell(cell)

    def put_cell(self, cell: Cell) -> str:
        """Write a pre-built cell to both transports. Returns cell ID."""
        self._sqlite.put(cell)
        self._jsonl.put(cell)
        return cell.id

    def get(self, cell_id: str) -> Cell | None:
        """Retrieve a cell by ID."""
        return self._sqlite.get(cell_id)

    def query(self, **kwargs) -> list[Cell]:
        """Find cells matching criteria. See SQLiteTransport.query for params."""
        return self._sqlite.query(**kwargs)

    def refs(self, cell_id: str) -> list[Cell]:
        """Return all cells that reference the given ID."""
        return self._sqlite.refs(cell_id)

    def expire(self) -> int:
        """Remove expired cells. Returns count removed."""
        return self._sqlite.expire()

    def watch(self, channel: str, callback, type_filter: str | None = None):
        """Subscribe to new cells on a channel."""
        self._sqlite.watch(channel, callback, type_filter)

    # --- Convenience Methods for Common Cell Types ---

    def task(
        self,
        *,
        from_agent: str,
        channel: str,
        title: str,
        spec: str = "",
        bounty: int = 5,
        deadline: str | None = None,
        quality_gates: list[str] | None = None,
        race: bool = False,
        auto_assign: bool = False,
        refs: list[str] | None = None,
        tags: list[str] | None = None,
    ) -> str:
        """Create a task cell."""
        data = {
            "title": title,
            "spec": spec,
            "bounty": bounty,
            "race": race,
            "auto_assign": auto_assign,
        }
        if deadline:
            data["deadline"] = deadline
        if quality_gates:
            data["quality_gates"] = quality_gates
        return self.put(type="task", from_agent=from_agent, channel=channel, data=data, refs=refs, tags=tags)

    def card(
        self,
        *,
        from_agent: str,
        capabilities: list[str],
        cost_profile: dict[str, Any] | None = None,
        models: list[str] | None = None,
        channel: str = "roster",
    ) -> str:
        """Create an agent capability card."""
        data: dict[str, Any] = {"capabilities": capabilities}
        if cost_profile:
            data["cost_profile"] = cost_profile
        if models:
            data["models"] = models
        return self.put(type="card", from_agent=from_agent, channel=channel, data=data)

    def heartbeat(
        self,
        *,
        from_agent: str,
        contract_id: str,
        progress: int = 0,
        status: str = "working",
        channel: str = "roster",
    ) -> str:
        """Create a heartbeat cell."""
        return self.put(
            type="heartbeat",
            from_agent=from_agent,
            channel=channel,
            data={"contract_id": contract_id, "progress": progress, "status": status},
            refs=[contract_id],
            ttl=120,
        )

    def result(
        self,
        *,
        from_agent: str,
        channel: str,
        contract_id: str,
        output: str,
        artifacts: list[str] | None = None,
        metrics: dict | None = None,
    ) -> str:
        """Create a result cell."""
        data: dict[str, Any] = {"output": output}
        if artifacts:
            data["artifacts"] = artifacts
        if metrics:
            data["metrics"] = metrics
        return self.put(type="result", from_agent=from_agent, channel=channel, data=data, refs=[contract_id])

    def feedback(
        self,
        *,
        from_agent: str,
        channel: str,
        result_id: str,
        contract_id: str,
        score: int,
        notes: str = "",
        tags: list[str] | None = None,
    ) -> str:
        """Create a feedback cell."""
        return self.put(
            type="feedback",
            from_agent=from_agent,
            channel=channel,
            data={"score": score, "notes": notes},
            refs=[result_id, contract_id],
            tags=tags,
        )
```

**Step 4: Update `hive/__init__.py` with exports**

```python
# hive/__init__.py
"""HIVE: Hierarchical Inter-agent Virtual Exchange protocol.

Usage:
    from hive import HiveBoard, make_cell, Cell

    board = HiveBoard(db_path="hive.db", channels_dir="channels")
    task_id = board.task(from_agent="claude/1", channel="general", title="Do thing")
    cell = board.get(task_id)
"""
from hive.board import HiveBoard
from hive.cell import Cell, make_cell, cell_to_dict, cell_from_dict

__version__ = "1.0.0"
__all__ = ["HiveBoard", "Cell", "make_cell", "cell_to_dict", "cell_from_dict"]
```

**Step 5: Run ALL tests**

Run: `cd C:/tools/agent-comms && timeout 30 python -m pytest tests/ -v --timeout=30`
Expected: All tests PASS (cell + sqlite + jsonl + board)

**Step 6: Commit**

```bash
git add hive/board.py hive/__init__.py tests/test_board.py
git commit -m "feat(hive): HiveBoard facade with dual-write SQLite+JSONL"
```

---

## Phase 4: Coordination Layer (Layer 3)

### Task 6: Implement reputation scoring

**Files:**
- Create: `hive/coordination/reputation.py`
- Create: `tests/test_reputation.py`

**Step 1: Write failing tests**

```python
# tests/test_reputation.py
"""Tests for hive.coordination.reputation."""
import os
import tempfile
from hive.board import HiveBoard
from hive.coordination.reputation import reputation


def _make_board():
    tmpdir = tempfile.mkdtemp()
    return HiveBoard(db_path=os.path.join(tmpdir, "test.db"), channels_dir=os.path.join(tmpdir, "ch"))


class TestReputation:
    def test_no_feedback_returns_default(self):
        board = _make_board()
        score = reputation(board, "claude/1")
        assert score == 5.0  # neutral default

    def test_single_perfect_feedback(self):
        board = _make_board()
        # Create a minimal task->contract->result->feedback chain
        task_id = board.put(type="task", from_agent="claude/1", channel="general", data={"title": "test"})
        contract_id = board.put(type="contract", from_agent="claude/1", channel="general", data={"agent": "gemini/1"}, refs=[task_id])
        result_id = board.put(type="result", from_agent="gemini/1", channel="general", data={"output": "done"}, refs=[contract_id])
        board.feedback(from_agent="claude/1", channel="general", result_id=result_id, contract_id=contract_id, score=10)
        score = reputation(board, "gemini/1")
        assert score == 10.0

    def test_recent_feedback_weighted_higher(self):
        board = _make_board()
        # Old feedback (score=2), new feedback (score=9)
        task_id = board.put(type="task", from_agent="claude/1", channel="general", data={})
        c1 = board.put(type="contract", from_agent="claude/1", channel="general", data={"agent": "gemini/1"}, refs=[task_id], ts="2026-01-01T00:00:00+00:00")
        r1 = board.put(type="result", from_agent="gemini/1", channel="general", data={"output": "v1"}, refs=[c1], ts="2026-01-01T00:01:00+00:00")
        board.put(type="feedback", from_agent="claude/1", channel="general", data={"score": 2}, refs=[r1, c1], ts="2026-01-01T00:02:00+00:00")

        c2 = board.put(type="contract", from_agent="claude/1", channel="general", data={"agent": "gemini/1"}, refs=[task_id], ts="2026-03-01T00:00:00+00:00")
        r2 = board.put(type="result", from_agent="gemini/1", channel="general", data={"output": "v2"}, refs=[c2], ts="2026-03-01T00:01:00+00:00")
        board.put(type="feedback", from_agent="claude/1", channel="general", data={"score": 9}, refs=[r2, c2], ts="2026-03-01T00:02:00+00:00")

        score = reputation(board, "gemini/1")
        # Recent (9) should be weighted more than old (2)
        assert score > 5.5
```

**Step 2: Run tests to verify they fail**

Run: `cd C:/tools/agent-comms && timeout 30 python -m pytest tests/test_reputation.py -v --timeout=30`
Expected: FAIL

**Step 3: Implement reputation**

```python
# hive/coordination/reputation.py
"""Reputation scoring from feedback cells.

Uses exponential decay weighting — recent feedback matters more.
Default score is 5.0 (neutral) when no feedback exists.
"""
from hive.board import HiveBoard

DEFAULT_SCORE = 5.0
DECAY_FACTOR = 0.95


def reputation(board: HiveBoard, agent_id: str, capability: str | None = None) -> float:
    """Calculate reputation score for an agent.

    Finds all feedback cells for contracts assigned to this agent,
    applies exponential decay weighting (most recent first).
    """
    # Find all contracts where this agent was the worker
    contracts = board.query(type="contract")
    agent_contracts = [c for c in contracts if c.data.get("agent") == agent_id]

    if not agent_contracts:
        return DEFAULT_SCORE

    # Find all feedback referencing these contracts
    feedbacks = []
    for contract in agent_contracts:
        contract_feedbacks = board.refs(contract.id)
        for fb in contract_feedbacks:
            if fb.type == "feedback":
                if capability and capability not in fb.tags:
                    continue
                feedbacks.append(fb)

    if not feedbacks:
        return DEFAULT_SCORE

    # Sort by timestamp descending (most recent first)
    feedbacks.sort(key=lambda f: f.ts, reverse=True)

    # Exponential decay weighting
    weights = [DECAY_FACTOR ** i for i in range(len(feedbacks))]
    scores = [f.data.get("score", DEFAULT_SCORE) for f in feedbacks]

    total_weight = sum(weights)
    if total_weight == 0:
        return DEFAULT_SCORE

    return sum(s * w for s, w in zip(scores, weights)) / total_weight
```

**Step 4: Run tests**

Run: `cd C:/tools/agent-comms && timeout 30 python -m pytest tests/test_reputation.py -v --timeout=30`
Expected: All 3 tests PASS

**Step 5: Commit**

```bash
git add hive/coordination/reputation.py tests/test_reputation.py
git commit -m "feat(hive): Reputation scoring with exponential decay"
```

---

### Task 7: Implement capability-based task router

**Files:**
- Create: `hive/coordination/router.py`
- Create: `tests/test_router.py`

**Step 1: Write failing tests**

```python
# tests/test_router.py
"""Tests for hive.coordination.router."""
import os
import tempfile
from hive.board import HiveBoard
from hive.coordination.router import route_task


def _make_board():
    tmpdir = tempfile.mkdtemp()
    return HiveBoard(db_path=os.path.join(tmpdir, "test.db"), channels_dir=os.path.join(tmpdir, "ch"))


class TestRouter:
    def test_no_agents_returns_empty(self):
        board = _make_board()
        task_id = board.task(from_agent="claude/1", channel="general", title="test")
        task = board.get(task_id)
        result = route_task(board, task)
        assert result == []

    def test_routes_to_capable_agent(self):
        board = _make_board()
        board.card(from_agent="gemini/1", capabilities=["scanning", "data-analysis"])
        board.card(from_agent="claude/1", capabilities=["architecture", "protocol-work"])
        task_id = board.put(type="task", from_agent="claude/1", channel="general", data={"title": "scan codebase", "required_capabilities": ["scanning"]})
        task = board.get(task_id)
        rankings = route_task(board, task)
        assert len(rankings) > 0
        assert rankings[0][0] == "gemini/1"  # gemini should rank first for scanning

    def test_reputation_affects_ranking(self):
        board = _make_board()
        board.card(from_agent="agent/a", capabilities=["coding"])
        board.card(from_agent="agent/b", capabilities=["coding"])
        # Give agent/a good feedback
        task_id = board.put(type="task", from_agent="claude/1", channel="general", data={})
        c = board.put(type="contract", from_agent="claude/1", channel="general", data={"agent": "agent/a"}, refs=[task_id])
        r = board.put(type="result", from_agent="agent/a", channel="general", data={"output": "done"}, refs=[c])
        board.feedback(from_agent="claude/1", channel="general", result_id=r, contract_id=c, score=10)
        # Route a coding task
        task_id2 = board.put(type="task", from_agent="claude/1", channel="general", data={"title": "code it", "required_capabilities": ["coding"]})
        task2 = board.get(task_id2)
        rankings = route_task(board, task2)
        assert rankings[0][0] == "agent/a"
```

**Step 2: Run tests, verify fail. Step 3: Implement.**

```python
# hive/coordination/router.py
"""Capability-based task routing.

Matches task requirements against agent capability cards.
Score = capability_overlap * reputation / (1 + cost).
"""
from hive.board import HiveBoard
from hive.cell import Cell
from hive.coordination.reputation import reputation


def route_task(board: HiveBoard, task: Cell) -> list[tuple[str, float]]:
    """Rank agents by suitability for a task.

    Returns list of (agent_id, score) sorted by score descending.
    """
    required = set(task.data.get("required_capabilities", []))
    cards = board.query(type="card")

    if not cards:
        return []

    scores = []
    for card in cards:
        agent_id = card.from_agent
        capabilities = set(card.data.get("capabilities", []))

        # Capability overlap
        if required:
            overlap = len(required & capabilities) / len(required)
        else:
            overlap = 1.0 if capabilities else 0.5

        # Cost factor
        cost_profile = card.data.get("cost_profile", {})
        cost = cost_profile.get("output", 1)

        # Reputation
        rep = reputation(board, agent_id)

        score = overlap * rep / (1 + cost)
        scores.append((agent_id, score))

    scores.sort(key=lambda x: -x[1])
    return scores
```

**Step 4: Run tests**

Run: `cd C:/tools/agent-comms && timeout 30 python -m pytest tests/test_router.py -v --timeout=30`
Expected: All 3 tests PASS

**Step 5: Commit**

```bash
git add hive/coordination/router.py tests/test_router.py
git commit -m "feat(hive): Capability-based task router with reputation weighting"
```

---

### Task 8: Implement file lease management

**Files:**
- Create: `hive/coordination/leases.py`
- Create: `tests/test_leases.py`

**Step 1: Write failing tests**

```python
# tests/test_leases.py
"""Tests for hive.coordination.leases."""
import os
import tempfile
from hive.board import HiveBoard
from hive.coordination.leases import acquire_lease, release_lease, is_leased


def _make_board():
    tmpdir = tempfile.mkdtemp()
    return HiveBoard(db_path=os.path.join(tmpdir, "test.db"), channels_dir=os.path.join(tmpdir, "ch"))


class TestLeases:
    def test_acquire_lease_succeeds(self):
        board = _make_board()
        lease_id = acquire_lease(board, resource="src/main.py", holder="claude/1")
        assert lease_id is not None
        assert lease_id.startswith("hive:")

    def test_is_leased_after_acquire(self):
        board = _make_board()
        acquire_lease(board, resource="src/main.py", holder="claude/1")
        assert is_leased(board, resource="src/main.py") is True

    def test_is_leased_false_when_free(self):
        board = _make_board()
        assert is_leased(board, resource="src/main.py") is False

    def test_release_frees_resource(self):
        board = _make_board()
        lease_id = acquire_lease(board, resource="src/main.py", holder="claude/1")
        release_lease(board, lease_id=lease_id, holder="claude/1")
        assert is_leased(board, resource="src/main.py") is False

    def test_cannot_acquire_already_leased(self):
        board = _make_board()
        acquire_lease(board, resource="src/main.py", holder="claude/1")
        lease2 = acquire_lease(board, resource="src/main.py", holder="gemini/1")
        assert lease2 is None  # already leased
```

**Step 2: Run tests, verify fail. Step 3: Implement.**

```python
# hive/coordination/leases.py
"""Advisory file lease management.

Agents claim leases before editing files. Other agents check before claiming.
Leases are advisory (like flock in Unix). Bad actors get bad feedback scores.
Leases expire via TTL — no daemon needed.
"""
from hive.board import HiveBoard

DEFAULT_LEASE_TTL = 300  # 5 minutes


def acquire_lease(
    board: HiveBoard,
    *,
    resource: str,
    holder: str,
    ttl: int = DEFAULT_LEASE_TTL,
    channel: str = "roster",
) -> str | None:
    """Attempt to acquire a lease on a resource.

    Returns lease cell ID if acquired, None if already leased.
    """
    if is_leased(board, resource=resource):
        return None

    return board.put(
        type="lease",
        from_agent=holder,
        channel=channel,
        data={"resource": resource, "holder": holder},
        ttl=ttl,
        tags=[f"resource:{resource}"],
    )


def release_lease(
    board: HiveBoard,
    *,
    lease_id: str,
    holder: str,
    channel: str = "roster",
) -> str:
    """Release a lease."""
    return board.put(
        type="release",
        from_agent=holder,
        channel=channel,
        data={},
        refs=[lease_id],
    )


def is_leased(board: HiveBoard, *, resource: str) -> bool:
    """Check if a resource currently has an active lease."""
    # Find lease cells for this resource
    leases = board.query(type="lease", tags=[f"resource:{resource}"])
    for lease in leases:
        # Check if there's a release for this lease
        releases = board.refs(lease.id)
        if any(r.type == "release" for r in releases):
            continue  # released
        # If TTL > 0, the expire() mechanism handles it
        # If still in DB, it's active
        return True
    return False
```

**Step 4: Run tests**

Run: `cd C:/tools/agent-comms && timeout 30 python -m pytest tests/test_leases.py -v --timeout=30`
Expected: All 5 tests PASS

**Step 5: Commit**

```bash
git add hive/coordination/leases.py tests/test_leases.py
git commit -m "feat(hive): Advisory file lease management"
```

---

### Task 9: Implement stall detection

**Files:**
- Create: `hive/coordination/stall_detector.py`
- Create: `tests/test_stall_detector.py`

**Step 1: Write failing tests**

```python
# tests/test_stall_detector.py
"""Tests for hive.coordination.stall_detector."""
import os
import tempfile
from hive.board import HiveBoard
from hive.coordination.stall_detector import detect_stalls


def _make_board():
    tmpdir = tempfile.mkdtemp()
    return HiveBoard(db_path=os.path.join(tmpdir, "test.db"), channels_dir=os.path.join(tmpdir, "ch"))


class TestStallDetector:
    def test_no_contracts_no_stalls(self):
        board = _make_board()
        stalls = detect_stalls(board)
        assert stalls == []

    def test_contract_with_result_not_stalled(self):
        board = _make_board()
        task_id = board.put(type="task", from_agent="claude/1", channel="general", data={})
        contract_id = board.put(type="contract", from_agent="claude/1", channel="general", data={"agent": "gemini/1"}, refs=[task_id])
        board.put(type="result", from_agent="gemini/1", channel="general", data={"output": "done"}, refs=[contract_id])
        stalls = detect_stalls(board)
        assert stalls == []

    def test_old_contract_no_heartbeat_is_stalled(self):
        board = _make_board()
        task_id = board.put(type="task", from_agent="claude/1", channel="general", data={}, ts="2020-01-01T00:00:00+00:00")
        contract_id = board.put(type="contract", from_agent="claude/1", channel="general", data={"agent": "gemini/1"}, refs=[task_id], ts="2020-01-01T00:00:01+00:00")
        stalls = detect_stalls(board, timeout_seconds=60)
        assert len(stalls) == 1
        assert stalls[0]["contract_id"] == contract_id
        assert stalls[0]["agent"] == "gemini/1"
```

**Step 2: Run tests, verify fail. Step 3: Implement.**

```python
# hive/coordination/stall_detector.py
"""Heartbeat monitoring and stall detection.

Checks contracts without results. If the last heartbeat is older than
the timeout, emits a stall signal.
"""
from datetime import datetime, timezone
from typing import Any

from hive.board import HiveBoard


def detect_stalls(
    board: HiveBoard,
    timeout_seconds: int = 300,
) -> list[dict[str, Any]]:
    """Find contracts that appear stalled (no recent heartbeat, no result).

    Returns list of stall info dicts with contract_id, agent, last_heartbeat.
    Also emits signal cells to the board for each detected stall.
    """
    contracts = board.query(type="contract")
    stalls = []

    for contract in contracts:
        # Check if there's a result for this contract
        refs = board.refs(contract.id)
        has_result = any(r.type == "result" for r in refs)
        if has_result:
            continue

        # Check last heartbeat
        heartbeats = [r for r in refs if r.type == "heartbeat"]
        heartbeats.sort(key=lambda h: h.ts, reverse=True)

        last_hb_ts = heartbeats[0].ts if heartbeats else None
        now = datetime.now(timezone.utc)

        if last_hb_ts:
            try:
                last_dt = datetime.fromisoformat(last_hb_ts)
                age = (now - last_dt).total_seconds()
            except ValueError:
                age = timeout_seconds + 1
        else:
            # No heartbeats — check contract age
            try:
                contract_dt = datetime.fromisoformat(contract.ts)
                age = (now - contract_dt).total_seconds()
            except ValueError:
                age = timeout_seconds + 1

        if age > timeout_seconds:
            agent = contract.data.get("agent", "unknown")
            stall_info = {
                "contract_id": contract.id,
                "agent": agent,
                "last_heartbeat": last_hb_ts,
                "age_seconds": age,
            }
            stalls.append(stall_info)

            # Emit signal
            board.put(
                type="signal",
                from_agent="hive/stall-detector",
                channel=contract.channel,
                data={
                    "event": "stall_detected",
                    "payload": stall_info,
                },
                refs=[contract.id],
            )

    return stalls
```

**Step 4: Run tests**

Run: `cd C:/tools/agent-comms && timeout 30 python -m pytest tests/test_stall_detector.py -v --timeout=30`
Expected: All 3 tests PASS

**Step 5: Commit**

```bash
git add hive/coordination/stall_detector.py tests/test_stall_detector.py
git commit -m "feat(hive): Stall detection via heartbeat monitoring"
```

---

### Task 10: Implement task DAG resolution

**Files:**
- Create: `hive/coordination/dag.py`
- Create: `tests/test_dag.py`

**Step 1: Write failing tests**

```python
# tests/test_dag.py
"""Tests for hive.coordination.dag — task dependency resolution."""
import os
import tempfile
from hive.board import HiveBoard
from hive.coordination.dag import get_ready_tasks, get_task_deps


def _make_board():
    tmpdir = tempfile.mkdtemp()
    return HiveBoard(db_path=os.path.join(tmpdir, "test.db"), channels_dir=os.path.join(tmpdir, "ch"))


class TestDAG:
    def test_task_with_no_deps_is_ready(self):
        board = _make_board()
        board.task(from_agent="claude/1", channel="general", title="standalone")
        ready = get_ready_tasks(board, channel="general")
        assert len(ready) == 1

    def test_task_with_unfinished_dep_not_ready(self):
        board = _make_board()
        t1 = board.task(from_agent="claude/1", channel="general", title="step 1")
        board.put(type="task", from_agent="claude/1", channel="general", data={"title": "step 2"}, refs=[t1])
        ready = get_ready_tasks(board, channel="general")
        # Only step 1 should be ready (step 2 depends on step 1 result)
        assert len(ready) == 1
        assert ready[0].data["title"] == "step 1"

    def test_task_with_finished_dep_is_ready(self):
        board = _make_board()
        t1 = board.task(from_agent="claude/1", channel="general", title="step 1")
        # Complete step 1
        c1 = board.put(type="contract", from_agent="claude/1", channel="general", data={"agent": "gemini/1"}, refs=[t1])
        board.put(type="result", from_agent="gemini/1", channel="general", data={"output": "done"}, refs=[c1])
        # Step 2 depends on step 1
        board.put(type="task", from_agent="claude/1", channel="general", data={"title": "step 2"}, refs=[t1])
        ready = get_ready_tasks(board, channel="general")
        titles = [t.data["title"] for t in ready]
        assert "step 2" in titles

    def test_get_task_deps(self):
        board = _make_board()
        t1 = board.task(from_agent="claude/1", channel="general", title="A")
        t2_id = board.put(type="task", from_agent="claude/1", channel="general", data={"title": "B"}, refs=[t1])
        t2 = board.get(t2_id)
        deps = get_task_deps(board, t2)
        assert len(deps) == 1
        assert deps[0].data["title"] == "A"
```

**Step 2: Run tests, verify fail. Step 3: Implement.**

```python
# hive/coordination/dag.py
"""Task DAG resolution.

Tasks can reference other tasks via refs. A task is "ready" when all
referenced tasks have result cells.
"""
from hive.board import HiveBoard
from hive.cell import Cell


def get_task_deps(board: HiveBoard, task: Cell) -> list[Cell]:
    """Get all task cells that this task depends on (via refs)."""
    deps = []
    for ref_id in task.refs:
        ref_cell = board.get(ref_id)
        if ref_cell and ref_cell.type == "task":
            deps.append(ref_cell)
    return deps


def _task_has_result(board: HiveBoard, task_id: str) -> bool:
    """Check if a task has been completed (has a contract with a result)."""
    contracts = board.refs(task_id)
    for contract in contracts:
        if contract.type == "contract":
            results = board.refs(contract.id)
            if any(r.type == "result" for r in results):
                return True
    return False


def get_ready_tasks(board: HiveBoard, channel: str | None = None) -> list[Cell]:
    """Get all tasks that are ready to be worked on.

    A task is ready if:
    1. It has no task refs (no dependencies), OR
    2. All referenced tasks have results (dependencies satisfied)
    AND it does not already have a contract.
    """
    kwargs = {"type": "task"}
    if channel:
        kwargs["channel"] = channel
    tasks = board.query(**kwargs)

    ready = []
    for task in tasks:
        # Skip tasks that already have contracts
        task_refs = board.refs(task.id)
        if any(r.type == "contract" for r in task_refs):
            continue

        # Check dependencies
        deps = get_task_deps(board, task)
        if not deps:
            ready.append(task)
            continue

        # All deps must have results
        if all(_task_has_result(board, dep.id) for dep in deps):
            ready.append(task)

    return ready
```

**Step 4: Run tests**

Run: `cd C:/tools/agent-comms && timeout 30 python -m pytest tests/test_dag.py -v --timeout=30`
Expected: All 4 tests PASS

**Step 5: Commit**

```bash
git add hive/coordination/dag.py tests/test_dag.py
git commit -m "feat(hive): Task DAG resolution -- dependency-aware task readiness"
```

---

### Task 11: Implement agent racing

**Files:**
- Create: `hive/coordination/racing.py`
- Create: `tests/test_racing.py`

**Step 1: Write failing tests**

```python
# tests/test_racing.py
"""Tests for hive.coordination.racing."""
import os
import tempfile
from hive.board import HiveBoard
from hive.coordination.racing import start_race, get_race_results


def _make_board():
    tmpdir = tempfile.mkdtemp()
    return HiveBoard(db_path=os.path.join(tmpdir, "test.db"), channels_dir=os.path.join(tmpdir, "ch"))


class TestRacing:
    def test_start_race_creates_contracts(self):
        board = _make_board()
        task_id = board.put(type="task", from_agent="claude/1", channel="general", data={"title": "race", "race": True})
        agents = ["gemini/1", "codex/1"]
        contract_ids = start_race(board, task_id=task_id, agents=agents)
        assert len(contract_ids) == 2

    def test_race_results_collects_all(self):
        board = _make_board()
        task_id = board.put(type="task", from_agent="claude/1", channel="general", data={"title": "race", "race": True})
        contracts = start_race(board, task_id=task_id, agents=["gemini/1", "codex/1"])
        # Both agents submit results
        board.put(type="result", from_agent="gemini/1", channel="general", data={"output": "gemini answer"}, refs=[contracts[0]])
        board.put(type="result", from_agent="codex/1", channel="general", data={"output": "codex answer"}, refs=[contracts[1]])
        results = get_race_results(board, task_id=task_id)
        assert len(results) == 2
```

**Step 2: Run tests, verify fail. Step 3: Implement.**

```python
# hive/coordination/racing.py
"""Multi-agent racing.

When a task has race=True, multiple agents get contracts for the same task.
All results are collected and compared.
"""
from hive.board import HiveBoard
from hive.cell import Cell


def start_race(
    board: HiveBoard,
    *,
    task_id: str,
    agents: list[str],
    channel: str = "general",
) -> list[str]:
    """Create contracts for multiple agents on the same task (racing).

    Returns list of contract cell IDs.
    """
    contract_ids = []
    for agent in agents:
        contract_id = board.put(
            type="contract",
            from_agent="hive/racing",
            channel=channel,
            data={"agent": agent, "race": True},
            refs=[task_id],
        )
        contract_ids.append(contract_id)
    return contract_ids


def get_race_results(board: HiveBoard, *, task_id: str) -> list[Cell]:
    """Get all results submitted for a racing task."""
    contracts = board.refs(task_id)
    race_contracts = [c for c in contracts if c.type == "contract"]

    results = []
    for contract in race_contracts:
        contract_refs = board.refs(contract.id)
        for cell in contract_refs:
            if cell.type == "result":
                results.append(cell)
    return results
```

**Step 4: Run tests**

Run: `cd C:/tools/agent-comms && timeout 30 python -m pytest tests/test_racing.py -v --timeout=30`
Expected: All 2 tests PASS

**Step 5: Commit**

```bash
git add hive/coordination/racing.py tests/test_racing.py
git commit -m "feat(hive): Multi-agent racing coordination"
```

---

### Task 12: Implement evolution feedback loops

**Files:**
- Create: `hive/coordination/evolution.py`
- Create: `tests/test_evolution.py`

**Step 1: Write failing tests**

```python
# tests/test_evolution.py
"""Tests for hive.coordination.evolution."""
import os
import tempfile
from hive.board import HiveBoard
from hive.coordination.evolution import evolve


def _make_board():
    tmpdir = tempfile.mkdtemp()
    return HiveBoard(db_path=os.path.join(tmpdir, "test.db"), channels_dir=os.path.join(tmpdir, "ch"))


class TestEvolution:
    def test_evolve_with_no_data_emits_nothing(self):
        board = _make_board()
        signals = evolve(board)
        assert signals == []

    def test_evolve_detects_high_failure_rate(self):
        board = _make_board()
        # Create 5 tasks with 4 bad scores
        for i in range(5):
            t = board.put(type="task", from_agent="claude/1", channel="general", data={}, tags=["task_type:coding"], ts=f"2026-03-01T{i:02d}:00:00+00:00")
            c = board.put(type="contract", from_agent="claude/1", channel="general", data={"agent": "agent/a"}, refs=[t], ts=f"2026-03-01T{i:02d}:01:00+00:00")
            r = board.put(type="result", from_agent="agent/a", channel="general", data={"output": "x"}, refs=[c], ts=f"2026-03-01T{i:02d}:02:00+00:00")
            score = 3 if i < 4 else 8  # 4 bad, 1 good = 80% failure
            board.put(type="feedback", from_agent="claude/1", channel="general", data={"score": score}, refs=[r, c], tags=["task_type:coding"], ts=f"2026-03-01T{i:02d}:03:00+00:00")

        signals = evolve(board)
        events = [s["event"] for s in signals]
        assert "high_failure_rate" in events
```

**Step 2: Run tests, verify fail. Step 3: Implement.**

```python
# hive/coordination/evolution.py
"""Self-improvement feedback loops.

Analyzes feedback patterns to detect performance declines and high failure rates.
Emits signal cells that the orchestrator can react to.
"""
from collections import defaultdict
from typing import Any

from hive.board import HiveBoard


FAILURE_THRESHOLD = 5  # scores below this are considered failures
FAILURE_RATE_ALERT = 0.3  # 30% failure rate triggers signal


def evolve(board: HiveBoard) -> list[dict[str, Any]]:
    """Analyze feedback patterns and emit improvement signals.

    Returns list of signal info dicts for signals emitted.
    """
    feedbacks = board.query(type="feedback")
    if not feedbacks:
        return []

    signals = []

    # Check failure rates by task_type tag
    by_type: dict[str, list] = defaultdict(list)
    for fb in feedbacks:
        for tag in fb.tags:
            if tag.startswith("task_type:"):
                task_type = tag.split(":", 1)[1]
                by_type[task_type].append(fb)

    for task_type, type_feedbacks in by_type.items():
        if len(type_feedbacks) < 3:
            continue  # not enough data
        fail_count = sum(1 for f in type_feedbacks if f.data.get("score", 5) < FAILURE_THRESHOLD)
        fail_rate = fail_count / len(type_feedbacks)
        if fail_rate > FAILURE_RATE_ALERT:
            signal_data = {
                "event": "high_failure_rate",
                "payload": {
                    "task_type": task_type,
                    "fail_rate": round(fail_rate, 2),
                    "sample_size": len(type_feedbacks),
                },
            }
            board.put(
                type="signal",
                from_agent="hive/evolution",
                channel="roster",
                data=signal_data,
            )
            signals.append(signal_data)

    return signals
```

**Step 4: Run tests**

Run: `cd C:/tools/agent-comms && timeout 30 python -m pytest tests/test_evolution.py -v --timeout=30`
Expected: All 2 tests PASS

**Step 5: Commit**

```bash
git add hive/coordination/evolution.py tests/test_evolution.py
git commit -m "feat(hive): Evolution feedback loops -- failure rate detection"
```

---

## Phase 5: MCP Server (Layer 4)

### Task 13: Implement MCP server wrapping Board operations

**Files:**
- Create: `hive/mcp/server.py`
- Create: `hive/mcp/tools.py`
- Create: `tests/test_mcp_tools.py`

This exposes all 6 Board operations + convenience methods as MCP tools, so any MCP-capable agent can participate in HIVE natively.

**Step 1: Write failing tests for tool definitions**

```python
# tests/test_mcp_tools.py
"""Tests for hive.mcp.tools — MCP tool definitions."""
from hive.mcp.tools import get_tool_definitions, execute_tool
import os
import tempfile
from hive.board import HiveBoard


def _make_board():
    tmpdir = tempfile.mkdtemp()
    return HiveBoard(db_path=os.path.join(tmpdir, "test.db"), channels_dir=os.path.join(tmpdir, "ch"))


class TestToolDefinitions:
    def test_tool_definitions_exist(self):
        tools = get_tool_definitions()
        assert len(tools) > 0
        names = [t["name"] for t in tools]
        assert "hive_put" in names
        assert "hive_get" in names
        assert "hive_query" in names
        assert "hive_task" in names

    def test_each_tool_has_description(self):
        for tool in get_tool_definitions():
            assert "description" in tool
            assert len(tool["description"]) > 10


class TestToolExecution:
    def test_hive_put_via_execute(self):
        board = _make_board()
        result = execute_tool(board, "hive_put", {
            "type": "task",
            "from_agent": "claude/1",
            "channel": "general",
            "data": {"title": "test"},
        })
        assert "id" in result
        assert result["id"].startswith("hive:")

    def test_hive_get_via_execute(self):
        board = _make_board()
        put_result = execute_tool(board, "hive_put", {
            "type": "task",
            "from_agent": "claude/1",
            "channel": "general",
            "data": {"title": "test"},
        })
        get_result = execute_tool(board, "hive_get", {"id": put_result["id"]})
        assert get_result["cell"]["type"] == "task"

    def test_hive_query_via_execute(self):
        board = _make_board()
        execute_tool(board, "hive_put", {
            "type": "task", "from_agent": "claude/1", "channel": "general", "data": {},
        })
        result = execute_tool(board, "hive_query", {"type": "task"})
        assert len(result["cells"]) == 1

    def test_hive_task_convenience(self):
        board = _make_board()
        result = execute_tool(board, "hive_task", {
            "from_agent": "claude/1", "channel": "general", "title": "Do thing",
        })
        assert "id" in result
```

**Step 2: Run tests, verify fail. Step 3: Implement.**

```python
# hive/mcp/tools.py
"""MCP tool definitions for HIVE Board operations.

Each Board operation becomes an MCP tool. Any MCP-capable agent
can participate in the HIVE protocol natively.
"""
from typing import Any

from hive.board import HiveBoard
from hive.cell import cell_to_dict


def get_tool_definitions() -> list[dict[str, Any]]:
    """Return MCP tool definitions for all HIVE operations."""
    return [
        {
            "name": "hive_put",
            "description": "Write a cell to the HIVE board. Returns the content-addressable cell ID.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "type": {"type": "string", "description": "Cell type (task, card, bid, contract, result, feedback, lease, release, heartbeat, signal, clock-in, clock-out, cancel)"},
                    "from_agent": {"type": "string", "description": "Agent identity (e.g. claude/1, gemini/signx)"},
                    "channel": {"type": "string", "description": "Channel name (e.g. general, signx-intel)"},
                    "data": {"type": "object", "description": "Type-specific payload"},
                    "refs": {"type": "array", "items": {"type": "string"}, "description": "IDs of related cells"},
                    "ttl": {"type": "integer", "description": "Seconds until expiry (0 = permanent)"},
                    "tags": {"type": "array", "items": {"type": "string"}, "description": "Freeform key:value tags"},
                },
                "required": ["type", "from_agent", "channel", "data"],
            },
        },
        {
            "name": "hive_get",
            "description": "Retrieve a cell by its ID.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "id": {"type": "string", "description": "Cell ID (hive:...)"},
                },
                "required": ["id"],
            },
        },
        {
            "name": "hive_query",
            "description": "Find cells matching criteria. Returns up to `limit` cells.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "type": {"type": "string"},
                    "channel": {"type": "string"},
                    "from_prefix": {"type": "string", "description": "Agent prefix match (e.g. 'claude' matches 'claude/1')"},
                    "since": {"type": "string", "description": "ISO-8601 timestamp -- cells after this time"},
                    "tags": {"type": "array", "items": {"type": "string"}},
                    "refs": {"type": "string", "description": "Cell ID -- find cells referencing this"},
                    "limit": {"type": "integer", "default": 100},
                    "order": {"type": "string", "enum": ["asc", "desc"], "default": "asc"},
                },
            },
        },
        {
            "name": "hive_refs",
            "description": "Return all cells that reference a given cell ID (reverse DAG traversal).",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "id": {"type": "string", "description": "Cell ID to find references for"},
                },
                "required": ["id"],
            },
        },
        {
            "name": "hive_expire",
            "description": "Remove all cells past their TTL. Returns count removed.",
            "inputSchema": {"type": "object", "properties": {}},
        },
        {
            "name": "hive_task",
            "description": "Create a task cell (convenience).",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "from_agent": {"type": "string"},
                    "channel": {"type": "string"},
                    "title": {"type": "string"},
                    "spec": {"type": "string", "default": ""},
                    "bounty": {"type": "integer", "default": 5},
                    "race": {"type": "boolean", "default": False},
                    "auto_assign": {"type": "boolean", "default": False},
                    "refs": {"type": "array", "items": {"type": "string"}},
                    "tags": {"type": "array", "items": {"type": "string"}},
                },
                "required": ["from_agent", "channel", "title"],
            },
        },
        {
            "name": "hive_card",
            "description": "Publish an agent capability card.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "from_agent": {"type": "string"},
                    "capabilities": {"type": "array", "items": {"type": "string"}},
                    "cost_profile": {"type": "object"},
                    "models": {"type": "array", "items": {"type": "string"}},
                },
                "required": ["from_agent", "capabilities"],
            },
        },
        {
            "name": "hive_heartbeat",
            "description": "Send a heartbeat (alive signal while working on a contract).",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "from_agent": {"type": "string"},
                    "contract_id": {"type": "string"},
                    "progress": {"type": "integer", "minimum": 0, "maximum": 100},
                    "status": {"type": "string", "default": "working"},
                },
                "required": ["from_agent", "contract_id"],
            },
        },
        {
            "name": "hive_feedback",
            "description": "Score a result (1-10). Feeds into reputation.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "from_agent": {"type": "string"},
                    "channel": {"type": "string"},
                    "result_id": {"type": "string"},
                    "contract_id": {"type": "string"},
                    "score": {"type": "integer", "minimum": 1, "maximum": 10},
                    "notes": {"type": "string", "default": ""},
                    "tags": {"type": "array", "items": {"type": "string"}},
                },
                "required": ["from_agent", "channel", "result_id", "contract_id", "score"],
            },
        },
    ]


def execute_tool(board: HiveBoard, tool_name: str, args: dict[str, Any]) -> dict[str, Any]:
    """Execute an MCP tool call against the board."""
    if tool_name == "hive_put":
        cell_id = board.put(
            type=args["type"],
            from_agent=args["from_agent"],
            channel=args["channel"],
            data=args.get("data", {}),
            refs=args.get("refs"),
            ttl=args.get("ttl", 0),
            tags=args.get("tags"),
        )
        return {"id": cell_id}

    elif tool_name == "hive_get":
        cell = board.get(args["id"])
        if cell is None:
            return {"cell": None}
        return {"cell": cell_to_dict(cell)}

    elif tool_name == "hive_query":
        query_args = {k: v for k, v in args.items() if v is not None}
        cells = board.query(**query_args)
        return {"cells": [cell_to_dict(c) for c in cells]}

    elif tool_name == "hive_refs":
        cells = board.refs(args["id"])
        return {"cells": [cell_to_dict(c) for c in cells]}

    elif tool_name == "hive_expire":
        count = board.expire()
        return {"removed": count}

    elif tool_name == "hive_task":
        cell_id = board.task(
            from_agent=args["from_agent"],
            channel=args["channel"],
            title=args["title"],
            spec=args.get("spec", ""),
            bounty=args.get("bounty", 5),
            race=args.get("race", False),
            auto_assign=args.get("auto_assign", False),
            refs=args.get("refs"),
            tags=args.get("tags"),
        )
        return {"id": cell_id}

    elif tool_name == "hive_card":
        cell_id = board.card(
            from_agent=args["from_agent"],
            capabilities=args["capabilities"],
            cost_profile=args.get("cost_profile"),
            models=args.get("models"),
        )
        return {"id": cell_id}

    elif tool_name == "hive_heartbeat":
        cell_id = board.heartbeat(
            from_agent=args["from_agent"],
            contract_id=args["contract_id"],
            progress=args.get("progress", 0),
            status=args.get("status", "working"),
        )
        return {"id": cell_id}

    elif tool_name == "hive_feedback":
        cell_id = board.feedback(
            from_agent=args["from_agent"],
            channel=args["channel"],
            result_id=args["result_id"],
            contract_id=args["contract_id"],
            score=args["score"],
            notes=args.get("notes", ""),
            tags=args.get("tags"),
        )
        return {"id": cell_id}

    else:
        return {"error": f"Unknown tool: {tool_name}"}
```

**Step 4: Run tests**

Run: `cd C:/tools/agent-comms && timeout 30 python -m pytest tests/test_mcp_tools.py -v --timeout=30`
Expected: All 6 tests PASS

**Step 5: Commit**

```bash
git add hive/mcp/tools.py tests/test_mcp_tools.py
git commit -m "feat(hive): MCP tool definitions for all Board operations"
```

---

### Task 14: Implement MCP server (stdio transport)

**Files:**
- Create: `hive/mcp/server.py`

This is the actual MCP server that can be registered in Claude Code's `settings.json`.
Uses `sys.stdin`/`sys.stdout` JSON-RPC per MCP spec.

**Step 1: Implement MCP server**

```python
# hive/mcp/server.py
"""MCP server for HIVE — exposes Board operations as MCP tools.

Run: python -m hive.mcp.server [--db hive.db] [--channels channels/]

Register in Claude Code settings.json:
{
  "mcpServers": {
    "hive": {
      "command": "python",
      "args": ["-m", "hive.mcp.server", "--db", "C:/tools/agent-comms/hive.db", "--channels", "C:/tools/agent-comms/channels"]
    }
  }
}
"""
import json
import sys
from typing import Any

from hive.board import HiveBoard
from hive.mcp.tools import get_tool_definitions, execute_tool


def _read_message() -> dict | None:
    """Read a JSON-RPC message from stdin."""
    # MCP uses Content-Length headers (LSP-style)
    headers: dict[str, str] = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        line_str = line.decode("utf-8").strip()
        if not line_str:
            break  # empty line = end of headers
        if ":" in line_str:
            key, value = line_str.split(":", 1)
            headers[key.strip().lower()] = value.strip()

    content_length = int(headers.get("content-length", "0"))
    if content_length == 0:
        return None

    body = sys.stdin.buffer.read(content_length)
    return json.loads(body.decode("utf-8"))


def _write_message(msg: dict):
    """Write a JSON-RPC message to stdout."""
    body = json.dumps(msg).encode("utf-8")
    header = f"Content-Length: {len(body)}\r\n\r\n".encode("utf-8")
    sys.stdout.buffer.write(header + body)
    sys.stdout.buffer.flush()


def _make_response(request_id: Any, result: Any) -> dict:
    return {"jsonrpc": "2.0", "id": request_id, "result": result}


def _make_error(request_id: Any, code: int, message: str) -> dict:
    return {"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": message}}


def run_server(db_path: str = "hive.db", channels_dir: str = "channels"):
    """Run the HIVE MCP server (stdio transport)."""
    board = HiveBoard(db_path=db_path, channels_dir=channels_dir)
    tools = get_tool_definitions()

    while True:
        msg = _read_message()
        if msg is None:
            break

        request_id = msg.get("id")
        method = msg.get("method", "")
        params = msg.get("params", {})

        if method == "initialize":
            _write_message(_make_response(request_id, {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "hive", "version": "1.0.0"},
            }))

        elif method == "notifications/initialized":
            pass  # no response needed

        elif method == "tools/list":
            tool_list = [
                {
                    "name": t["name"],
                    "description": t["description"],
                    "inputSchema": t["inputSchema"],
                }
                for t in tools
            ]
            _write_message(_make_response(request_id, {"tools": tool_list}))

        elif method == "tools/call":
            tool_name = params.get("name", "")
            tool_args = params.get("arguments", {})
            try:
                result = execute_tool(board, tool_name, tool_args)
                _write_message(_make_response(request_id, {
                    "content": [{"type": "text", "text": json.dumps(result, indent=2)}],
                }))
            except Exception as e:
                _write_message(_make_response(request_id, {
                    "content": [{"type": "text", "text": json.dumps({"error": str(e)})}],
                    "isError": True,
                }))

        else:
            _write_message(_make_error(request_id, -32601, f"Method not found: {method}"))


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="HIVE MCP Server")
    parser.add_argument("--db", default="C:/tools/agent-comms/hive.db")
    parser.add_argument("--channels", default="C:/tools/agent-comms/channels")
    args = parser.parse_args()
    run_server(db_path=args.db, channels_dir=args.channels)
```

**Step 2: Create `hive/__main__.py` for `python -m hive.mcp.server`**

```python
# hive/mcp/__main__.py
"""Allow running as: python -m hive.mcp"""
from hive.mcp.server import run_server
import argparse

parser = argparse.ArgumentParser(description="HIVE MCP Server")
parser.add_argument("--db", default="C:/tools/agent-comms/hive.db")
parser.add_argument("--channels", default="C:/tools/agent-comms/channels")
args = parser.parse_args()
run_server(db_path=args.db, channels_dir=args.channels)
```

**Step 3: Commit**

```bash
git add hive/mcp/server.py hive/mcp/__main__.py
git commit -m "feat(hive): MCP server (stdio transport) for native agent integration"
```

---

## Phase 6: comms.sh Migration (Layer 4)

### Task 15: Add `comms hive` subcommand to bridge bash CLI to Python

**Files:**
- Modify: `comms.sh` (add `hive` subcommand)
- Create: `tests/test_comms_hive.sh` (bash integration test)

This bridges the existing `comms.sh` CLI to the HIVE Python package. Agents using `comms.sh` can now dual-write to HIVE.

**Step 1: Add hive subcommand to comms.sh**

Add this case to the `comms()` function in `comms.sh`, before the `help|*)` case:

```bash
    hive)
      # comms hive <subcommand> [args] — bridge to HIVE Python package
      local subcmd="${1:-help}"
      shift 2>/dev/null
      case "$subcmd" in
        put)
          # comms hive put <type> <channel> <data_json>
          local cell_type="$1" channel="$2" data="${3:-"{}"}"
          python -c "
import sys, json
sys.path.insert(0, '${COMMS_DIR}')
from hive import HiveBoard
board = HiveBoard(db_path='${COMMS_DIR}/hive.db', channels_dir='${CHANNELS_DIR}')
cell_id = board.put(type=sys.argv[1], from_agent=sys.argv[2], channel=sys.argv[3], data=json.loads(sys.argv[4]))
print(cell_id)
" "$cell_type" "$COMMS_AGENT" "$channel" "$data"
          ;;
        get)
          # comms hive get <cell_id>
          python -c "
import sys, json
sys.path.insert(0, '${COMMS_DIR}')
from hive import HiveBoard, cell_to_dict
board = HiveBoard(db_path='${COMMS_DIR}/hive.db', channels_dir='${CHANNELS_DIR}')
cell = board.get(sys.argv[1])
if cell:
    print(json.dumps(cell_to_dict(cell), indent=2))
else:
    print('(not found)')
" "$1"
          ;;
        query)
          # comms hive query [--type X] [--channel X] [--from X] [--limit N]
          local query_type="" query_channel="" query_from="" query_limit="20"
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --type) query_type="$2"; shift 2 ;;
              --channel) query_channel="$2"; shift 2 ;;
              --from) query_from="$2"; shift 2 ;;
              --limit) query_limit="$2"; shift 2 ;;
              *) shift ;;
            esac
          done
          python -c "
import sys, json
sys.path.insert(0, '${COMMS_DIR}')
from hive import HiveBoard, cell_to_dict
board = HiveBoard(db_path='${COMMS_DIR}/hive.db', channels_dir='${CHANNELS_DIR}')
kwargs = {}
if '$query_type': kwargs['type'] = '$query_type'
if '$query_channel': kwargs['channel'] = '$query_channel'
if '$query_from': kwargs['from_prefix'] = '$query_from'
kwargs['limit'] = int('$query_limit')
cells = board.query(**kwargs)
for c in cells:
    d = cell_to_dict(c)
    print(f\"[{d['ts'][:19]}] {d['from']:>16} | {d['type']:>10} | {json.dumps(d['data'])[:60]}\")
print(f'({len(cells)} cells)')
"
          ;;
        status)
          # comms hive status — board statistics
          python -c "
import sys
sys.path.insert(0, '${COMMS_DIR}')
from hive import HiveBoard
board = HiveBoard(db_path='${COMMS_DIR}/hive.db', channels_dir='${CHANNELS_DIR}')
types = ['task','card','contract','result','bid','heartbeat','feedback','signal','lease','release','clock-in','clock-out','cancel']
print('=== HIVE Board Status ===')
total = 0
for t in types:
    cells = board.query(type=t)
    if cells:
        print(f'  {t:>15}: {len(cells)}')
        total += len(cells)
print(f'  {\"TOTAL\":>15}: {total}')
"
          ;;
        *)
          cat <<'HIVEEOF'
comms hive — bridge to HIVE Protocol (Python)

  comms hive put <type> <channel> <data_json>    Write a cell
  comms hive get <cell_id>                        Get cell by ID
  comms hive query [--type X] [--channel X]       Query cells
  comms hive status                               Board statistics
HIVEEOF
          ;;
      esac
      ;;
```

**Step 2: Test manually**

```bash
export COMMS_AGENT="claude/1"
source C:/tools/agent-comms/comms.sh
comms hive status
comms hive put task general '{"title":"test from bash"}'
comms hive query --type task
```

**Step 3: Commit**

```bash
git add comms.sh
git commit -m "feat(hive): Bridge comms.sh CLI to HIVE Python package"
```

---

## Phase 7: Integration Testing

### Task 16: Full lifecycle integration test

**Files:**
- Create: `tests/test_integration.py`

End-to-end test of the complete task lifecycle: task -> bid -> contract -> heartbeat -> result -> feedback.

**Step 1: Write integration test**

```python
# tests/test_integration.py
"""Integration test — full HIVE task lifecycle."""
import os
import tempfile
from hive.board import HiveBoard
from hive.coordination.router import route_task
from hive.coordination.reputation import reputation
from hive.coordination.stall_detector import detect_stalls
from hive.coordination.dag import get_ready_tasks
from hive.coordination.leases import acquire_lease, release_lease, is_leased


def _make_board():
    tmpdir = tempfile.mkdtemp()
    return HiveBoard(db_path=os.path.join(tmpdir, "test.db"), channels_dir=os.path.join(tmpdir, "ch")), tmpdir


class TestFullLifecycle:
    def test_task_to_feedback(self):
        """Complete lifecycle: task -> card -> route -> contract -> heartbeat -> result -> feedback -> reputation."""
        board, tmpdir = _make_board()

        # 1. Agent publishes capability card
        board.card(from_agent="gemini/1", capabilities=["scanning", "data-analysis"],
                    cost_profile={"input": 0.15, "output": 0.6, "currency": "USD"})

        # 2. Orchestrator creates task
        task_id = board.task(from_agent="claude/1", channel="signx-intel",
                             title="Scan codebase for dead imports",
                             spec="Use rg to find unused imports in src/",
                             bounty=7, tags=["task_type:scanning"])

        # 3. Route task to best agent
        task = board.get(task_id)
        rankings = route_task(board, task)
        assert len(rankings) > 0
        best_agent = rankings[0][0]
        assert best_agent == "gemini/1"

        # 4. Create contract
        contract_id = board.put(type="contract", from_agent="claude/1", channel="signx-intel",
                                 data={"agent": best_agent, "deliverables": ["dead_imports.txt"]},
                                 refs=[task_id])

        # 5. Agent sends heartbeat
        board.heartbeat(from_agent="gemini/1", contract_id=contract_id, progress=50, status="scanning src/")

        # 6. Agent delivers result
        result_id = board.result(from_agent="gemini/1", channel="signx-intel",
                                  contract_id=contract_id, output="Found 12 dead imports",
                                  artifacts=["dead_imports.txt"])

        # 7. Reviewer scores result
        board.feedback(from_agent="claude/1", channel="signx-intel",
                        result_id=result_id, contract_id=contract_id,
                        score=9, notes="Clean work, accurate results",
                        tags=["task_type:scanning"])

        # 8. Check reputation improved
        rep = reputation(board, "gemini/1")
        assert rep == 9.0  # single feedback, score is the reputation

        # 9. Verify no stalls
        stalls = detect_stalls(board)
        assert stalls == []

        # 10. Verify JSONL files created
        assert os.path.exists(os.path.join(tmpdir, "ch", "signx-intel.jsonl"))
        assert os.path.exists(os.path.join(tmpdir, "ch", "roster.jsonl"))

    def test_dag_lifecycle(self):
        """Tasks with dependencies execute in order."""
        board, _ = _make_board()

        # Create DAG: A -> B -> C
        t_a = board.task(from_agent="claude/1", channel="general", title="Extract data")
        t_b_id = board.put(type="task", from_agent="claude/1", channel="general",
                            data={"title": "Analyze trends"}, refs=[t_a])
        t_c_id = board.put(type="task", from_agent="claude/1", channel="general",
                            data={"title": "Generate report"}, refs=[t_b_id])

        # Only A should be ready
        ready = get_ready_tasks(board, channel="general")
        assert len(ready) == 1
        assert ready[0].data["title"] == "Extract data"

        # Complete A
        c_a = board.put(type="contract", from_agent="claude/1", channel="general",
                         data={"agent": "gemini/1"}, refs=[t_a])
        board.put(type="result", from_agent="gemini/1", channel="general",
                   data={"output": "data extracted"}, refs=[c_a])

        # Now B should be ready
        ready = get_ready_tasks(board, channel="general")
        titles = [t.data["title"] for t in ready]
        assert "Analyze trends" in titles
        assert "Generate report" not in titles

    def test_lease_lifecycle(self):
        """File leases prevent conflicts."""
        board, _ = _make_board()

        # Agent 1 acquires lease
        lease_id = acquire_lease(board, resource="src/parser.py", holder="claude/1")
        assert lease_id is not None
        assert is_leased(board, resource="src/parser.py")

        # Agent 2 cannot acquire
        assert acquire_lease(board, resource="src/parser.py", holder="gemini/1") is None

        # Agent 1 releases
        release_lease(board, lease_id=lease_id, holder="claude/1")
        assert not is_leased(board, resource="src/parser.py")

        # Now agent 2 can acquire
        lease2 = acquire_lease(board, resource="src/parser.py", holder="gemini/1")
        assert lease2 is not None
```

**Step 2: Run ALL tests**

Run: `cd C:/tools/agent-comms && timeout 60 python -m pytest tests/ -v --timeout=30`
Expected: ALL tests PASS

**Step 3: Commit**

```bash
git add tests/test_integration.py
git commit -m "test(hive): Full lifecycle integration tests"
```

---

## Phase 8: Final Polish

### Task 17: Register MCP server in Claude Code settings

**Files:**
- No code changes — configuration only

**Step 1: Register the HIVE MCP server**

Run from bash (not inside Claude Code):
```bash
claude mcp add hive python -- -m hive.mcp.server --db C:/tools/agent-comms/hive.db --channels C:/tools/agent-comms/channels
```

Or manually add to project `.mcp.json`:
```json
{
  "mcpServers": {
    "hive": {
      "command": "python",
      "args": ["-m", "hive.mcp.server", "--db", "C:/tools/agent-comms/hive.db", "--channels", "C:/tools/agent-comms/channels"],
      "cwd": "C:/tools/agent-comms"
    }
  }
}
```

**Step 2: Verify MCP server starts**

```bash
cd C:/tools/agent-comms && echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test"}}}' | python -m hive.mcp.server
```

Expected: JSON response with serverInfo

### Task 18: Push to GitHub and tag release

**Step 1: Run final test suite**

```bash
cd C:/tools/agent-comms && timeout 60 python -m pytest tests/ -v --timeout=30
```

Expected: All tests PASS (should be 40+ tests across 9 test files)

**Step 2: Push and tag**

```bash
cd C:/tools/agent-comms
git push
git tag -a v1.0.0 -m "HIVE Protocol v1.0.0 — first release"
git push origin v1.0.0
```

---

## Summary

| Phase | Tasks | What It Builds |
|-------|-------|----------------|
| 0 | 1 | Project scaffolding |
| 1 | 2 | Cell dataclass + content-addressable IDs |
| 2 | 3-4 | SQLite transport + JSONL projection |
| 3 | 5 | HiveBoard facade (dual-write) |
| 4 | 6-12 | Coordination layer (reputation, router, leases, stalls, DAGs, racing, evolution) |
| 5 | 13-14 | MCP server |
| 6 | 15 | comms.sh bridge |
| 7 | 16 | Integration testing |
| 8 | 17-18 | MCP registration + release |

**Total: 18 tasks, ~50 tests, zero external dependencies.**

Each task is independently committable. Each phase builds on the last. The existing `comms.sh` keeps working throughout — HIVE is additive, not a rewrite.
