"""JSONL projection transport for HIVE.

Appends cells as one-JSON-per-line to channel-named files.
Provides backward compatibility with the existing comms.sh readers.
This is a write-only projection -- reads go through SQLite.
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
