<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-02 | Updated: 2026-03-02 -->

# hive/mcp/ — MCP Server

## Purpose
Exposes HIVE board operations as MCP (Model Context Protocol) tools so Claude Code
can read/write the HIVE bus directly without shell commands. 12 tools total.

## Key Files
| File | Description |
|------|-------------|
| `server.py` | JSON-RPC stdio transport — LSP-style Content-Length headers, version 1.1.0 |
| `tools.py` | 12 MCP tool definitions + execute_tool dispatch |
| `__main__.py` | Entry point: python -m hive.mcp.server |

## MCP Tools (12 total)
| Tool | Purpose |
|------|---------|
| `hive_put` | Write any cell type to the board |
| `hive_get` | Get a cell by ID |
| `hive_query` | Query cells by type/channel/agent |
| `hive_refs` | Get all cells that reference a given cell |
| `hive_expire` | Mark a cell as expired |
| `hive_clock_in` | Register an agent to the roster |
| `hive_clock_out` | Deregister an agent |
| `hive_roster` | Get current agent roster |
| `hive_hire` | Post a task and watch for result |
| `hive_trace` | Record a reasoning trace for a contract |
| `hive_belief` | Record an explicit prior belief before acting |
| `hive_refute` | Mark a belief as refuted |

## For AI Agents

### Registration in Claude Code
See .mcp.json in project root. Server runs via:
  python -m hive.mcp.server --db C:/tools/agent-comms/hive.db --channels C:/Users/Brady.EAGLE/.ai/channels

### Protocol
JSON-RPC 2.0 over stdio with Content-Length headers (LSP-style).
Supports: initialize, tools/list, tools/call

## Dependencies
- hive.board.HiveBoard
- hive.mcp.tools (tool definitions)
- Python stdlib: json, sys
