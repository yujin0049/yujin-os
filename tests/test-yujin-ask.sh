#!/bin/bash
# yujin-ask: 로컬 모델이 MCP 도구를 부르고 답하는지, 바깥 주소를 거부하는지 (가짜 모델·가짜 MCP)
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'kill "${llm_pid:-}" 2>/dev/null || true; rm -rf "$tmp"' EXIT

cat > "$tmp/mcp.py" <<'PY'
import json, sys
for line in sys.stdin:
    m = json.loads(line)
    if "id" not in m:
        continue
    r = {}
    if m["method"] == "tools/list":
        r = {"tools": [{"name": "echo", "description": "echo", "inputSchema": {"type": "object"}}]}
    elif m["method"] == "tools/call":
        r = {"content": [{"type": "text", "text": "도구답-" + m["params"]["arguments"].get("x", "")}]}
    print(json.dumps({"jsonrpc": "2.0", "id": m["id"], "result": r}), flush=True)
PY
cat > "$tmp/llm.py" <<'PY'
import json, http.server, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        b = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        last = b["messages"][-1]
        if last["role"] == "user":
            m = {"role": "assistant", "tool_calls": [{"id": "1", "type": "function",
                 "function": {"name": "t__echo", "arguments": "{\"x\": \"ok\"}"}}]}
        else:
            m = {"role": "assistant", "content": "답: " + last["content"]}
        o = json.dumps({"choices": [{"message": m}]}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(o)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(s.server_address[1]))
s.serve_forever()
PY
python3 "$tmp/llm.py" "$tmp/port" & llm_pid=$!
for _ in $(seq 50); do [[ -s "$tmp/port" ]] && break; sleep 0.1; done
port="$(cat "$tmp/port")"
printf '{"llm":"http://127.0.0.1:%s/v1","mcp":{"t":["python3","%s"]}}' "$port" "$tmp/mcp.py" > "$tmp/ok.json"
out="$(XDG_CONFIG_HOME="$tmp" YUJIN_AGENT_CONF="$tmp/ok.json" python3 "$here/system_files/usr/local/bin/yujin-ask" "질문" 2>/dev/null)"
[[ "$out" == "답: 도구답-ok" ]] || { echo "FAIL: tool loop: $out"; exit 1; }
printf '{"llm":"http://example.com/v1"}' > "$tmp/bad.json"
if XDG_CONFIG_HOME="$tmp" YUJIN_AGENT_CONF="$tmp/bad.json" python3 "$here/system_files/usr/local/bin/yujin-ask" hi >/dev/null 2>&1; then
  echo "FAIL: remote llm accepted"; exit 1
fi
# serve: 질문 둘을 동시에 받아 둘 다 끝내고, 처리 중에 죽어도 다시 켜면 이어서 끝낸다
state="$tmp/state"; sp=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
run_serve() { XDG_STATE_HOME="$state" XDG_CONFIG_HOME="$tmp" YUJIN_AGENT_CONF="$tmp/ok.json" python3 "$here/system_files/usr/local/bin/yujin-ask" serve "$sp" 2>/dev/null & serve_pid=$!; for _ in $(seq 50); do curl -s -m 1 "127.0.0.1:$sp/api/chats" >/dev/null && break; sleep 0.1; done; }
trap 'kill "${llm_pid:-}" "${serve_pid:-}" 2>/dev/null || true; rm -rf "$tmp"' EXIT
run_serve
curl -s -m 5 -X POST "127.0.0.1:$sp/api/ask" -d '{"q":"하나"}' >/dev/null & a=$!
curl -s -m 5 -X POST "127.0.0.1:$sp/api/ask" -d '{"q":"둘"}' >/dev/null & b=$!
wait "$a" "$b"
done_count() { python3 -c "import sqlite3,sys;print(sqlite3.connect(sys.argv[1]).execute(\"SELECT COUNT(*) FROM 질문 WHERE 상태='끝'\").fetchone()[0])" "$state/yujin-os/ask.db"; }
for _ in $(seq 50); do [[ "$(done_count)" == 2 ]] && break; sleep 0.1; done
[[ "$(done_count)" == 2 ]] || { echo "FAIL: serve concurrent: $(done_count)"; exit 1; }
kill -9 "$serve_pid"; wait "$serve_pid" 2>/dev/null || true
python3 -c "import sqlite3,sys;c=sqlite3.connect(sys.argv[1]);c.execute(\"INSERT INTO 질문 (대화, 글, 상태) VALUES (1, '셋', '처리중')\");c.commit()" "$state/yujin-os/ask.db"
run_serve
for _ in $(seq 50); do [[ "$(done_count)" == 3 ]] && break; sleep 0.1; done
[[ "$(done_count)" == 3 ]] || { echo "FAIL: serve resume after crash: $(done_count)"; exit 1; }
echo "PASS test-yujin-ask.sh"
