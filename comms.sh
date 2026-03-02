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
import sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
with open('$standards', encoding='utf-8') as f:
    for line in f:
        line = line.rstrip().replace('\u2014', '--').replace('\u2013', '-')
        if line.startswith('# '): print(f'  {line[2:].upper()}')
        elif line.startswith('## '): print(f'  --- {line[3:]} ---')
        elif line.startswith('- '): print(f'    {line}')
        elif line.startswith('|'): pass
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

    hire)
      # comms hire <agent/session> <department> <role> [--task "instructions"] [--cwd /path] [--no-launch]
      local agent_id="$1" dept="$2" role="$3"
      shift 3 2>/dev/null
      local task_instructions="" work_dir="" no_launch=false
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --task) task_instructions="$2"; shift 2 ;;
          --cwd)  work_dir="$2"; shift 2 ;;
          --no-launch) no_launch=true; shift ;;
          *) shift ;;
        esac
      done
      if [[ -z "$agent_id" || -z "$dept" || -z "$role" ]]; then
        echo "usage: comms hire <agent/session> <department> <role> [--task 'instructions'] [--cwd /path] [--no-launch]"
        echo "  departments: signx, erp, ops"
        echo "  agents:      claude/<session>, gemini/<session>, openclaw/<session>"
        echo ""
        echo "  example: comms hire gemini/signx signx 'data analyst' --task 'analyze labor CSV' --cwd ~/Desktop/signx"
        echo "  --no-launch  Record hire but don't open terminal (manual onboarding)"
        return 1
      fi
      # Extract agent type from agent/session format
      local agent_type="${agent_id%%/*}"
      local session_name="${agent_id#*/}"

      # Record hire in roster
      local data
      data=$(python -c "import json,sys;print(json.dumps({'agent':sys.argv[1],'department':sys.argv[2],'role':sys.argv[3],'hired_by':sys.argv[4],'task':sys.argv[5],'cwd':sys.argv[6]}))" "$agent_id" "$dept" "$role" "$COMMS_AGENT" "${task_instructions:-}" "${work_dir:-}")
      _comms_write "roster" "hire" "HIRED ${agent_id} -> ${dept} dept as ${role}" "$data"

      echo ""
      echo "  HIRED: ${agent_id}"
      echo "  Dept:  ${dept}"
      echo "  Role:  ${role}"
      [[ -n "$task_instructions" ]] && echo "  Task:  ${task_instructions}"
      [[ -n "$work_dir" ]] && echo "  CWD:   ${work_dir}"

      if [[ "$no_launch" == "true" ]]; then
        echo ""
        echo "  (--no-launch) Manual onboarding:"
        echo "    export COMMS_AGENT=\"${agent_id}\""
        echo "    source C:/tools/agent-comms/comms.sh"
        echo "    comms clock-in \"${role}\""
        return 0
      fi

      # Write boot script for the new terminal
      local boot_script="${COMMS_DIR}/.boot-${agent_id//\//-}.sh"
      cat > "$boot_script" <<BOOTEOF
#!/usr/bin/env bash
# Auto-generated boot script for ${agent_id}
# Created by: ${COMMS_AGENT} at $(date -Iseconds)

export COMMS_AGENT="${agent_id}"
source C:/tools/agent-comms/comms.sh

echo ""
echo "========================================"
echo "  AGENT: ${agent_id}"
echo "  DEPT:  ${dept}"
echo "  ROLE:  ${role}"
echo "========================================"
echo ""

# Clock in
comms clock-in "${role}"
BOOTEOF

      # Add task dispatch if provided
      if [[ -n "$task_instructions" ]]; then
        cat >> "$boot_script" <<BOOTEOF

# Task dispatched at hire time
echo ""
echo "  DISPATCHED TASK:"
echo "  ${task_instructions}"
echo ""
comms task "${dept}" "starting: ${task_instructions}" --data '{"dispatched_at_hire":true}'
BOOTEOF
      fi

      # Add the agent CLI launch
      case "$agent_type" in
        gemini)
          cat >> "$boot_script" <<BOOTEOF

# Launch Gemini CLI
echo "Launching Gemini CLI..."
echo ""
gemini
BOOTEOF
          ;;
        claude)
          cat >> "$boot_script" <<BOOTEOF

