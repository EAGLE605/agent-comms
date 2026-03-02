"""Tests for hive.cell -- the atomic unit of HIVE."""
import hashlib
import json

from hive.cell import Cell, cell_from_dict, cell_to_dict, make_cell


class TestCellCreation:
    def test_make_cell_returns_cell(self):
        c = make_cell(type="task", from_agent="claude/1", channel="general", data={"title": "test"})
        assert isinstance(c, Cell)

    def test_cell_has_hive_prefix_id(self):
        c = make_cell(type="task", from_agent="claude/1", channel="general", data={"title": "test"})
        assert c.id.startswith("hive:")

    def test_cell_id_is_16_hex_chars_after_prefix(self):
        c = make_cell(type="task", from_agent="claude/1", channel="general", data={"title": "test"})
        hex_part = c.id[5:]
        assert len(hex_part) == 16
        int(hex_part, 16)  # should not raise

    def test_cell_id_is_deterministic(self):
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
        assert "T" in c.ts

    def test_cell_defaults(self):
        c = make_cell(type="task", from_agent="claude/1", channel="general", data={})
        assert c.refs == ()
        assert c.ttl == 0
        assert c.tags == ()
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
        assert c.refs == ()
        assert c.ttl == 0
        assert c.tags == ()
        assert c.sig is None


class TestCellIDGeneration:
    def test_id_formula_matches_spec(self):
        """ID = hive: + SHA256(type + from + ts + channel + JSON(data))[:16]"""
        ts = "2026-03-01T22:00:00-06:00"
        c = make_cell(type="task", from_agent="claude/1", channel="general", data={"a": 1}, ts=ts)
        payload = "task" + "claude/1" + ts + "general" + json.dumps({"a": 1}, separators=(",", ":"), sort_keys=True)
        expected_hash = hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]
        assert c.id == f"hive:{expected_hash}"
