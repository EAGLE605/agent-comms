#!/usr/bin/env bash
# agent-comms CLI — universal inter-agent communication bus
# Usage: source comms.sh  (adds 'comms' function)
#    or: bash comms.sh <command> [args]
#
# Identity: COMMS_AGENT = "agent/session" e.g. "claude/1", "gemini/signx", "gemini/warehouse"
# Channels: project-scoped e.g. "signx-intel", "signx-warehouse", "keyedin", "general"

COMMS_DIR="C:/tools/agent-comms"
CHANNELS_DIR="${COMMS_DIR}/channels"
COMMS_AGENT="${COMMS_AGENT:-unknown}"

_comms_uuid() {
  python -c "import uuid;print(uuid.uuid4())"
}

_comms_ts() {
  date -Iseconds
}

_comms_ensure_channel() {
  local ch="$1"
  if [[ ! -f "${CHANNELS_DIR}/${ch}.jsonl" ]]; then
    touch "${CHANNELS_DIR}/${ch}.jsonl"
  fi
}

_comms_write() {
  local channel="$1" type="$2" msg="$3" data="${4:-"{}"}"
  _comms_ensure_channel "$channel"
  if printf '%s' "$data" | python -c "
import json, uuid, datetime, sys
data_raw = sys.stdin.read()
obj = {
    'id': str(uuid.uuid4()),
    'from': sys.argv[1],
    'ts': datetime.datetime.now().astimezone().isoformat(),
    'channel': sys.argv[2],
    'type': sys.argv[3],
    'msg': sys.argv[4],
    'data': json.loads(data_raw)
}
with open(sys.argv[5], 'a', encoding='utf-8') as f:
    f.write(json.dumps(obj, ensure_ascii=False) + '\n')
" "$COMMS_AGENT" "$channel" "$type" "$msg" "${CHANNELS_DIR}/${channel}.jsonl" 2>/dev/null; then
    echo "sent to ${channel} [${type}]"
  else
    echo "FAILED to send to ${channel} [${type}] — check data payload" >&2
    return 1
  fi
}

# Shared arg parser for send/task/result/error (all identical except type)
_comms_typed_send() {
  local type="$1"; shift
  local channel="$1" msg="$2" data="{}"
  shift 2 2>/dev/null
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --data) data="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ -z "$channel" || -z "$msg" ]]; then
    echo "usage: comms ${type} <channel> <message> [--data '{}']"
    return 1
  fi
  _comms_write "$channel" "$type" "$msg" "$data"
}

comms() {
  local cmd="${1:-help}"
  shift 2>/dev/null

  case "$cmd" in

    send)    _comms_typed_send "status" "$@" ;;
    task)    _comms_typed_send "task" "$@" ;;
    result)  _comms_typed_send "result" "$@" ;;
    error)   _comms_typed_send "error" "$@" ;;

    read)
      # comms read <channel> [--last N] [--from agent] [--type type]
      local channel="$1" last=10 filter_from="" filter_type=""
      shift 2>/dev/null
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --last) last="$2"; shift 2 ;;
          --from) filter_from="$2"; shift 2 ;;
          --type) filter_type="$2"; shift 2 ;;
          *) shift ;;
        esac
      done
      if [[ -z "$channel" ]]; then
        echo "usage: comms read <channel> [--last N] [--from agent] [--type type]"
        return 1
      fi
      local f="${CHANNELS_DIR}/${channel}.jsonl"
      if [[ ! -f "$f" ]]; then
        echo "channel '${channel}' does not exist"
        return 1
      fi
      local lines
      lines=$(wc -l < "$f" | tr -d ' ')
      if [[ "$lines" -eq 0 ]]; then
        echo "(no messages in ${channel})"
        return 0
      fi
      tail -n "$last" "$f" | python -c "
