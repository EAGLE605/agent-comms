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
