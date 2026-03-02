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

    Checks:
    1. High failure rate by task_type tag (feedback scores)
    2. Refuted beliefs -- wrong priors that agents acted on

    Returns list of signal info dicts for signals emitted.
    """
    signals = []

    feedbacks = board.query(type="feedback")
    if feedbacks:
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

    # Check for refuted beliefs -- wrong priors that need correction
    try:
        from hive.coordination.beliefs import get_refuted_beliefs
        refuted = get_refuted_beliefs(board, limit=20)
        if refuted:
            signal_data = {
                "event": "refuted_beliefs",
                "payload": {
                    "count": len(refuted),
                    "corrections": [
                        {"claim": r["claim"], "correction": r["correction"]}
                        for r in refuted
                        if r.get("correction")
                    ],
                },
            }
            board.put(
                type="signal",
                from_agent="hive/evolution",
                channel="roster",
                data=signal_data,
            )
            signals.append(signal_data)
    except ImportError:
        pass  # beliefs module not yet available

    return signals