# Launch Claude Code
echo "Launching Claude Code..."
echo ""
claude
BOOTEOF
          ;;
        openclaw)
          cat >> "$boot_script" <<BOOTEOF

# Launch OpenClaw
echo "Launching OpenClaw..."
echo ""
openclaw
BOOTEOF
          ;;
        *)
          cat >> "$boot_script" <<BOOTEOF

# Unknown agent type — drop to interactive shell
echo "Agent type '${agent_type}' has no known CLI. Dropping to shell."
echo "Set up manually, then: comms clock-in '${role}'"
exec bash -l
BOOTEOF
          ;;
      esac

      # Keep terminal open after agent exits
      cat >> "$boot_script" <<'BOOTEOF'

# Agent CLI exited — clock out and hold terminal
echo ""
echo "Agent CLI exited. Clocking out..."
comms clock-out "CLI exited"
echo "Press Enter to close this terminal..."
read -r
BOOTEOF

      chmod +x "$boot_script"

      # Determine working directory
      local launch_dir="${work_dir:-.}"

      # Launch headed terminal via Windows Terminal (wt.exe)
      local title="${agent_id} [${dept}]"
      local wt_path
      wt_path=$(which wt.exe 2>/dev/null)
      if [[ -n "$wt_path" ]]; then
        # Windows Terminal — native Windows 11 look
        wt.exe new-tab --title "$title" --startingDirectory "$launch_dir" \
          bash -l "$boot_script" &
      else
        # Fallback to mintty (Git Bash terminal)
        mintty --title "$title" --dir "$launch_dir" \
          -e /usr/bin/bash -l "$boot_script" &
      fi

      echo ""
      echo "  >> Terminal launched: ${title}"
      echo "  >> Boot script: ${boot_script}"
      echo ""
      ;;

    fire)
      # comms fire <agent/session> [reason]
      local agent_id="$1" reason="${2:-no longer needed}"
      if [[ -z "$agent_id" ]]; then
        echo "usage: comms fire <agent/session> [reason]"
        return 1
      fi
      local data
      data=$(python -c "import json,sys;print(json.dumps({'agent':sys.argv[1],'reason':sys.argv[2],'fired_by':sys.argv[3]}))" "$agent_id" "$reason" "$COMMS_AGENT")
      _comms_write "roster" "fire" "FIRED ${agent_id}: ${reason}" "$data"
      echo "  Terminated: ${agent_id} (${reason})"
      ;;

    org)
      # comms org — show organizational chart
      local org_file="${COMMS_DIR}/org.json"
      if [[ ! -f "$org_file" ]]; then
        echo "org.json not found"
        return 1
      fi
      python -c "
import json
with open('$org_file') as f:
    org = json.load(f)

print('=== ' + org.get('company','Fleet') + ' ===')
print()

h = org.get('hierarchy', {})
d = h.get('DIRECTOR', {})
o = h.get('ORCHESTRATOR', {})
print(f'  DIRECTOR:      {d.get(\"id\",\"?\")}')
print(f'                 {d.get(\"role\",\"\")}')
print(f'  ORCHESTRATOR:  {o.get(\"id\",\"?\")}')
print(f'                 {o.get(\"role\",\"\")}')
print()

print('  DEPARTMENTS:')
for key, dept in org.get('departments', {}).items():
    chans = ', '.join(dept.get('channels', []))
    print(f'    {dept.get(\"name\",key):20s}  channels: {chans}')
    print(f'    {\"\":20s}  mission: {dept.get(\"mission\",\"\")}')
print()

# Show active roster alongside org
import glob, os
roster_file = '${CHANNELS_DIR}/roster.jsonl'
agents = {}
if os.path.exists(roster_file):
    with open(roster_file) as rf:
        for line in rf:
            line = line.strip()
            if not line: continue
            try:
                m = json.loads(line)
                agent = m.get('from', '?')
                mtype = m.get('type', '')
                if mtype == 'clock-in':
                    agents[agent] = {'status': 'ACTIVE', 'role': m.get('data',{}).get('role',''), 'ts': m['ts']}
                elif mtype == 'clock-out':
                    if agent in agents: agents[agent]['status'] = 'OFFLINE'
                elif mtype == 'fire':
                    fired = m.get('data',{}).get('agent','')
                    if fired in agents: agents[fired]['status'] = 'FIRED'
            except: pass

