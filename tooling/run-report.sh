#!/usr/bin/env bash
# What did a run actually spend its time and tokens on?
#
#   run-report.sh <session-transcript.jsonl> [--tsv]
#   run-report.sh --latest <project-dir>        the most recently written one
#
# Agent sessions are Claude Code sessions, so each one writes a full JSONL
# transcript: every tool call, every timestamp, every token. This reads that and
# names the things that waste a run — the same file read five times, the same
# command run again, long gaps, tokens spent before the first write.
#
# Deterministic. No model is called to analyse a model.
set -uo pipefail
if [ "${1:-}" = "--latest" ]; then
  D=${2:?project dir}
  F=$(ls -t "$D"/*.jsonl 2>/dev/null | head -1)
  [ -n "$F" ] || { echo "no transcripts in $D" >&2; exit 66; }
else
  F=${1:?transcript.jsonl}
fi
[ -f "$F" ] || { echo "no such transcript: $F" >&2; exit 66; }

python3 - "$F" "${2:-}" <<'PY'
import json, re, sys, collections, datetime

path, flag = sys.argv[1], sys.argv[2]
tools, reads, bashes, stamps = [], collections.Counter(), collections.Counter(), []
opened = collections.Counter()
tok_in = tok_out = tok_cache = thinking_ms = 0
model = None

with open(path) as fh:
    for line in fh:
        try: d = json.loads(line)
        except Exception: continue
        ts = d.get("timestamp")
        if ts: stamps.append(ts)
        if d.get("type") != "assistant": continue
        m = d.get("message", {}) or {}
        model = model or m.get("model")
        u = m.get("usage") or {}
        tok_in    += u.get("input_tokens") or 0
        tok_out   += u.get("output_tokens") or 0
        tok_cache += (u.get("cache_read_input_tokens") or 0)
        thinking_ms += d.get("thinkingDurationMs") or 0
        for b in (m.get("content") or []):
            if not isinstance(b, dict) or b.get("type") != "tool_use": continue
            name = b.get("name", "?")
            tools.append((ts, name))
            inp = b.get("input") or {}
            if name in ("Read", "NotebookRead"):
                reads[inp.get("file_path", "?")] += 1
            elif name == "Bash":
                cmd = inp.get("command") or ""
                bashes[cmd[:90]] += 1
                # An agent reads far more through cat/sed/head/grep than through
                # the Read tool, so counting Read alone reports "nothing was read
                # twice" about a run that read one file eight times.
                for m2 in re.finditer(r'(/(?:[\w.\-]+/)+[\w.\-]+\.\w+)', cmd):
                    opened[m2.group(1)] += 1

def when(s):
    try: return datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception: return None

span = ""
if stamps:
    a, b = when(min(stamps)), when(max(stamps))
    if a and b: span = str(b - a).split(".")[0]

if flag == "--tsv":
    print("metric\tvalue")
    print(f"wall\t{span}")
    print(f"tool_calls\t{len(tools)}")
    print(f"output_tokens\t{tok_out}")
    print(f"cache_read_tokens\t{tok_cache}")
    for f, n in reads.most_common():
        print(f"read\t{n}\t{f}")
    sys.exit(0)

print(f"transcript : {path.split('/')[-1]}")
print(f"model      : {model}")
print(f"wall clock : {span}")
print(f"thinking   : {thinking_ms/1000:.0f}s")
print(f"tokens     : {tok_out} out, {tok_in} in, {tok_cache} cache-read")
print(f"tool calls : {len(tools)}")
print()
print("BY TOOL")
for name, n in collections.Counter(t for _, t in tools).most_common():
    print(f"  {n:4}  {name}")

# The signature of a run that does not know where anything is: the same file,
# again. Once is reading. Three times is looking for something.
combined = collections.Counter()
combined.update(reads); combined.update(opened)
repeat = [(f, n) for f, n in combined.most_common() if n > 1]
print()
print("FILES OPENED MORE THAN ONCE" if repeat else "NO FILE WAS OPENED TWICE")
for f, n in repeat[:20]:
    print(f"  {n:3}x  {f}")

rebash = [(c, n) for c, n in bashes.most_common() if n > 1]
if rebash:
    print()
    print("COMMANDS RUN MORE THAN ONCE")
    for c, n in rebash[:12]:
        print(f"  {n:3}x  {c}")

wasted = sum(n - 1 for _, n in repeat)
print()
print(f"{wasted} re-read(s) of a file this run had already seen.")
if wasted:
    print("Each one is a path the formula could have handed it instead.")
PY
