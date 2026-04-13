#!/usr/bin/env bash
# Cache freshness age + cache token usage
#
# Shows how long since the last API call touched the prompt cache,
# color-coded by TTL freshness. Helps you gauge whether your cache
# is still warm or has expired.

set -euo pipefail

INPUT=$(cat)

COMPACT=False COMPONENTS="" DIM="" LGRAY="" GREEN="" YELLOW="" RED="" RESET="" ICON=""
READ_PREFIX="read:" WRITE_PREFIX="write:" READ_PREFIX_COMPACT="R:" WRITE_PREFIX_COMPACT="W:"
CACHE_READ=0 CACHE_WRITE=0 CACHE_AGE="--" CACHE_AGE_TIER="none"

eval "$(echo "$INPUT" | python3 -c "
import json, os, sys
from datetime import datetime, timezone
d = json.load(sys.stdin)
cfg = d.get('config', {})
palette = cfg.get('palette', {})
icons = cfg.get('icons', {})
settings = cfg.get('settings', {})
data = d.get('data', {})
cw = data.get('context_window') or {}
cu = cw.get('current_usage') or {}
print(f'COMPACT={cfg.get(\"compact\", False)}')
print('COMPONENTS=\"' + ','.join(cfg.get('components', [])) + '\"')
print(f'DIM=\"{palette.get(\"muted\", \"\")}\"')
print(f'LGRAY=\"{palette.get(\"subtle\", \"\")}\"')
print(f'GREEN=\"{palette.get(\"success\", \"\")}\"')
print(f'YELLOW=\"{palette.get(\"warning\", \"\")}\"')
print(f'RED=\"{palette.get(\"danger\", \"\")}\"')
print(f'RESET=\"{palette.get(\"reset\", \"\")}\"')
print(f'ICON=\"{icons.get(\"icon\", \"\U0001F5C4 \")}\"')
print(f'READ_PREFIX=\"{icons.get(\"cache_read\", \"read:\")}\"')
print(f'WRITE_PREFIX=\"{icons.get(\"cache_write\", \"write:\")}\"')
print(f'READ_PREFIX_COMPACT=\"{icons.get(\"cache_read_compact\", \"R:\")}\"')
print(f'WRITE_PREFIX_COMPACT=\"{icons.get(\"cache_write_compact\", \"W:\")}\"')
cr = cu.get('cache_read_input_tokens')
cc = cu.get('cache_creation_input_tokens')
print(f'CACHE_READ={cr if cr is not None else 0}')
print(f'CACHE_WRITE={cc if cc is not None else 0}')
print(f'HAS_CACHE={\"true\" if cr is not None else \"false\"}')
cache_ttl = int(settings.get('cache_ttl', 300))
caution_threshold = int(cache_ttl * 0.8)
try:
    tp = data.get('transcript_path')
    last_ts = None
    if tp and os.path.exists(tp):
        with open(tp) as f:
            for line in f:
                try:
                    e = json.loads(line)
                except Exception:
                    continue
                ts = e.get('timestamp')
                if ts:
                    last_ts = ts
    if last_ts:
        dt = datetime.fromisoformat(last_ts.replace('Z', '+00:00'))
        elapsed = max(0, int((datetime.now(timezone.utc) - dt).total_seconds()))
        if elapsed < 60:
            age_str = f'{elapsed}s'
        elif elapsed < 3600:
            age_str = f'{elapsed // 60}m{elapsed % 60:02d}s'
        else:
            age_str = f'{elapsed // 3600}h{elapsed % 3600 // 60:02d}m'
        if elapsed < caution_threshold:
            tier = 'warm'
        elif elapsed < cache_ttl:
            tier = 'caution'
        else:
            tier = 'expired'
        print(f'CACHE_AGE=\"{age_str}\"')
        print(f'CACHE_AGE_TIER={tier}')
    else:
        print('CACHE_AGE=\"--\"')
        print('CACHE_AGE_TIER=none')
except Exception:
    print('CACHE_AGE=\"--\"')
    print('CACHE_AGE_TIER=none')
" 2>/dev/null)"

# Format token count as Xk
fmt_k() {
  local n=$1
  if (( n >= 1000 )); then
    echo "$(( (n + 500) / 1000 ))k"
  else
    echo "$n"
  fi
}

show_all=true
[[ -n "$COMPONENTS" ]] && show_all=false

show_time=false
show_cache=false
if $show_all; then
  show_time=true
  show_cache=true
else
  echo "$COMPONENTS" | grep -qw "time" && show_time=true
  echo "$COMPONENTS" | grep -qw "cache" && show_cache=true
fi

parts=""

if $show_time; then
  case "$CACHE_AGE_TIER" in
    warm)    AGE_COLOR="$GREEN" ;;
    caution) AGE_COLOR="$YELLOW" ;;
    expired) AGE_COLOR="$RED" ;;
    *)       AGE_COLOR="$DIM" ;;
  esac

  if [[ "$COMPACT" == "True" ]]; then
    parts="${AGE_COLOR}${CACHE_AGE}${RESET}"
  else
    parts="${DIM}${ICON}${RESET}${AGE_COLOR}${CACHE_AGE}${RESET}"
  fi
fi

if $show_cache && [[ "${HAS_CACHE:-false}" == "true" ]]; then
  READ_FMT=$(fmt_k "$CACHE_READ")
  WRITE_FMT=$(fmt_k "$CACHE_WRITE")

  if [[ -n "$parts" ]]; then
    [[ "$COMPACT" == "True" ]] && parts="$parts " || parts="$parts ${DIM}|${RESET} "
  fi

  if [[ "$COMPACT" == "True" ]]; then
    parts="${parts}${GREEN}${READ_PREFIX_COMPACT}${READ_FMT}${RESET} ${YELLOW}${WRITE_PREFIX_COMPACT}${WRITE_FMT}${RESET}"
  else
    parts="${parts}${GREEN}${READ_PREFIX}${READ_FMT}${RESET} ${YELLOW}${WRITE_PREFIX}${WRITE_FMT}${RESET}"
  fi
fi

# Fallback: if nothing to show, show just the cache age
if [[ -z "$parts" ]]; then
  parts="${DIM}${CACHE_AGE}${RESET}"
fi

echo -e "{\"output\": \"$parts\", \"components\": [\"time\", \"cache\"]}"
