#!/usr/bin/env python3
"""Loopback-only host control plane for the Unsensored Agent VM harness.
Uses only the Python standard library. The VM API remains the source of truth for tasks.
"""
from __future__ import annotations
import argparse, json, os, re, shutil, socket, subprocess, threading, time, urllib.error, urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
GUEST_API = os.getenv("UNSENSORED_GUEST_API", "http://127.0.0.1:8765").rstrip("/")
OLLAMA_API = os.getenv("UNSENSORED_OLLAMA_API", "http://127.0.0.1:11434").rstrip("/")
PORT = int(os.getenv("UNSENSORED_CONTROL_PORT", "8766"))
STATE_DIR = Path(os.getenv("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "unsensored-agent-control"
ACTIONS_DIR = STATE_DIR / "actions"
PULSE_FILE = STATE_DIR / "hourly-pulse.jsonl"
STATE_DIR.mkdir(parents=True, exist_ok=True)
ACTIONS_DIR.mkdir(parents=True, exist_ok=True)
PULSE_LOCK = threading.Lock()
ACTION_LOCK = threading.Lock()
ACTIONS: dict[str, dict] = {}


def utcnow(): return datetime.now(timezone.utc).isoformat()


def cmd(args, timeout=3):
    try:
        p = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=timeout, check=False)
        return {"ok": p.returncode == 0, "code": p.returncode, "output": p.stdout.strip()[-4000:]}
    except Exception as e:
        return {"ok": False, "code": None, "output": str(e)}


def port_open(port: int, host="127.0.0.1", timeout=0.35):
    try:
        with socket.create_connection((host, port), timeout=timeout): return True
    except OSError: return False


def http_json(url, timeout=2.5):
    req = urllib.request.Request(url, headers={"User-Agent": "Unsensored-Control-Plane/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        body = r.read(2_000_000)
        return json.loads(body.decode("utf-8", "replace"))


def get_guest(path, timeout=5):
    return http_json(GUEST_API + path, timeout=timeout)


def post_guest(path, payload=None, timeout=8):
    data = json.dumps(payload or {}).encode()
    req = urllib.request.Request(GUEST_API + path, data=data, headers={"Content-Type":"application/json", "User-Agent":"Unsensored-Control-Plane/1.0"}, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        b = r.read(2_000_000)
        return json.loads(b.decode("utf-8", "replace")) if b else {"ok": True}


def active_user_service(name):
    r = cmd(["systemctl", "--user", "is-active", name], timeout=2)
    val = r["output"].splitlines()[0] if r["output"] else "unknown"
    return {"name": name, "status": val, "active": r["ok"] and val == "active"}


def read_memory():
    try:
        vals = {}
        for line in Path("/proc/meminfo").read_text().splitlines():
            k, rest = line.split(":", 1); vals[k] = int(rest.strip().split()[0]) * 1024
        total = vals.get("MemTotal", 0); avail = vals.get("MemAvailable", 0)
        st = vals.get("SwapTotal", 0); sf = vals.get("SwapFree", 0)
        return {"total_bytes": total, "available_bytes": avail, "used_bytes": max(0,total-avail), "used_pct": round((total-avail)*100/total,1) if total else None,
                "swap_total_bytes": st, "swap_free_bytes": sf, "swap_used_bytes": max(0,st-sf), "swap_used_pct": round((st-sf)*100/st,1) if st else 0}
    except Exception as e: return {"error": str(e)}


def host_gpu():
    r = cmd(["nvidia-smi", "--query-gpu=name,memory.total,memory.used,utilization.gpu,temperature.gpu", "--format=csv,noheader,nounits"], timeout=2)
    if not r["ok"]: return {"available": False, "detail": r["output"] or "nvidia-smi unavailable"}
    gpus=[]
    for line in r["output"].splitlines():
        bits=[x.strip() for x in line.split(",")]
        if len(bits)>=5:
            try: gpus.append({"name":bits[0],"memory_total_mib":float(bits[1]),"memory_used_mib":float(bits[2]),"utilization_pct":float(bits[3]),"temperature_c":float(bits[4])})
            except ValueError: pass
    return {"available": bool(gpus), "gpus":gpus, "detail":r["output"]}


def host_ollama():
    try:
        tags=http_json(OLLAMA_API+"/api/tags", timeout=2.5)
        loaded=http_json(OLLAMA_API+"/api/ps", timeout=2.5)
        return {"reachable":True,"installed_models":[m.get("name") for m in tags.get("models",[]) if m.get("name")],"loaded_models":[{"name":m.get("name"),"size":m.get("size"),"size_vram":m.get("size_vram"),"expires_at":m.get("expires_at")} for m in loaded.get("models",[])],"error":None}
    except Exception as e: return {"reachable":False,"installed_models":[],"loaded_models":[],"error":str(e)}


def qemu_info():
    pidfile=ROOT/"vm/qemu.pid"; pid=None; alive=False; cmdline=""
    try:
        pid=int(pidfile.read_text().strip()); os.kill(pid,0)
        cp=Path(f"/proc/{pid}/cmdline")
        cmdline=cp.read_bytes().replace(b"\0",b" ").decode(errors="replace") if cp.exists() else ""
        alive="qemu-system" in cmdline
    except Exception: pid=None; alive=False
    disk=ROOT/"vm/disk.qcow2"
    disk_info={"exists":disk.exists(),"allocated_bytes":disk.stat().st_size if disk.exists() else 0}
    virtual=None
    if disk.exists():
        qi=cmd(["qemu-img","info","--output=json",str(disk)], timeout=3)
        if qi["ok"]:
            try: virtual=json.loads(qi["output"]).get("virtual-size")
            except Exception: pass
    disk_info["virtual_bytes"]=virtual
    return {"running":alive,"pid":pid if alive else None,"cmdline":cmdline[:220] if alive else None,"disk":disk_info,"ssh_port_open":port_open(2222)}


def overview():
    vm=qemu_info(); tunnel=active_user_service("unsensored-agent-tunnel.service"); proxy=active_user_service("unsensored-agent-proxy.service"); novnc=active_user_service("unsensored-agent-novnc-tunnel.service")
    try:
        health=get_guest("/health", timeout=4)
        api={"reachable":True,"health":health,"error":None}
    except Exception as e: api={"reachable":False,"health":None,"error":str(e)}
    guest_services={"reachable":False,"services":{},"error":None}
    if vm["ssh_port_open"]:
        root_key=ROOT/"vm/agent_vm_ed25519"; known=ROOT/"vm/known_hosts"
        s=cmd(["ssh","-i",str(root_key),"-p","2222","-o","BatchMode=yes","-o","ConnectTimeout=3","-o","StrictHostKeyChecking=accept-new","-o",f"UserKnownHostsFile={known}","agent@127.0.0.1", "systemctl is-active unsensored-agent.service agent-desktop.service agent-vnc.service agent-novnc.service"], timeout=5)
        lines=s["output"].splitlines()
        names=["agent","desktop","vnc","novnc"]
        guest_services={"reachable":s["code"] == 0 or len(lines)>0,"services":{n:(lines[i] if i<len(lines) else "unknown") for i,n in enumerate(names)},"error":None if lines else s["output"]}
    mem=read_memory(); disk=shutil.disk_usage(ROOT)
    try: load=[float(x) for x in Path("/proc/loadavg").read_text().split()[:3]]
    except Exception: load=[]
    return {"timestamp":utcnow(),"project_root":str(ROOT),"dashboard":{"status":"active","port":PORT},"vm":vm,
      "services":{"tunnel":tunnel,"proxy":proxy,"novnc_tunnel":novnc},"guest_api":api,"guest_services":guest_services,
      "ollama":host_ollama(),"memory":mem,"gpu":host_gpu(),"host":{"load_average":load,"disk_free_bytes":disk.free,"disk_total_bytes":disk.total,"disk_used_pct":round((disk.total-disk.free)*100/disk.total,1) if disk.total else None},
      "ports":{"agent_api":port_open(8765),"vnc":port_open(5901),"novnc":port_open(6081)},
      "urls":{"agent_api":"http://127.0.0.1:8765","api_docs":"http://127.0.0.1:8765/docs","novnc":"http://127.0.0.1:6081/vnc.html?autoconnect=true"}}


def launch_action(action):
    mapping={
      "start_stack":"start-stack.sh", "stop_stack":"stop-stack.sh",
      "start_agent":"start-agent.sh", "stop_agent":"stop-agent.sh", "force_stop_agent":"interrupt-agent.sh",
      "start_vm":"start-vm.sh", "stop_vm":"stop-vm.sh",
      "start_novnc":"start-novnc.sh", "stop_novnc":"stop-novnc.sh",
      "start_dashboard":"start-dashboard.sh", "stop_dashboard":"stop-dashboard.sh",
      "repair_desktop":"repair-desktop.sh"
    }
    if action not in mapping: raise ValueError("Unsupported action")
    script=HERE/mapping[action]
    if not script.exists(): raise FileNotFoundError(str(script))
    aid=datetime.now().strftime("%Y%m%d-%H%M%S-")+action
    log_path=ACTIONS_DIR/(aid+".log")
    log_file=log_path.open("w",encoding="utf-8")
    proc=subprocess.Popen(["/bin/bash",str(script)],cwd=str(ROOT),stdout=log_file,stderr=subprocess.STDOUT,start_new_session=True,close_fds=True)
    with ACTION_LOCK:
        ACTIONS[aid]={"id":aid,"action":action,"pid":proc.pid,"process":proc,"log":str(log_path),"started_at":utcnow()}
    return {"id":aid,"action":action,"pid":proc.pid,"status":"running","log":str(log_path)}


def action_status():
    out=[]
    with ACTION_LOCK:
        items=list(ACTIONS.items())
    for aid,a in reversed(items[-12:]):
        proc=a["process"]; rc=proc.poll(); log=Path(a["log"])
        try: tail="\n".join(log.read_text(errors="replace").splitlines()[-24:])
        except Exception: tail=""
        out.append({"id":aid,"action":a["action"],"pid":a["pid"],"status":"running" if rc is None else ("succeeded" if rc==0 else "failed"),"returncode":rc,"started_at":a["started_at"],"log_tail":tail})
    return out


def pulse_snapshot():
    """Write a deterministic hourly status note. This never calls the LLM."""
    try:
        ov = overview()
    except Exception as e:
        ov = {"timestamp": utcnow(), "vm": {"running": False}, "guest_api": {"reachable": False, "error": str(e)}, "ollama": {"reachable": False}, "memory": {}}
    try:
        tasks = get_guest("/tasks", timeout=8)
        if not isinstance(tasks, list): tasks = []
    except Exception:
        tasks = []
    counts = {k: sum(1 for t in tasks if t.get("status") == k) for k in ("queued", "running", "completed", "failed", "partial", "stopped")}
    vm_online = bool((ov.get("vm") or {}).get("running"))
    api_online = bool((ov.get("guest_api") or {}).get("reachable"))
    ollama_online = bool((ov.get("ollama") or {}).get("reachable"))
    mem = ov.get("memory") or {}
    parts = [
        "VM " + ("online" if vm_online else "offline"),
        "agent API " + ("healthy" if api_online else "unavailable"),
        "Ollama " + ("reachable" if ollama_online else "unavailable"),
        f"tasks: {counts['running']} running, {counts['queued']} queued, {counts['completed']} completed, {counts['failed'] + counts['partial'] + counts['stopped']} blocked/stopped",
    ]
    if mem.get("used_pct") is not None:
        parts.append(f"host RAM {mem['used_pct']}% used")
    if mem.get("swap_used_pct") is not None and mem.get("swap_total_bytes", 0):
        parts.append(f"swap {mem['swap_used_pct']}% used")
    active = [t for t in tasks if t.get("status") in ("queued", "running")][:3]
    active_items = []
    for t in active:
        item = {"id": str(t.get("id", "")), "status": t.get("status", "unknown"),
                "stage": int(t.get("current_stage", 0) or 0) + 1,
                "goal": re.sub(r"\s+", " ", str(t.get("goal", ""))).strip()[:180],
                "last_event": None}
        try:
            events = get_guest(f"/tasks/{item['id']}/events?limit=20", timeout=5)
            if isinstance(events, list) and events:
                e = events[-1]
                payload = e.get("payload") or {}
                if not payload and e.get("payload_json"):
                    try: payload = json.loads(e["payload_json"])
                    except Exception: payload = {}
                description = next((str(payload[k]) for k in ("name", "title", "stage_title", "summary", "error", "status") if payload.get(k)), "")
                if not description:
                    description = json.dumps(payload, ensure_ascii=False)[:180]
                item["last_event"] = {"kind": e.get("kind", "event"), "ts": e.get("ts"), "summary": description[:220]}
        except Exception:
            pass
        active_items.append(item)
    entry = {"timestamp": ov.get("timestamp", utcnow()), "summary": " · ".join(parts),
             "counts": counts, "active_tasks": active_items,
             "vm_online": vm_online, "api_online": api_online, "ollama_online": ollama_online,
             "memory_used_pct": mem.get("used_pct"), "swap_used_pct": mem.get("swap_used_pct"),
             "source": "local status and persisted task metadata; no LLM request"}
    try:
        with PULSE_LOCK:
            with PULSE_FILE.open("a", encoding="utf-8") as f:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")
            # Keep a bounded history: 500 hourly lines is about three weeks.
            lines = PULSE_FILE.read_text(encoding="utf-8").splitlines()
            if len(lines) > 500:
                PULSE_FILE.write_text("\n".join(lines[-500:]) + "\n", encoding="utf-8")
    except OSError:
        pass
    return entry


def read_pulses(limit=72):
    try:
        lines = PULSE_FILE.read_text(encoding="utf-8").splitlines()[-max(1, min(200, limit)):]
        out = []
        for line in reversed(lines):
            try: out.append(json.loads(line))
            except json.JSONDecodeError: continue
        return out
    except OSError:
        return []


def pulse_worker():
    # The first pulse makes the current state visible immediately; later pulses are hourly.
    pulse_snapshot()
    while True:
        time.sleep(3600)
        pulse_snapshot()


INDEX=(HERE/"index.html").read_text(encoding="utf-8")

class Handler(BaseHTTPRequestHandler):
    server_version="UnsensoredControlPlane/1.0"
    def log_message(self, fmt, *args):
        # concise stdout logging for systemd journal
        print(f"[{self.log_date_time_string()}] {self.address_string()} {fmt%args}", flush=True)
    def send_bytes(self, code, content, content_type="application/json; charset=utf-8"):
        if isinstance(content,str): content=content.encode()
        self.send_response(code); self.send_header("Content-Type",content_type); self.send_header("Content-Length",str(len(content))); self.send_header("Cache-Control","no-store"); self.end_headers(); self.wfile.write(content)
    def send_json(self, code, obj): self.send_bytes(code,json.dumps(obj,ensure_ascii=False).encode(),"application/json; charset=utf-8")
    def body_json(self):
        n=int(self.headers.get("Content-Length","0"));
        if n>250_000: raise ValueError("Request body too large")
        raw=self.rfile.read(n) if n else b"{}"
        return json.loads(raw.decode() or "{}")
    def local_guard(self):
        host=self.headers.get("Host","").split(":",1)[0]
        origin=self.headers.get("Origin")
        if host not in {"127.0.0.1","localhost"}: return False
        if origin:
            try:
                h=urlparse(origin).hostname
                if h not in {"127.0.0.1","localhost"}: return False
            except Exception: return False
        return True
    def do_GET(self):
        path=urlparse(self.path).path
        if path=="/" or path=="/index.html": return self.send_bytes(200,INDEX,"text/html; charset=utf-8")
        if path=="/favicon.ico": return self.send_bytes(204,b"","image/x-icon")
        if path=="/api/control/overview":
            try: return self.send_json(200,overview())
            except Exception as e: return self.send_json(500,{"error":str(e)})
        if path=="/api/control/actions": return self.send_json(200,action_status())
        if path=="/api/control/pulses": return self.send_json(200,read_pulses())
        if path=="/api/tasks":
            try: return self.send_json(200,get_guest("/tasks",timeout=8))
            except Exception as e: return self.send_json(502,{"error":"Guest API unavailable","detail":str(e)})
        m=re.fullmatch(r"/api/tasks/([A-Za-z0-9_-]+)(?:/(events|report))?",path)
        if m:
            tid,leaf=m.group(1),m.group(2)
            route=f"/tasks/{tid}"+(f"/{leaf}" if leaf else "")
            if leaf=="events": route+="?limit=200"
            try:
                if leaf=="report":
                    req=urllib.request.Request(GUEST_API+route)
                    with urllib.request.urlopen(req,timeout=8) as r: return self.send_bytes(200,r.read(1_000_000),"text/markdown; charset=utf-8")
                return self.send_json(200,get_guest(route,timeout=8))
            except urllib.error.HTTPError as e:
                return self.send_json(e.code,{"error":"Guest API returned an error","detail":e.read(4000).decode(errors="replace")})
            except Exception as e: return self.send_json(502,{"error":"Guest API unavailable","detail":str(e)})
        if path.startswith("/api/"): return self.send_json(404,{"error":"Unknown API route"})
        return self.send_bytes(404,"Not found","text/plain; charset=utf-8")
    def do_POST(self):
        if not self.local_guard(): return self.send_json(403,{"error":"Loopback/local-origin requests only"})
        path=urlparse(self.path).path
        try: body=self.body_json()
        except Exception as e: return self.send_json(400,{"error":str(e)})
        if path=="/api/tasks":
            try: return self.send_json(201,post_guest("/tasks",body,timeout=10))
            except Exception as e: return self.send_json(502,{"error":"Could not submit task","detail":str(e)})
        if path=="/api/control/action":
            try: return self.send_json(202,launch_action(str(body.get("action",""))))
            except Exception as e: return self.send_json(400,{"error":str(e)})
        m=re.fullmatch(r"/api/tasks/([A-Za-z0-9_-]+)/(stop|resume)",path)
        if m:
            try: return self.send_json(200,post_guest(f"/tasks/{m.group(1)}/{m.group(2)}",{},timeout=8))
            except urllib.error.HTTPError as e: return self.send_json(e.code,{"error":e.read(3000).decode(errors="replace")})
            except Exception as e: return self.send_json(502,{"error":str(e)})
        return self.send_json(404,{"error":"Unknown API route"})


def main():
    parser=argparse.ArgumentParser(); parser.add_argument("--host",default="127.0.0.1"); parser.add_argument("--port",type=int,default=PORT); parser.add_argument("--once",action="store_true",help="Print status JSON and exit")
    args=parser.parse_args()
    if args.once: print(json.dumps(overview(),indent=2,ensure_ascii=False)); return
    if args.host not in {"127.0.0.1","localhost"}: raise SystemExit("Refusing to bind to a non-loopback interface")
    server=ThreadingHTTPServer((args.host,args.port),Handler); server.daemon_threads=True
    threading.Thread(target=pulse_worker, name="hourly-status-pulse", daemon=True).start()
    print(f"Unsensored Agent Control Plane listening on http://{args.host}:{args.port}",flush=True)
    print("Hourly pulse: local status snapshots only; no LLM calls.", flush=True)
    try: server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt: pass
    finally: server.server_close()

if __name__=="__main__": main()
