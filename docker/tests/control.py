#!/usr/bin/env python3
import copy
import hashlib
import http.client
import importlib.util
import json
import os
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from unittest.mock import patch

from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("padm_control_api", ROOT / "docker/images/ops/control_api.py")
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)
schema = json.loads((ROOT / "docker/contracts/control.schema.json").read_text())
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema, format_checker=FormatChecker())
TOKEN = "a" * 48
ENTRYPOINT = ROOT / "docker/images/ops/entrypoint.sh"
subprocess.run(["sh", "-n", str(ENTRYPOINT)], check=True)
for arguments in ([], ["--check", "/state.json"], ["--state"],
                  ["--state", "/state.json", "--check"]):
    checked = subprocess.run(["sh", str(ENTRYPOINT), "control-health", *arguments],
                             capture_output=True, timeout=3)
    assert checked.returncode == 64 and not checked.stdout
    assert checked.stderr == b"usage: control-health --state PATH\n"
STATE = {
    "schema_version": 1, "role": "main",
    "node_id": "11111111-1111-4111-8111-111111111111", "revision": 7,
    "listen": {"interface": "wg-padm", "address": "10.77.0.1", "port": 39778},
    "peer": {"id": "22222222-2222-4222-8222-222222222222", "address": "10.77.0.2",
             "enabled": True, "expires_at": int(time.time()) + 3600,
             "token_sha256": hashlib.sha256(TOKEN.encode()).hexdigest()},
    "accounts": [{"id": "33333333-3333-4333-8333-333333333333", "name": "共享账号",
                  "enabled": True, "uuid": "44444444-4444-4444-8444-444444444444",
                  "password": "b" * 48, "shadowsocks_password": None}],
}


def rejected(function, *args):
    try:
        function(*args)
    except (ValueError, OSError):
        return
    raise AssertionError("应拒绝不安全控制输入")


validator.validate(STATE)
api.validate_state(STATE)
for field, value in (("role", "controlled"), ("revision", True), ("schema_version", 2), ("accounts", {})):
    state = copy.deepcopy(STATE)
    state[field] = value
    rejected(api.validate_state, state)
for address in ("0.0.0.0", "127.0.0.1", "8.8.8.8", "169.254.1.1", "100.64.0.1",
                "::1", "fd00::1", "::ffff:10.77.0.1", "10.077.0.1"):
    state = copy.deepcopy(STATE)
    state["listen"]["address"] = address
    rejected(api.validate_state, state)
state = copy.deepcopy(STATE)
state["accounts"] *= 2
rejected(api.validate_state, state)
state = copy.deepcopy(STATE)
other = copy.deepcopy(state["accounts"][0])
other.update(id=state["accounts"][0]["uuid"], uuid="66666666-6666-4666-8666-666666666666",
             password="c" * 48)
state["accounts"].append(other)
rejected(api.validate_state, state)
state = copy.deepcopy(STATE)
state["accounts"][0]["password"] = "Compatible.-~@+=:Password"
state["accounts"][0]["uuid"] = state["accounts"][0]["id"]
validator.validate(state)
api.validate_state(state)
for field in ("password", "shadowsocks_password"):
    state = copy.deepcopy(STATE)
    state["accounts"][0]["shadowsocks_password"] = "AQEBAQEBAQEBAQEBAQEBAQ=="
    other = copy.deepcopy(state["accounts"][0])
    other.update(id="55555555-5555-4555-8555-555555555555", uuid="66666666-6666-4666-8666-666666666666",
                 password="c" * 48, shadowsocks_password="AgICAgICAgICAgICAgICAg==")
    other[field] = state["accounts"][0][field]
    state["accounts"].append(other)
    rejected(api.validate_state, state)
rejected(api.strict_object, [("role", "main"), ("role", "main")])
for section, field in (("peer", "token_sha256"), ("accounts", "id"), ("accounts", "name"), ("accounts", "password")):
    state = copy.deepcopy(STATE)
    target = state[section][0] if section == "accounts" else state[section]
    target[field] += "\n"
    assert not validator.is_valid(state), "合同不得接受末尾换行"
    rejected(api.validate_state, state)

