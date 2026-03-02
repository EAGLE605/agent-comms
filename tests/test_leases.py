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
