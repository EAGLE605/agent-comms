#!/usr/bin/env bash
# agent-comms CLI — universal inter-agent communication bus
# Usage: source comms.sh  (adds 'comms' function)
#    or: bash comms.sh <command> [args]

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
  local channel="$1" type="$2" msg="$3" data="${4:-{}}"
  _comms_ensure_channel "$channel"
  local id
  id=$(_comms_uuid)
  local ts
  ts=$(_comms_ts)
  printf '{"id":"%s","from":"%s","ts":"%s","channel":"%s","type":"%s","msg":"%s","data":%s}\n' \
    "$id" "$COMMS_AGENT" "$ts" "$channel" "$type" "$msg" "$data" \
    >> "${CHANNELS_DIR}/${channel}.jsonl"
  echo "sent to ${channel} [${type}]"
}

comms() {
  local cmd="${1:-help}"
  shift 2>/dev/null

  case "$cmd" in

    send)
      # comms send <channel> <message> [--data '{}']
      local channel="$1" msg="$2" data="{}"
      shift 2 2>/dev/null
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --data) data="$2"; shift 2 ;;
          *) shift ;;
        esac
      done
      if [[ -z "$channel" || -z "$msg" ]]; then
        echo "usage: comms send <channel> <message> [--data '{}']"
        return 1
      fi
      _comms_write "$channel" "status" "$msg" "$data"
      ;;

    read)
      # comms read <channel> [--last N]
      local channel="$1" last=10
      shift 2>/dev/null
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --last) last="$2"; shift 2 ;;
          *) shift ;;
        esac
      done
      if [[ -z "$channel" ]]; then
        echo "usage: comms read <channel> [--last N]"
        return 1
      fi
      local f="${CHANNELS_DIR}/${channel}.jsonl"
      if [[ ! -f "$f" ]]; then
        echo "channel '${channel}' does not exist"
        return 1
      fi
      tail -n "$last" "$f" | python -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        m = json.loads(line)
        print(f\"[{m.get('ts','?')[:19]}] {m.get('from','?'):>10} | {m.get('type','?'):>10} | {m.get('msg','')}\")
        d = m.get('data', {})
        if d and d != {}:
            for k, v in d.items():
                print(f\"{'':>24}{k}: {v}\")
    except json.JSONDecodeError:
        print(f'  (bad json) {line[:80]}')
"
      ;;

    task)
      # comms task <channel> <message> [--data '{}']
      local channel="$1" msg="$2" data="{}"
      shift 2 2>/dev/null
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --data) data="$2"; shift 2 ;;
          *) shift ;;
        esac
      done
      if [[ -z "$channel" || -z "$msg" ]]; then
        echo "usage: comms task <channel> <message> [--data '{}']"
        return 1
      fi
      _comms_write "$channel" "task" "$msg" "$data"
      ;;

    result)
      # comms result <channel> <message> [--data '{}']
      local channel="$1" msg="$2" data="{}"
      shift 2 2>/dev/null
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --data) data="$2"; shift 2 ;;
          *) shift ;;
        esac
      done
      if [[ -z "$channel" || -z "$msg" ]]; then
        echo "usage: comms result <channel> <message> [--data '{}']"
        return 1
      fi
      _comms_write "$channel" "result" "$msg" "$data"
      ;;

    error)
      # comms error <channel> <message> [--data '{}']
      local channel="$1" msg="$2" data="{}"
      shift 2 2>/dev/null
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --data) data="$2"; shift 2 ;;
          *) shift ;;
        esac
      done
      if [[ -z "$channel" || -z "$msg" ]]; then
        echo "usage: comms error <channel> <message> [--data '{}']"
        return 1
      fi
      _comms_write "$channel" "error" "$msg" "$data"
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
      data=$(printf '{"task_id":"%s","next_agent":"%s","instructions":"%s"}' "$task_id" "$next_agent" "$instructions")
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
      data=$(printf '{"task_id":"%s"}' "$task_id")
      _comms_write "$channel" "ack" "acknowledged ${task_id}" "$data"
      ;;

    status)
      # comms status — show all channels with last message
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
        print(f\"{m.get('from','?')} | {m.get('type','?')} | {m.get('msg','')[:60]}\")
    except: print('(parse error)')
" 2>/dev/null)
        fi
        printf "  %-12s %4s msgs  %s\n" "$ch" "$count" "${last:-(empty)}"
      done
      echo ""
      ;;

    channels)
      # comms channels — list all channels
      for f in "${CHANNELS_DIR}"/*.jsonl; do
        basename "$f" .jsonl
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
        print(f\"[{m.get('ts','?')[:19]}] {m.get('from','?'):>10} | {m.get('type','?'):>10} | {m.get('msg','')}\")
    except: print(line)
"
      done
      ;;

    help|*)
      cat <<'EOF'
agent-comms CLI — universal inter-agent communication bus

Setup:
  export COMMS_AGENT="claude"    # set your agent name
  source C:/tools/agent-comms/comms.sh

Commands:
  comms send <channel> <message> [--data '{}']   Write a status message
  comms task <channel> <message> [--data '{}']    Write a task request
  comms result <channel> <message> [--data '{}']  Write a result
  comms error <channel> <message> [--data '{}']   Write an error
  comms phone-home <message> [--channel X]        Check in with the boss
  comms handoff <channel> <agent> <instructions>  Hand off work
  comms ack <channel> <task_id>                   Acknowledge a handoff
  comms read <channel> [--last N]                 Read latest N messages
  comms status                                    All channels overview
  comms channels                                  List channel names
  comms watch <channel>                           Live tail a channel
  comms help                                      This help

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