assert os.getuid() == 0, "控制文件权限回归必须使用 Linux root"
# /tmp 可写、CI checkout 非 root 所有；状态夹具使用安全的 Linux 系统目录。
with tempfile.TemporaryDirectory(prefix=".tmp-control-", dir="/var/lib") as directory:
    state_path = Path(directory) / "control.json"

    def publish(state):
        stage = state_path.with_suffix(".new")
        stage.write_text(json.dumps(state))
        stage.chmod(0o640)
        stage.replace(state_path)

    publish(STATE)
    assert api.read_state(state_path) == STATE
    assert stat.S_IMODE(state_path.stat().st_mode) == 0o640
    for mode in (0o644, 0o740, 0o650, 0o4640):
        state_path.chmod(mode)
        rejected(api.read_state, state_path)
    publish(STATE)
    link = Path(directory) / "symlink.json"
    link.symlink_to(state_path)
    rejected(api.read_state, link)
    rejected(api.read_state, "relative.json")
    fifo = Path(directory) / "fifo.json"
    os.mkfifo(fifo, 0o600)
    rejected(api.read_state, fifo)
    Path(directory).chmod(0o770)
    rejected(api.read_state, state_path)
    Path(directory).chmod(0o700)
    state_path.write_text('{"role":"main","role":"main"}')
    rejected(api.read_state, state_path)
    state_path.write_bytes(b" " * (api.MAX_STATE_BYTES + 1))
    rejected(api.read_state, state_path)
    state_path.write_bytes(b"[" * 1100 + b"0" + b"]" * 1100)
    rejected(api.read_state, state_path)
    publish(STATE)
    Path(directory).chmod(0o750)
    os.chown(directory, 0, 10001)
    os.chown(state_path, 0, 10001)

    def runtime_user():
        os.setgroups([])
        os.setgid(10001)
        os.setuid(10001)

    checked = subprocess.run(
        [sys.executable, str(ROOT / "docker/images/ops/control_api.py"), "--state", str(state_path), "--check"],
        preexec_fn=runtime_user, capture_output=True, timeout=3,
    )
    assert checked.returncode == 0 and checked.stdout == checked.stderr == b"", "默认容器用户应能只读检查状态"
    failed_health = subprocess.run(
        [sys.executable, str(ROOT / "docker/images/ops/control_api.py"), "--state", str(state_path), "--health"],
        preexec_fn=runtime_user, capture_output=True, timeout=6,
    )
    assert failed_health.returncode == 1 and not failed_health.stdout
    assert failed_health.stderr.decode() == "控制服务健康检查失败\n", "无实际接口时健康应失败且不泄露状态"
    os.chown(state_path, 10001, 10001)
    rejected(api.read_state, state_path)
    publish(STATE)

    class TestHandler(api.ControlHandler):
        # 网络仅走工具容器回环；模拟私网源地址，不冒充真实 WireGuard 连通。
        peer_address = STATE["peer"]["address"]
        health_status = None
        health_body = b'{"ok":false,"error":"unauthorized"}'
        health_delay = 0
        health_encoding = None

        def setup(self):
            super().setup()
            self.client_address = (self.peer_address, self.client_address[1])

        def log_message(self, *_):
            pass

        def do_GET(self):
            if self.health_status is None:
                super().do_GET()
                return
            assert not self.headers.get_all("Authorization"), "健康探测不得携带凭据"
            self.send_response(self.health_status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(self.health_body)))
            if self.health_encoding:
                self.send_header("Transfer-Encoding", self.health_encoding)
            self.end_headers()
            for offset in range(0, len(self.health_body), 1 if self.health_delay else len(self.health_body)):
                if self.health_delay:
                    time.sleep(self.health_delay)
                self.wfile.write(self.health_body[offset:offset + (1 if self.health_delay else len(self.health_body))])
                self.wfile.flush()

    server = api.ControlServer(("127.0.0.1", 0), TestHandler)
    server.state_path = state_path
    server.listen = STATE["listen"]
    thread = threading.Thread(target=server.serve_forever)
    thread.start()
    http_connection = http.client.HTTPConnection

    def local_health_connection(address, port, timeout):
        assert (address, port) == (STATE["listen"]["address"], STATE["listen"]["port"])
        assert 0 < timeout <= 2, "健康连接必须有界"
        return http_connection(*server.server_address, timeout=timeout)

    def health():
        # 私网地址只路由到容器回环；接口结果模拟，不替换服务的鉴权或状态读取。
        with patch.object(api.fcntl, "ioctl", return_value=b"\0" * 20 + socket.inet_aton(STATE["listen"]["address"])), \
                patch.object(api.http.client, "HTTPConnection", side_effect=local_health_connection):
            api.health_check(api.read_state(state_path))

    def request(path="/v1/health", token=TOKEN, version="1", method="GET", authorization=None):
        connection = http.client.HTTPConnection(*server.server_address, timeout=3)
        connection.request(method, path, headers={
            "Authorization": f"Bearer {token}" if authorization is None else authorization,
            "X-Padm-Control-Version": version,
        })
        response = connection.getresponse()
        status, content = response.status, response.read()
        connection.close()
        return status, content

    try:
        status, body = request()
        assert status == 200 and json.loads(body)["capabilities"] == ["health", "desired"]
        health()
        os.chown(state_path, 0, 10001)
        checked_health = subprocess.run(
            [sys.executable, "-c", """
import importlib.util, socket, sys
spec = importlib.util.spec_from_file_location("control_health_test", sys.argv[1])
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)
connection = api.http.client.HTTPConnection
port = int(sys.argv[3])
api.fcntl.ioctl = lambda *_: b"\\0" * 20 + socket.inet_aton("10.77.0.1")
api.http.client.HTTPConnection = lambda _address, _port, timeout: connection("127.0.0.1", port, timeout=timeout)
sys.argv = [sys.argv[1], "--state", sys.argv[2], "--health"]
api.main()
""", str(ROOT / "docker/images/ops/control_api.py"), str(state_path), str(server.server_address[1])],
            preexec_fn=runtime_user, capture_output=True, timeout=6,
        )
        assert checked_health.returncode == 0 and checked_health.stdout == checked_health.stderr == b"", \
            "默认容器用户应能检查真实服务；仅接口与私网路由由回环模拟"
        with patch.object(api.fcntl, "ioctl", return_value=b"\0" * 20 + socket.inet_aton("10.77.0.3")):
            rejected(api.health_check, STATE)
        assert TOKEN.encode() not in body and STATE["accounts"][0]["password"].encode() not in body
        assert "token_sha256" not in body.decode()
        status, body = request("/v1/desired")
        assert status == 200 and json.loads(body)["accounts"] == STATE["accounts"]
        assert json.loads(body)["revision"] == 7
        assert request(token="wrong")[0] == 401
        for authorization in (TOKEN, f"Basic {TOKEN}", f"bearer {TOKEN}", f"Bearer  {TOKEN}"):
            assert request(authorization=authorization)[0] == 401
        for header, value, expected in (("Authorization", f"Bearer {TOKEN}", 401),
                                        ("X-Padm-Control-Version", "1", 409)):
            connection = http.client.HTTPConnection(*server.server_address, timeout=3)
            connection.putrequest("GET", "/v1/health")
            connection.putheader("Authorization", f"Bearer {TOKEN}")
            connection.putheader("X-Padm-Control-Version", "1")
            connection.putheader(header, value)
            connection.endheaders()
            response = connection.getresponse()
            assert response.status == expected, "重复安全请求头必须拒绝"
            response.read()
            connection.close()
        assert request(version="2")[0] == 409
        assert request("/v1/desired?token=secret")[0] == 404
        assert request(method="POST")[0] == 501
        malformed = socket.create_connection(server.server_address, timeout=2)
        malformed.sendall(b"GET /" + TOKEN.encode() + b" BROKEN\r\n\r\n")
        chunks = []
        while chunk := malformed.recv(4096):
            chunks.append(chunk)
        malformed.close()
        assert TOKEN.encode() not in b"".join(chunks), "畸形请求不得回显秘密"
        TestHandler.peer_address = "10.77.0.3"
        assert request()[0] == 401
        TestHandler.peer_address = STATE["peer"]["address"]
        for mutation in ("disabled", "expired", "rotated"):
            state = copy.deepcopy(STATE)
            if mutation == "disabled":
                state["peer"]["enabled"] = False
            elif mutation == "expired":
                state["peer"]["expires_at"] = int(time.time()) - 1
            else:
                state["peer"]["token_sha256"] = "0" * 64
            publish(state)
            assert request()[0] == 401, "授权变更必须立即生效，不缓存旧凭据"
            health()
        publish(STATE)
        assert request()[0] == 200
        state = copy.deepcopy(STATE)
        state["listen"]["port"] += 1
        publish(state)
        assert request()[0] == 503, "监听状态变更必须重启服务，不沿用旧地址"
        with patch.object(api.fcntl, "ioctl", return_value=b"\0" * 20 + socket.inet_aton(state["listen"]["address"])), \
                patch.object(api.http.client, "HTTPConnection",
                             side_effect=lambda *_args, **kwargs: http_connection(*server.server_address, **kwargs)):
            rejected(api.health_check, api.read_state(state_path))
        publish(STATE)
        state_path.write_text('{"invalid":true}')
        assert request()[0] == 503
        rejected(health)
        publish(STATE)
        expected_body = TestHandler.health_body
        for status, body, encoding in (
                (200, expected_body, None), (302, expected_body, None), (401, b'{"ok":true}', None),
                (401, b"x" * (api.MAX_HEALTH_BYTES + 1), None), (401, expected_body, "chunked")):
            TestHandler.health_status, TestHandler.health_body, TestHandler.health_encoding = status, body, encoding
            rejected(health)
        TestHandler.health_status, TestHandler.health_body, TestHandler.health_encoding = 401, expected_body, None
        health()
        TestHandler.health_delay = 0.04
        with patch.object(api, "HEALTH_TIMEOUT", 0.2):
            before = time.monotonic()
            rejected(health)
            assert time.monotonic() - before < 1, "持续慢速健康响应也必须按总时限终止"
        TestHandler.health_status, TestHandler.health_delay = None, 0
        server.request_timeout = 0.2
        for slow in (False, True):
            blocked = socket.create_connection(server.server_address, timeout=2)
            started = threading.Event()

            def occupy():
                try:
                    blocked.sendall(b"G")
                    started.set()
                    if slow:
                        for _ in range(20):
                            time.sleep(0.04)
                            blocked.sendall(b"E")
                except OSError:
                    pass

            sender = threading.Thread(target=occupy)
            sender.start()
            assert started.wait(timeout=2)
            before = time.monotonic()
            assert request()[0] == 200
            assert time.monotonic() - before < 1.5, "慢速或空请求不得无限占住服务"
            blocked.close()
            sender.join(timeout=2)
            assert not sender.is_alive()
    finally:
        server.shutdown()
        thread.join(timeout=3)
        server.server_close()
        assert not thread.is_alive()
    rejected(health)

print("docker-control-api-regression-ok")
