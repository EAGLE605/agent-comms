"""Episodic memory -- reasoning traces for HIVE cells.

Agents write "trace" cells to record HOW they solved a problem, not just that
they solved it. Traces capture the trajectory: attempts, failures, pivots.

A "trace" cell stores the reasoning chain for a contract. Future agents solving
similar problems can query traces to avoid repeating failed strategies.
"""
from typing import Any

from hive.board import HiveBoard
from hive.cell import Cell


def record_trace(
    board: HiveBoard,
    *,
    from_agent: str,
    contract_id: str,
    channel: str,
    steps: list[dict[str, Any]],
    outcome: str = "success",
    tags: list[str] | None = None,
) -> str:
    """Record a reasoning trace for a completed contract.

    Each step should document: what was attempted, the outcome, and any
    observations that informed the next step.

    Args:
        steps: List of step dicts, e.g.:
               [{"attempt": 1, "action": "tried X", "outcome": "failed: 502"},
                {"attempt": 2, "action": "tried Y with Z adjustment", "outcome": "succeeded"}]
        outcome: Final outcome ("success", "failure", "partial")
    """
    return board.put(
        type="trace",
        from_agent=from_agent,
        channel=channel,
        data={
            "contract_id": contract_id,
            "outcome": outcome,
            "steps": steps,
            "step_count": len(steps),
        },
        refs=[contract_id],
        tags=tags or [],
    )


def get_traces(
    board: HiveBoard,
    *,
    channel: str | None = None,
    outcome: str | None = None,
    from_agent: str | None = None,
    limit: int = 20,
) -> list[Cell]:
    """Retrieve trace cells, optionally filtered.

    Use this to find "how did we solve X before?" before attempting a task.
    """
    kwargs: dict[str, Any] = {"type": "trace", "limit": limit, "order": "desc"}
    if channel:
        kwargs["channel"] = channel
    if from_agent:
        kwargs["from_prefix"] = from_agent
    cells = board.query(**kwargs)
    if outcome:
        cells = [c for c in cells if c.data.get("outcome") == outcome]
    return cells


def get_contract_trace(board: HiveBoard, contract_id: str) -> Cell | None:
    """Get the trace for a specific contract, if recorded."""
    refs = board.refs(contract_id)
    traces = [r for r in refs if r.type == "trace"]
    if not traces:
        return None
    # Most recent trace if multiple
    traces.sort(key=lambda t: t.ts, reverse=True)
    return traces[0]


def summarize_traces(board: HiveBoard, *, channel: str | None = None, limit: int = 10) -> dict[str, Any]:
    """Summarize recent trace patterns: success rate, avg steps, common failures."""
    traces = get_traces(board, channel=channel, limit=limit)
    if not traces:
        return {"total": 0, "success_rate": 0.0, "avg_steps": 0.0, "outcomes": {}}

    outcomes: dict[str, int] = {}
    total_steps = 0
    for t in traces:
        outcome = t.data.get("outcome", "unknown")
        outcomes[outcome] = outcomes.get(outcome, 0) + 1
        total_steps += t.data.get("step_count", 0)

    success_count = outcomes.get("success", 0)
    return {
        "total": len(traces),
        "success_rate": round(success_count / len(traces), 2),
        "avg_steps": round(total_steps / len(traces), 1),
        "outcomes": outcomes,
    }