import sys, json
filter_from = '$filter_from'
filter_type = '$filter_type'
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        m = json.loads(line)
        if filter_from and filter_from not in m.get('from', ''): continue
        if filter_type and m.get('type', '') != filter_type: continue
        print(f\"[{m.get('ts','?')[:19]}] {m.get('from','?'):>16} | {m.get('type','?'):>10} | {m.get('msg','')}\")
        d = m.get('data', {})
        if d and d != {}:
            for k, v in d.items():
                vstr = str(v)
                if len(vstr) > 120: vstr = vstr[:120] + '...'
                print(f\"{'':>30}{k}: {vstr}\")
    except json.JSONDecodeError:
        print(f'  (bad json) {line[:80]}')
"
      ;;

    phone-home)
      # comms phone-home <message> [--channel general] [--data '{}']
      local msg="$1" channel="general" data="{}"
      shift 2>/dev/null
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --channel) channel="$2"; shift 2 ;;
          --data) data="$2"; shift 2 ;;
          *) shift ;;
        esac
      done
      if [[ -z "$msg" ]]; then
        echo "usage: comms phone-home <message> [--channel general] [--data '{}']"
        return 1
      fi
      _comms_write "$channel" "phone-home" "$msg" "$data"
      ;;

    clock-in)
      # comms clock-in [role/project] — register this terminal as active
      local role="${1:-general}"
      local data
      data=$(python -c "import json,sys;print(json.dumps({'role':sys.argv[1],'pid':sys.argv[2]}))" "$role" "$$")
      _comms_write "roster" "clock-in" "${COMMS_AGENT} online — ${role}" "$data"
      # Show standards on clock-in
      local standards="${COMMS_DIR}/standards.md"
      if [[ -f "$standards" ]]; then
        echo ""
        echo "=== FLEET STANDARDS (read before working) ==="
        python -c "
with open('$standards') as f:
    for line in f:
        line = line.rstrip()
        if line.startswith('# '): print(f'  {line[2:].upper()}')
        elif line.startswith('## '): print(f'  --- {line[3:]} ---')
        elif line.startswith('- '): print(f'    {line}')
        elif line.startswith('|'): pass  # skip tables
        elif line.strip(): print(f'  {line}')
" 2>/dev/null
        echo "  ============================================"
        echo ""
      fi
      # Show current roster
      comms roster
      ;;

    clock-out)
      # comms clock-out [reason]
      local reason="${1:-session ended}"
      _comms_write "roster" "clock-out" "${COMMS_AGENT} offline — ${reason}"
      ;;

    roster)
      # comms roster — show who's active (last clock-in without matching clock-out)
      local f="${CHANNELS_DIR}/roster.jsonl"
      if [[ ! -f "$f" ]] || [[ $(wc -l < "$f" | tr -d ' ') -eq 0 ]]; then
        echo "(no agents registered — use 'comms clock-in' to register)"
        return 0
      fi
      echo "=== Active Roster ==="
      python -c "
import json
agents = {}
with open('$f') as fh:
    for line in fh:
        line = line.strip()
        if not line: continue
        try:
            m = json.loads(line)
            agent = m.get('from', '?')
            mtype = m.get('type', '')
            if mtype == 'clock-in':
                agents[agent] = {'ts': m['ts'], 'role': m.get('data',{}).get('role',''), 'status': 'ACTIVE'}
            elif mtype == 'clock-out':
                if agent in agents:
                    agents[agent]['status'] = 'OFFLINE'
                    agents[agent]['ts'] = m['ts']
        except: pass
if not agents:
    print('  (empty)')
