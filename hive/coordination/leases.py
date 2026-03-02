"""Advisory file lease management.

Agents claim leases before editing files. Other agents check before claiming.
Leases are advisory (like flock in Unix). Bad actors get bad feedback scores.
Leases expire via TTL -- no daemon needed.
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
    leases = board.query(type="lease", tags=[f"resource:{resource}"])
    for lease in leases:
        releases = board.refs(lease.id)
        if any(r.type == "release" for r in releases):
            continue  # released
        return True
    return False
