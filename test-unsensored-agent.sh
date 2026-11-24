#!/usr/bin/env bash
# Host-side smoke test for the Unsensored Agent VM Harness.
# Submits one bounded task and checks its final status plus recorded tool evidence.
set -Eeuo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8765}"
POLL_SECONDS="${POLL_SECONDS:-5}"
MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-1800}"
RESULT_DIR="${RESULT_DIR:-./agent-test-results}"

for tool in curl python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: Required command '$tool' is missing." >&2; exit 2; }
done
mkdir -p "$RESULT_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)_$$"
TEST_FILE="agent_smoke_test_${STAMP}.md"

curl_api() {
  curl --silent --show-error --connect-timeout 5 --max-time 30 "$@"
}

extract_status() {
  python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("task") or d).get("status", "unknown"))'
}

validate_events() {
  python3 - "$1" "$2" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
expected_test_id = sys.argv[2]
try:
    events = json.loads(p.read_text(encoding="utf-8"))
except Exception as e:
    print(f"FAIL: could not parse task events: {e}")
    raise SystemExit(1)

calls = set()
verified_reads = []
for ev in events:
    kind = ev.get("kind")
    payload = ev.get("payload") or {}
    if kind == "tool_call":
        calls.add(payload.get("name"))
    if kind == "tool_result" and payload.get("name") == "file_read":
        try:
            result = json.loads(payload.get("result", "{}"))
        except Exception:
            continue
        content = result.get("content", "")
        path = result.get("path", "")
        if "agent_smoke_test_" in path:
            verified_reads.append((path, content))

required = {"list_files", "file_write", "file_read"}
missing = sorted(required - calls)
if missing:
    print("FAIL: expected tool calls were not recorded: " + ", ".join(missing))
    print("Observed tool calls: " + (", ".join(sorted(x for x in calls if x)) or "none"))
    raise SystemExit(1)
if not verified_reads:
    print("FAIL: no file_read result for the smoke-test file was found in the audit events.")
    raise SystemExit(1)

path, content = verified_reads[-1]
checks = {
    "test heading": "# Agent Smoke Test" in content,
    "test id": expected_test_id in content,
    "pass marker": "Result: PASS" in content,
}
failed = [name for name, okay in checks.items() if not okay]
if failed:
    print("FAIL: final read-back missed: " + ", ".join(failed))
    print(f"Last matching read-back path: {path}")
    raise SystemExit(1)
print("PASS: recorded list_files, file_write and file_read tool calls.")
print("PASS: final file_read evidence includes the expected heading, test ID and Result: PASS.")
print(f"Verified guest path: {path}")
PY
}

echo "===== 1. API health ====="
HEALTH="$(curl_api -fsS "$BASE_URL/health")" || { echo "ERROR: Cannot reach $BASE_URL/health. Check the host SSH tunnel." >&2; exit 2; }
printf '%s\n' "$HEALTH" | python3 -m json.tool
python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("status")=="ok", f"API not healthy: {d}"; assert d.get("ollama_reachable") is True, f"Ollama is not reachable: {d}"; print("PASS: API healthy and Ollama reachable.")' <<< "$HEALTH"

echo
echo "===== 2. Dashboard and OpenAPI endpoints ====="
for path in / /openapi.json /docs; do
  code="$(curl_api -o /dev/null -w '%{http_code}' "$BASE_URL$path")"
  printf '%-16s HTTP %s\n' "$path" "$code"
  [[ "$code" == "200" ]] || { echo "ERROR: $path returned HTTP $code" >&2; exit 2; }
done

