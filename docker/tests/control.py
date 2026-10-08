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

from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("padm_control_api", ROOT / "docker/images/ops/control_api.py")
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)
schema = json.loads((ROOT / "docker/contracts/control.schema.json").read_text())
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema, format_checker=FormatChecker())
TOKEN = "a" * 48
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
for address in ("0.0.0.0", "127.0.0.1", "8.8.8.8", "169.254.1.1", "100.64.0.1", "::1", "10.077.0.1"):
    state = copy.deepcopy(STATE)
    state["listen"]["address"] = address
    rejected(api.validate_state, state)
state = copy.deepcopy(STATE)
state["accounts"] *= 2
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
    os.chown(state_path, 10001, 10001)
    rejected(api.read_state, state_path)
    publish(STATE)

    class TestHandler(api.ControlHandler):
        # 网络仅走工具容器回环；模拟私网源地址，不冒充真实 WireGuard 连通。
        peer_address = STATE["peer"]["address"]

        def setup(self):
            super().setup()
            self.client_address = (self.peer_address, self.client_address[1])

        def log_message(self, *_):
            pass

    server = api.ControlServer(("127.0.0.1", 0), TestHandler)
    server.state_path = state_path
    server.listen = STATE["listen"]
    thread = threading.Thread(target=server.serve_forever)
    thread.start()

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
        publish(STATE)
        assert request()[0] == 200
        state = copy.deepcopy(STATE)
        state["listen"]["port"] += 1
        publish(state)
        assert request()[0] == 503, "监听状态变更必须重启服务，不沿用旧地址"
        publish(STATE)
        state_path.write_text('{"invalid":true}')
        assert request()[0] == 503
        publish(STATE)
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

print("docker-control-api-regression-ok")
