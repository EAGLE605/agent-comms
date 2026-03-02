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

    def test_evolve_detects_refuted_beliefs(self):
        board = _make_board()
        from hive.coordination.beliefs import assert_belief, refute_belief
        bid = assert_belief(
            board,
            from_agent="claude/1",
            channel="general",
            claim="Sequential requests cause 1102",
            confidence=0.9,
        )
        refute_belief(
            board,
            belief_id=bid,
            from_agent="gemini/1",
            channel="general",
            reason="Connection pooling issue",
            correction="Use persistent connections",
        )
        signals = evolve(board)
        events = [s["event"] for s in signals]
        assert "refuted_beliefs" in events
        refuted_signal = next(s for s in signals if s["event"] == "refuted_beliefs")
        assert refuted_signal["payload"]["count"] == 1
        assert refuted_signal["payload"]["corrections"][0]["correction"] == "Use persistent connections"
