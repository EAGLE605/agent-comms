"""Tests for JSONLTransport -- append-only JSONL projection."""
import json
import os
import tempfile

import pytest

from hive.cell import make_cell
from hive.transports.jsonl import JSONLTransport


@pytest.fixture
def tmp_dir():
    with tempfile.TemporaryDirectory() as d:
        yield d


@pytest.fixture
def transport(tmp_dir):
    return JSONLTransport(tmp_dir)


def _read_lines(path: str) -> list[dict]:
    with open(path, encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


# ---------------------------------------------------------------------------
# put creates channel file
# ---------------------------------------------------------------------------

def test_put_creates_channel_file(transport, tmp_dir):
    cell = make_cell(type="msg", from_agent="agent-a", channel="alpha", data={"x": 1})
    transport.put(cell)
    assert os.path.isfile(os.path.join(tmp_dir, "alpha.jsonl"))


# ---------------------------------------------------------------------------
# put appends JSON line with correct fields
# ---------------------------------------------------------------------------

def test_put_line_has_correct_fields(transport, tmp_dir):
    cell = make_cell(type="msg", from_agent="agent-a", channel="alpha", data={"x": 1})
    returned_id = transport.put(cell)

    path = os.path.join(tmp_dir, "alpha.jsonl")
    lines = _read_lines(path)

    assert len(lines) == 1
    obj = lines[0]

    # returned id matches cell id
    assert returned_id == cell.id

    # all required fields present
    assert obj["id"] == cell.id
    assert obj["v"] == 1
    assert obj["type"] == "msg"
    assert obj["channel"] == "alpha"
    assert obj["data"] == {"x": 1}
    assert "ts" in obj
    assert "refs" in obj
    assert "ttl" in obj
    assert "tags" in obj
    assert "sig" in obj


# ---------------------------------------------------------------------------
# serialized cell uses "from" not "from_agent" (protocol wire format)
# ---------------------------------------------------------------------------

def test_put_uses_from_not_from_agent(transport, tmp_dir):
    cell = make_cell(type="msg", from_agent="agent-b", channel="wire", data={})
    transport.put(cell)

    path = os.path.join(tmp_dir, "wire.jsonl")
    lines = _read_lines(path)
    obj = lines[0]

    assert "from" in obj
    assert obj["from"] == "agent-b"
    assert "from_agent" not in obj


# ---------------------------------------------------------------------------
# put multiple cells appends multiple lines
# ---------------------------------------------------------------------------

def test_put_multiple_appends_multiple_lines(transport, tmp_dir):
    channel = "multi"
    cells = [
        make_cell(type="msg", from_agent="agent-a", channel=channel, data={"n": i})
        for i in range(3)
    ]
    for c in cells:
        transport.put(c)

    path = os.path.join(tmp_dir, f"{channel}.jsonl")
    lines = _read_lines(path)

    assert len(lines) == 3
    ids_in_file = [obj["id"] for obj in lines]
    assert ids_in_file == [c.id for c in cells]


# ---------------------------------------------------------------------------
# put to different channels creates separate files
# ---------------------------------------------------------------------------

def test_put_different_channels_separate_files(transport, tmp_dir):
    cell_a = make_cell(type="msg", from_agent="agent-a", channel="chan-a", data={"v": "a"})
    cell_b = make_cell(type="msg", from_agent="agent-b", channel="chan-b", data={"v": "b"})

    transport.put(cell_a)
    transport.put(cell_b)

    path_a = os.path.join(tmp_dir, "chan-a.jsonl")
    path_b = os.path.join(tmp_dir, "chan-b.jsonl")

    assert os.path.isfile(path_a)
    assert os.path.isfile(path_b)

    lines_a = _read_lines(path_a)
    lines_b = _read_lines(path_b)

    assert len(lines_a) == 1
    assert len(lines_b) == 1
    assert lines_a[0]["channel"] == "chan-a"
    assert lines_b[0]["channel"] == "chan-b"
    assert lines_a[0]["data"] == {"v": "a"}
    assert lines_b[0]["data"] == {"v": "b"}


# ---------------------------------------------------------------------------
# constructor creates channels_dir if it does not exist
# ---------------------------------------------------------------------------

def test_init_creates_channels_dir(tmp_dir):
    new_dir = os.path.join(tmp_dir, "deeply", "nested", "channels")
    assert not os.path.exists(new_dir)
    JSONLTransport(new_dir)
    assert os.path.isdir(new_dir)
