#!/usr/bin/env python3
import subprocess, threading, json, signal, sys, time, socket, re
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

POMO = sys.argv[1] if len(sys.argv) > 1 else "waybar-module-pomodoro"
PORT = 9421

_state = {"text": "--:--", "class": "idle"}
_lock  = threading.Lock()


def _stream():
    while True:
        try:
            proc = subprocess.Popen(
                [POMO], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            )
            for raw in proc.stdout:
                line = raw.decode().strip()
                if not line:
                    continue
                try:
                    data = json.loads(line)
                    with _lock:
                        _state.update(data)
                except (ValueError, TypeError):
                    pass
            proc.wait()
        except Exception:
            time.sleep(2)


threading.Thread(target=_stream, daemon=True).start()


def ping_host(host):
    """ICMP ping with TCP-connect fallback. Returns {up, latency}."""
    # Try ICMP first — works even if the host runs no TCP services
    try:
        result = subprocess.run(
            ["ping", "-c", "1", "-W", "2", host],
            capture_output=True, timeout=4,
        )
        if result.returncode == 0:
            m = re.search(r"time=(\d+\.?\d*)", result.stdout.decode())
            lat = int(float(m.group(1))) if m else 1
            return {"up": True, "latency": lat}
    except Exception:
        pass

    # TCP fallback — connection refused still means the host is up
    for port in [80, 443, 22, 25565]:
        t0 = time.monotonic()
        try:
            socket.create_connection((host, port), timeout=2).close()
            lat = int((time.monotonic() - t0) * 1000)
            return {"up": True, "latency": lat}
        except ConnectionRefusedError:
            lat = int((time.monotonic() - t0) * 1000)
            return {"up": True, "latency": lat}
        except Exception:
            continue

    return {"up": False, "latency": 0}


class Handler(BaseHTTPRequestHandler):
    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path == "/state":
            with _lock:
                body = json.dumps(_state).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self._cors()
            self.end_headers()
            self.wfile.write(body)

        elif parsed.path == "/ping":
            host = parse_qs(parsed.query).get("host", [""])[0].strip()
            if not host:
                self.send_response(400); self._cors(); self.end_headers(); return
            result = ping_host(host)
            body = json.dumps(result).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self._cors()
            self.end_headers()
            self.wfile.write(body)

        else:
            self.send_response(404)
            self._cors()
            self.end_headers()

    def do_POST(self):
        cmds = {"/toggle": "toggle", "/reset": "reset"}
        arg  = cmds.get(self.path)
        if arg:
            subprocess.run([POMO, arg], capture_output=True)
            self.send_response(200)
        else:
            self.send_response(404)
        self._cors()
        self.end_headers()

    def log_message(self, *_):
        pass


signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
print(f"pomo-bridge on 127.0.0.1:{PORT}", flush=True)
HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
