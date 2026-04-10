#!/usr/bin/env bash
# Last interaction timestamp + cache token usage
#
# Shows when you last interacted with Claude and how many tokens
# were read from / written to cache. Helps you gauge cache freshness
# and cost efficiency at a glance.

set -euo pipefail

INPUT=$(cat)

COMPACT=False COMPONENTS="" DIM="" LGRAY="" GREEN="" YELLOW="" RESET="" ICON=""
READ_PREFIX="read:" WRITE_PREFIX="write:" READ_PREFIX_COMPACT="R:" WRITE_PREFIX_COMPACT="W:"
CACHE_READ=0 CACHE_WRITE=0

eval "$(echo "$INPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
cfg = d.get('config', {})
palette = cfg.get('palette', {})
icons = cfg.get('icons', {})
data = d.get('data', {})
cw = data.get('context_window', {})
cu = cw.get('current_usage', {})
print(f'COMPACT={cfg.get(\"compact\", False)}')
print('COMPONENTS=\"' + ','.join(cfg.get('components', [])) + '\"')
print(f'DIM=\"{palette.get(\"muted\", \"\")}\"')
print(f'LGRAY=\"{palette.get(\"subtle\", \"\")}\"')
print(f'GREEN=\"{palette.get(\"success\", \"\")}\"')
print(f'YELLOW=\"{palette.get(\"warning\", \"\")}\"')
print(f'RESET=\"{palette.get(\"reset\", \"\")}\"')
print(f'ICON=\"{icons.get(\"icon\", \"\u23F1 \")}\"')
print(f'READ_PREFIX=\"{icons.get(\"cache_read\", \"read:\")}\"')
print(f'WRITE_PREFIX=\"{icons.get(\"cache_write\", \"write:\")}\"')
print(f'READ_PREFIX_COMPACT=\"{icons.get(\"cache_read_compact\", \"R:\")}\"')
print(f'WRITE_PREFIX_COMPACT=\"{icons.get(\"cache_write_compact\", \"W:\")}\"')
cr = cu.get('cache_read_input_tokens')
cc = cu.get('cache_creation_input_tokens')
print(f'CACHE_READ={cr if cr is not None else 0}')
print(f'CACHE_WRITE={cc if cc is not None else 0}')
print(f'HAS_CACHE={\"true\" if cr is not None else \"false\"}')
" 2>/dev/null)"

TIMESTAMP=$(date +%H:%M:%S)

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
  if [[ "$COMPACT" == "True" ]]; then
    parts="${LGRAY}${TIMESTAMP}${RESET}"
  else
    parts="${DIM}${ICON}${RESET}${LGRAY}${TIMESTAMP}${RESET}"
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

# Fallback: if nothing to show, show just the timestamp
if [[ -z "$parts" ]]; then
  parts="${LGRAY}${TIMESTAMP}${RESET}"
fi

echo -e "{\"output\": \"$parts\", \"components\": [\"time\", \"cache\"]}"
