#!/bin/bash
# Prints the Prosper ticket board from Basira (local life-OS app) so every
# Claude Code session starts by looking at the tracker. Wired up as a
# SessionStart hook in .claude/settings.json. Safe to run by hand:
#   bash scripts/basira-board.sh | jq -r .hookSpecificOutput.additionalContext
B="${BASIRA_URL:-http://127.0.0.1:8001}"

emit() {
  jq -n --arg m "$1" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
}

companies=$(curl -s -m 4 "$B/companies" 2>/dev/null)
company_id=$(printf '%s' "$companies" | jq -r '.[]? | select(.name=="Prosper") | .id' 2>/dev/null | head -1)
if [ -z "$company_id" ]; then
  emit "PROSPER TICKETS: Basira is not reachable at $B (or has no Prosper company). Tickets for this project live ONLY in Basira (Work → Prosper). Start it with: launchctl load ~/Library/LaunchAgents/com.sysgo.backend.plist, then re-run scripts/basira-board.sh before picking up work. See CLAUDE.md → Workflow."
  exit 0
fi

tickets=$(curl -s -m 4 "$B/work-tickets?company_id=$company_id" 2>/dev/null)
if ! printf '%s' "$tickets" | jq -e 'type=="array"' >/dev/null 2>&1; then
  emit "PROSPER TICKETS: Basira answered but the ticket list failed to load from $B. Check the tracker before working. See CLAUDE.md → Workflow."
  exit 0
fi

board=$(printf '%s' "$tickets" | jq -r '
  def sorder: {"blocked":0,"in_progress":1,"review":2,"todo":3,"backlog":4};
  def porder: {"urgent":0,"high":1,"medium":2,"low":3};
  map(select(.status != "done"))
  | sort_by([(sorder[.status] // 9), (porder[.priority] // 9), .ticket_ref])
  | .[] | "  [\(.status)] \(.priority) \(.ticket_ref) — \(.title)"')
done_count=$(printf '%s' "$tickets" | jq '[.[] | select(.status=="done")] | length')
open_count=$(printf '%s' "$tickets" | jq '[.[] | select(.status!="done")] | length')

msg=$(printf 'PROSPER BOARD — source of truth is Basira (%s → Work → Prosper). %s open, %s done.\n%s\n\nWORKFLOW RULE: check this board before starting anything. Pick work from it (todo → in_progress when you start). When work lands: PUT /work-tickets/{id} to set status (review with the PR URL as a "proof" comment, or done) and POST a dated note comment. New scope = new ticket first. Details: CLAUDE.md → Workflow.' "$B" "$open_count" "$done_count" "$board")
emit "$msg"
