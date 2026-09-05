#!/usr/bin/env python3
import json
import os
import signal
import shutil
import socket
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Lock

SCRIPT_PATH = os.environ.get("PADM_CONTROL_SCRIPT_PATH", "")
TOKEN_FILE = os.environ.get("PADM_CONTROL_TOKEN_FILE", "")
VERSION = os.environ.get("PADM_CONTROL_VERSION", "unknown")
CAPABILITIES = ["health", "sync", "traffic"]
PORT = int(os.environ.get("PADM_CONTROL_PORT", "10086"))
MAX_BODY_SIZE = 256 * 1024
CONTROL_REQUEST_LOCK = Lock()

try:
    SCRIPT_TIMEOUT = max(0.1, float(os.environ.get("PADM_CONTROL_SCRIPT_TIMEOUT", "20") or "20"))
except ValueError:
    SCRIPT_TIMEOUT = 20
try:
    REQUEST_READ_TIMEOUT = max(0.1, float(os.environ.get("PADM_CONTROL_REQUEST_TIMEOUT", "10") or "10"))
except ValueError:
    REQUEST_READ_TIMEOUT = 10


class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(REQUEST_READ_TIMEOUT)

    def log_message(self, *_):
        return

    def respond(self, code, payload):
        data = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except OSError:
            pass

    def token(self):
        auth = self.headers.get("Authorization", "")
        return auth[7:] if auth.startswith("Bearer ") else ""

    def authorized(self):
        try:
            with open(TOKEN_FILE, encoding="utf-8") as handle:
                expected = handle.read().strip()
        except OSError:
            expected = ""
        return bool(expected) and self.token() == expected

    def endpoint(self):
        prefix = "/s/control/"
        if not self.path.startswith(prefix):
            return ""
        return self.path[len(prefix):].split("?", 1)[0]

    def parse_script_response(self, stdout, returncode):
        output = (stdout or "").strip()
        decoder = json.JSONDecoder()
        parsed = []
        for index, char in enumerate(output):
            if char != "{":
                continue
            try:
                value, _ = decoder.raw_decode(output[index:])
            except json.JSONDecodeError:
                continue
            if isinstance(value, dict):
                parsed.append(value)
        body = next((item for item in reversed(parsed) if "ok" in item), parsed[-1] if parsed else None)
        if isinstance(body, dict):
            if returncode != 0:
                body = dict(body)
                body.setdefault("exit_code", returncode)
                if body.get("ok") is not False:
                    body["ok"] = False
                    body.setdefault("error", "script_failed")
                body.setdefault("error_detail", {"type": "script_failed", "message": f"脚本退出码 {returncode}"})
            return body
        if returncode != 0:
            return {"ok": False, "error": "script_failed", "exit_code": returncode,
                    "error_detail": {"type": "script_failed", "message": f"脚本退出码 {returncode}"}}
        return {"ok": False, "error": "invalid_response",
                "error_detail": {"type": "invalid_response", "message": "脚本输出不是合法 JSON"}}

    def response_status(self, endpoint, body):
        if not isinstance(body, dict):
            return 500
        if body.get("ok") is True:
            return 200
        error = body.get("error", "")
        if error == "unauthorized":
            return 401
        if endpoint in ("sync", "traffic") and error in ("invalid_payload", "empty_payload"):
            return 400
        if endpoint == "health":
            return 503
        if error in ("script_timeout", "script_failed", "script_exec_failed", "invalid_response"):
            return 503
        return 503 if endpoint in ("sync", "traffic", "refresh") else 500

    def call_script(self, endpoint, payload=""):
        bash_bin = shutil.which("bash.exe") or shutil.which("bash") or "/bin/bash"
        if not SCRIPT_PATH:
            return {"ok": False, "error": "script_exec_failed",
                    "error_detail": {"type": "script_exec_failed", "message": "控制脚本路径未配置"}}
        env = dict(os.environ)
        env.update(PADM_CONTROL_SERVER="1", PADM_CONTROL_TOKEN=self.token(), PADM_SKIP_REMOTE_REF_CHECK="1")
        popen_options = {"start_new_session": True} if os.name == "posix" else {
            "creationflags": getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
        }
        try:
            process = subprocess.Popen(
                [bash_bin, SCRIPT_PATH, "SubscriptionControl", endpoint], stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env,
                encoding="utf-8", errors="replace", **popen_options)
            stdout, _ = process.communicate(payload, timeout=None if endpoint in ("sync", "refresh") else SCRIPT_TIMEOUT)
        except subprocess.TimeoutExpired:
            if os.name == "posix":
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
            else:
                if process.poll() is None:
                    process.terminate()
            try:
                process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                if os.name == "posix":
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                else:
                    taskkill = shutil.which("taskkill.exe") or shutil.which("taskkill")
                    if taskkill:
                        subprocess.run([taskkill, "/PID", str(process.pid), "/T", "/F"],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
                    if process.poll() is None:
                        process.kill()
                process.communicate()
            return {"ok": False, "error": "script_timeout",
                    "error_detail": {"type": "script_timeout", "message": "脚本执行超时"}}
        except OSError:
            return {"ok": False, "error": "script_exec_failed",
                    "error_detail": {"type": "script_exec_failed", "message": "脚本无法执行"}}
        return self.parse_script_response(stdout, process.returncode)

    def read_body(self, length):
        deadline = time.monotonic() + REQUEST_READ_TIMEOUT
        chunks = []
        while length > 0:
            timeout = deadline - time.monotonic()
            if timeout <= 0:
                raise TimeoutError
            self.connection.settimeout(timeout)
            chunk = self.rfile.read(min(65536, length))
            if not chunk:
                raise ValueError
            chunks.append(chunk)
            length -= len(chunk)
        return b"".join(chunks)

    def do_GET(self):
        endpoint = self.endpoint()
        if endpoint != "health":
            self.respond(404, {"ok": False, "error": "not_found"})
            return
        if not self.authorized():
            self.respond(401, {"ok": False, "error": "unauthorized",
                               "error_detail": {"type": "unauthorized", "message": "控制 token 验证失败"}})
            return
        self.respond(200, {"ok": True, "version": VERSION, "capabilities": CAPABILITIES})

    def do_POST(self):
        endpoint = self.endpoint()
        if endpoint not in ("sync", "traffic", "refresh"):
            self.respond(404, {"ok": False, "error": "not_found"})
            return
        if endpoint != "refresh" and not self.authorized():
            self.respond(401, {"ok": False, "error": "unauthorized",
                               "error_detail": {"type": "unauthorized", "message": "控制 token 验证失败"}})
            return
        try:
            length = int(self.headers.get("Content-Length", "0") or "0")
        except ValueError:
            self.respond(400, {"ok": False, "error": "invalid_payload",
                               "error_detail": {"type": "invalid_payload", "message": "Content-Length 无效"}})
            return
        if length < 0:
            self.respond(400, {"ok": False, "error": "invalid_payload"})
            return
        if length > MAX_BODY_SIZE:
            self.respond(413, {"ok": False, "error": "payload_too_large"})
            return
        try:
            payload = self.read_body(length).decode("utf-8", errors="replace") if length else ""
        except (socket.timeout, TimeoutError):
            self.respond(408, {"ok": False, "error": "request_timeout",
                               "error_detail": {"type": "request_timeout", "message": "请求体读取超时"}})
            return
        except ValueError:
            self.respond(400, {"ok": False, "error": "invalid_payload",
                               "error_detail": {"type": "invalid_payload", "message": "请求体不完整"}})
            return
        if not CONTROL_REQUEST_LOCK.acquire(blocking=False):
            self.respond(503, {"ok": False, "error": "busy",
                               "error_detail": {"type": "busy", "message": "控制服务正在处理其他变更请求"}})
            return
        try:
            body = self.call_script(endpoint, payload)
        finally:
            CONTROL_REQUEST_LOCK.release()
        self.respond(self.response_status(endpoint, body), body)


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