else:
    for agent, info in sorted(agents.items()):
        marker = 'ON ' if info['status'] == 'ACTIVE' else 'OFF'
        print(f\"  {marker}  {agent:>20}  {info.get('role',''):20}  last: {info['ts'][:19]}\")
"
      echo ""
      ;;

    handoff)
      # comms handoff <channel> <next_agent> <instructions>
      local channel="$1" next_agent="$2" instructions="$3"
      if [[ -z "$channel" || -z "$next_agent" || -z "$instructions" ]]; then
        echo "usage: comms handoff <channel> <next_agent> <instructions>"
        return 1
      fi
      local task_id
      task_id=$(_comms_uuid)
      local data
      data=$(python -c "import json,sys;print(json.dumps({'task_id':sys.argv[1],'next_agent':sys.argv[2],'instructions':sys.argv[3]}))" "$task_id" "$next_agent" "$instructions")
      _comms_write "$channel" "handoff" "handoff to ${next_agent}: ${instructions}" "$data"
      echo "task_id: ${task_id}"
      ;;

    ack)
      # comms ack <channel> <task_id>
      local channel="$1" task_id="$2"
      if [[ -z "$channel" || -z "$task_id" ]]; then
        echo "usage: comms ack <channel> <task_id>"
        return 1
      fi
      local data
      data=$(python -c "import json,sys;print(json.dumps({'task_id':sys.argv[1]}))" "$task_id")
      _comms_write "$channel" "ack" "acknowledged ${task_id}" "$data"
      ;;

    status)
      # comms status — all channels grouped by project
      echo "=== Agent Comms Status ==="
      echo ""
      for f in "${CHANNELS_DIR}"/*.jsonl; do
        local ch
        ch=$(basename "$f" .jsonl)
        local count
        count=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
        local last=""
        if [[ "$count" -gt 0 ]]; then
          last=$(tail -1 "$f" | python -c "
import sys, json
line = sys.stdin.read().strip()
if line:
    try:
        m = json.loads(line)
        ts = m.get('ts','')[:19]
        print(f\"{ts}  {m.get('from','?')} | {m.get('type','?')} | {m.get('msg','')[:50]}\")
    except: print('(parse error)')
" 2>/dev/null)
        fi
        printf "  %-22s %4s msgs  %s\n" "$ch" "$count" "${last:-(empty)}"
      done
      echo ""
      ;;

    channels)
      # comms channels — list all with message counts
      for f in "${CHANNELS_DIR}"/*.jsonl; do
        local ch
        ch=$(basename "$f" .jsonl)
        local count
        count=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
        printf "  %-22s %s msgs\n" "$ch" "$count"
      done
      ;;

    watch)
      # comms watch <channel> — tail -f with pretty print
      local channel="$1"
      if [[ -z "$channel" ]]; then
        echo "usage: comms watch <channel>"
        return 1
      fi
      local f="${CHANNELS_DIR}/${channel}.jsonl"
      if [[ ! -f "$f" ]]; then
        echo "channel '${channel}' does not exist"
        return 1
      fi
      echo "watching ${channel}... (ctrl+c to stop)"
      tail -f "$f" | while IFS= read -r line; do
        echo "$line" | python -c "
import sys, json
line = sys.stdin.read().strip()
if line:
    try:
        m = json.loads(line)
        print(f\"[{m.get('ts','?')[:19]}] {m.get('from','?'):>16} | {m.get('type','?'):>10} | {m.get('msg','')}\")
    except: print(line)
"
      done
      ;;

    log)
      # comms log — unified timeline across ALL channels, last N messages
      local last="${1:-20}"
      python -c "
import json, os, glob
msgs = []
for f in glob.glob('${CHANNELS_DIR}/*.jsonl'):
    with open(f) as fh:
        for line in fh:
            line = line.strip()
            if not line: continue
            try: msgs.append(json.loads(line))
            except: pass
msgs.sort(key=lambda m: m.get('ts', ''))
for m in msgs[-${last}:]:
    ch = m.get('channel', '?')
    print(f\"[{m.get('ts','?')[:19]}] {ch:>16} | {m.get('from','?'):>16} | {m.get('type','?'):>10} | {m.get('msg','')[:60]}\")
"
      ;;

    help|*)
      cat <<'EOF'
agent-comms CLI — universal inter-agent communication bus

Identity:
  export COMMS_AGENT="claude/1"       # agent/session (e.g. gemini/signx, claude/2)
  source C:/tools/agent-comms/comms.sh

Channels are project-scoped:
  signx-intel, signx-warehouse, keyedin, kimco, general, roster

Commands:
  comms send <ch> <msg> [--data '{}']        Status message
  comms task <ch> <msg> [--data '{}']        Request work
  comms result <ch> <msg> [--data '{}']      Deliver results
  comms error <ch> <msg> [--data '{}']       Report failure
  comms phone-home <msg> [--channel X]       Check in with the boss
  comms handoff <ch> <agent> <instructions>  Hand off work
  comms ack <ch> <task_id>                   Acknowledge a handoff
  comms clock-in [role]                      Register terminal as active
  comms clock-out [reason]                   Mark terminal as offline
  comms roster                               Who's online
  comms read <ch> [--last N] [--from X]      Read messages (filter by agent)
  comms log [N]                              Unified timeline, all channels
  comms status                               All channels overview
  comms channels                             List channels with counts
  comms watch <ch>                           Live tail a channel
  comms help                                 This help

Agent behavior:
  WORKING  — do your task, no chatter
  DONE     — phone home with results
  BLOCKED  — phone home with what you need
  IDLE     — check masterplan or phone home 'ready for work'
EOF
      ;;
  esac
}

# If called directly (not sourced), run the command
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  comms "$@"
fi
