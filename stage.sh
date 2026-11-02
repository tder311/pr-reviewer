#!/usr/bin/env bash
# Runs one headless Claude call in $WORK and saves its structured output.
# ./stage.sh <model> <schema.json> <prompt.md> <out.json>. EXTRA_TOOLS adds tools, e.g. Skill,Agent.
set -euo pipefail

model=$1 schema=$2 prompt=$3 out=$4
tools="Read,Grep,Glob,Bash(git diff:*),Bash(git log:*),Bash(git show:*),Bash(git blame:*),Bash(git merge-base:*),Bash(git rev-parse:*),Bash(git status:*)"

# Read-only by construction: no Write/Edit, no network, git reads only, no user plugins or MCP servers.
(cd "$WORK" && claude -p "$(cat "$prompt")" \
  --model "$model" \
  --output-format json --json-schema "$(cat "$schema")" \
  --permission-mode dontAsk --setting-sources project,local --strict-mcp-config --no-session-persistence \
  --allowedTools "$tools${EXTRA_TOOLS:+,$EXTRA_TOOLS}" \
  --disallowedTools "Write,Edit,NotebookEdit,WebFetch,WebSearch") >"$out.raw"
jq -e .structured_output "$out.raw" >"$out.tmp"
mv "$out.tmp" "$out"