print('  ACTIVE WORKFORCE:')
for agent, info in sorted(agents.items()):
    if info['status'] == 'FIRED': marker = 'XX'
    elif info['status'] == 'OFFLINE': marker = '--'
    else: marker = '>>'
    print(f'    {marker}  {agent:20s}  {info.get(\"role\",\"\"):30s}  {info[\"status\"]}')
print()
"
      ;;

    perf)
      # comms perf [agent] — performance summary from message history
      local agent_filter="$1"
      python -c "
import json, glob, os
from collections import defaultdict

stats = defaultdict(lambda: {'tasks': 0, 'results': 0, 'errors': 0, 'handoffs_sent': 0, 'handoffs_recv': 0, 'phone_homes': 0, 'first_seen': '', 'last_seen': '', 'channels': set()})
agent_filter = '$agent_filter'

for f in glob.glob('${CHANNELS_DIR}/*.jsonl'):
    with open(f) as fh:
        for line in fh:
            line = line.strip()
            if not line: continue
            try:
                m = json.loads(line)
                agent = m.get('from', '?')
                if agent_filter and agent_filter not in agent: continue
                mtype = m.get('type', '')
                ts = m.get('ts', '')
                ch = m.get('channel', '')

                s = stats[agent]
                if not s['first_seen'] or ts < s['first_seen']: s['first_seen'] = ts
                if not s['last_seen'] or ts > s['last_seen']: s['last_seen'] = ts
                if ch != 'roster': s['channels'].add(ch)

                if mtype == 'task': s['tasks'] += 1
                elif mtype == 'result': s['results'] += 1
                elif mtype == 'error': s['errors'] += 1
                elif mtype == 'handoff': s['handoffs_sent'] += 1
                elif mtype == 'ack': s['handoffs_recv'] += 1
                elif mtype == 'phone-home': s['phone_homes'] += 1
            except: pass

if not stats:
    print('  (no data — agents need to use the bus first)')
else:
    print('=== Agent Performance ===')
    print()
    for agent in sorted(stats):
        s = stats[agent]
        total = s['results'] + s['errors']
        success_rate = f\"{(s['results']/total*100):.0f}%\" if total > 0 else 'n/a'
        channels = ', '.join(sorted(s['channels'])) if s['channels'] else '(none)'
        print(f'  {agent}')
        print(f'    Results: {s[\"results\"]}  Errors: {s[\"errors\"]}  Success rate: {success_rate}')
        print(f'    Tasks requested: {s[\"tasks\"]}  Handoffs: sent={s[\"handoffs_sent\"]} recv={s[\"handoffs_recv\"]}')
        print(f'    Phone-homes: {s[\"phone_homes\"]}  Channels: {channels}')
        print(f'    Active: {s[\"first_seen\"][:19]} to {s[\"last_seen\"][:19]}')
        print()
"
      ;;

    niche)
      # comms niche [agent_type] — show agent strengths from org.json
      local agent_type="$1"
      local org_file="${COMMS_DIR}/org.json"
      if [[ ! -f "$org_file" ]]; then
        echo "org.json not found"
        return 1
      fi
      python -c "
import json
with open('$org_file') as f:
    org = json.load(f)
agent_filter = '$agent_type'
print('=== Agent Niches ===')
print()
for name, info in org.get('agents', {}).items():
    if agent_filter and agent_filter != name: continue
    print(f'  {name.upper()} ({info.get(\"type\",\"\")})')
    print(f'    Cost: {info.get(\"cost\",\"?\")}')
    print(f'    Best for: {\", \".join(info.get(\"best_for\",[]))}')
    print(f'    Strengths:')
    for s in info.get('strengths', []): print(f'      + {s}')
    print(f'    Weaknesses:')
    for w in info.get('weaknesses', []): print(f'      - {w}')
    mistakes = info.get('known_mistakes', [])
    if mistakes:
        print(f'    Known mistakes:')
        for m in mistakes: print(f'      ! {m}')
    print()
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

Messaging:
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

Organization:
  comms hire <agent/session> <dept> <role>   Hire agent + launch terminal
  comms fire <agent/session> [reason]        Terminate agent
  comms org                                  Org chart + active workforce
  comms perf [agent]                         Performance stats from history
  comms niche [agent_type]                   Agent strengths/weaknesses
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