echo
echo "===== 3. Prepare a unique workspace smoke-test task ====="
export TEST_FILE TEST_ID="$STAMP"
PAYLOAD_FILE="$(mktemp)"
trap 'rm -f "$PAYLOAD_FILE"' EXIT
python3 - <<'PY' > "$PAYLOAD_FILE"
import json, os
filename = os.environ["TEST_FILE"]
test_id = os.environ["TEST_ID"]
goal = f'''Run a minimal, non-destructive filesystem smoke test inside the isolated VM.

Scope: ONLY /home/agent/workspace. Do not access anything outside that workspace.

Required steps:
1. Use the list_files tool to inspect the workspace before creating anything.
2. Use file_write (not shell_exec) to create a NEW Markdown file named {filename}. Never overwrite an existing file. If that name already exists, choose an unused name by adding a numeric suffix.
3. The file must contain the heading "# Agent Smoke Test", this exact test ID "{test_id}", a short list of the checks performed, and initially "Result: PENDING".
4. Use file_read to read the file back and verify its heading and test ID. If they match, use file_write to update the result to exactly "Result: PASS". Then use file_read again and verify the final version contains the heading, exact test ID, and "Result: PASS".
5. Report the exact guest file path, the tools actually used, read-back evidence, and any errors. Do not claim PASS unless the final file_read confirms the required text.

Restrictions: do not use shell_exec, browser tools, desktop tools, web search, persistent memory, network access, elevated privileges, or any tools other than list_files, file_write, and file_read. Do not modify or delete any pre-existing files. This is a test of the task planner, tool calls, file operations, audit events, and final verifier.'''
print(json.dumps({"goal": goal}))
PY
SUBMISSION="$(curl_api -fsS -H 'Content-Type: application/json' --data-binary "@$PAYLOAD_FILE" "$BASE_URL/tasks")"
printf '%s\n' "$SUBMISSION" | tee "$RESULT_DIR/submission.json" | python3 -m json.tool
TASK_ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))' <<< "$SUBMISSION")"
[[ -n "$TASK_ID" ]] || { echo "ERROR: /tasks response did not contain an id." >&2; exit 2; }
echo "Task ID: $TASK_ID"
echo "Dashboard: $BASE_URL/"
echo "Task details: $BASE_URL/tasks/$TASK_ID"

printf '%s\n' "$TASK_ID" > "$RESULT_DIR/latest-task-id.txt"
END_STATUS="unknown"
ELAPSED=0

echo
echo "===== 4. Poll task status (max ${MAX_WAIT_SECONDS}s) ====="
while (( ELAPSED < MAX_WAIT_SECONDS )); do
  DETAIL="$(curl_api -fsS "$BASE_URL/tasks/$TASK_ID")"
  printf '%s\n' "$DETAIL" > "$RESULT_DIR/$TASK_ID.detail.json"
  END_STATUS="$(extract_status <<< "$DETAIL")"
  printf '[%4ss] status=%s\n' "$ELAPSED" "$END_STATUS"
  case "$END_STATUS" in
    completed|failed|partial|stopped) break ;;
  esac
  sleep "$POLL_SECONDS"
  ELAPSED=$((ELAPSED + POLL_SECONDS))
done

# Save the final detail, event audit and report where available.
curl_api -fsS "$BASE_URL/tasks/$TASK_ID" > "$RESULT_DIR/$TASK_ID.detail.json"
curl_api -fsS "$BASE_URL/tasks/$TASK_ID/events?limit=1000" > "$RESULT_DIR/$TASK_ID.events.json"
if curl_api -fsS "$BASE_URL/tasks/$TASK_ID/report" > "$RESULT_DIR/$TASK_ID.report.md"; then
  echo "Saved task report: $RESULT_DIR/$TASK_ID.report.md"
else
  rm -f "$RESULT_DIR/$TASK_ID.report.md"
  echo "Note: report endpoint is not available yet."
fi

echo
echo "===== 5. Final task details ====="
python3 -m json.tool < "$RESULT_DIR/$TASK_ID.detail.json" | sed -n '1,200p'

echo
echo "===== 6. Audit evidence validation ====="
if [[ "$END_STATUS" != "completed" ]]; then
  echo "FAIL: task ended with status '$END_STATUS' (or timed out). Inspect: $RESULT_DIR/$TASK_ID.detail.json and $RESULT_DIR/$TASK_ID.events.json"
  exit 1
fi
if ! validate_events "$RESULT_DIR/$TASK_ID.events.json" "$STAMP"; then
  echo "FAIL: task reached completed status but the smoke-test tool evidence did not validate." >&2
  echo "Inspect audit events: $RESULT_DIR/$TASK_ID.events.json" >&2
  exit 1
fi

echo
echo "===== PASS ====="
echo "API, dashboard, OpenAPI, model connectivity, task creation, task execution and file-tool read-back checks passed."
echo "Task ID: $TASK_ID"
echo "Results directory: $RESULT_DIR"
