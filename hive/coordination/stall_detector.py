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
            # No heartbeats -- check contract age
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
