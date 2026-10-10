#!/usr/bin/env python3
import copy
import hashlib
import http.client
import importlib.util
import json
import os
import re
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime
from http import HTTPStatus
from pathlib import Path
from unittest.mock import Mock, patch

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


def log_failed(function, *args):
    with patch.object(api, "print", create=True) as output:
        try:
            function(*args)
        except SystemExit as error:
            assert error.code == 78, "日志失败必须退出服务，不能交给 socketserver 吞掉"
        else:
            raise AssertionError("日志失败后不应继续服务")
        output.assert_called_once_with("控制访问日志写入失败，服务已停止", file=sys.stderr, flush=True)


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

    log_directory = Path(directory) / "logs"
    log_directory.mkdir(mode=0o750)
    os.chown(log_directory, 0, 10001)
    access_path = log_directory / "auth.log"
    access_path.write_bytes(b"existing\n")
    os.chown(access_path, 10001, 10001)
    access_path.chmod(0o640)
    descriptor = api.open_access_log(access_path)
    try:
        flags = api.fcntl.fcntl(descriptor, api.fcntl.F_GETFL)
        assert flags & os.O_APPEND and flags & os.O_NONBLOCK
        assert api.fcntl.fcntl(descriptor, api.fcntl.F_GETFD) & api.fcntl.FD_CLOEXEC
    finally:
        os.close(descriptor)
    assert access_path.read_bytes() == b"existing\n", "安全打开不能截断已有证据"
    for mode in (0o600, 0o644, 0o660, 0o4640):
        access_path.chmod(mode)
        rejected(api.open_access_log, access_path)
    access_path.chmod(0o640)
    for uid, gid in ((0, 10001), (10001, 0)):
        os.chown(access_path, uid, gid)
        rejected(api.open_access_log, access_path)
    os.chown(access_path, 10001, 10001)
    for uid, gid, mode in ((10001, 10001, 0o750), (0, 0, 0o750), (0, 10001, 0o770),
                           (0, 10001, 0o755)):
        os.chown(log_directory, uid, gid)
        log_directory.chmod(mode)
        rejected(api.open_access_log, access_path)
    os.chown(log_directory, 0, 10001)
    log_directory.chmod(0o750)
    Path(directory).chmod(0o770)
    rejected(api.open_access_log, access_path)
    Path(directory).chmod(0o750)
    log_link = log_directory / "linked.log"
    log_link.symlink_to(access_path)
    rejected(api.open_access_log, log_link)
    directory_link = Path(directory) / "linked-logs"
    directory_link.symlink_to(log_directory, target_is_directory=True)
    rejected(api.open_access_log, directory_link / "auth.log")
    hard_link = log_directory / "hard.log"
    os.link(access_path, hard_link)
    rejected(api.open_access_log, access_path)
    hard_link.unlink()
    log_fifo = log_directory / "fifo.log"
    os.mkfifo(log_fifo, 0o640)
    rejected(api.open_access_log, log_fifo)
    rejected(api.open_access_log, log_directory)
    rejected(api.open_access_log, "relative.log")
    missing_log = log_directory / (TOKEN + ".log")
    rejected(api.open_access_log, missing_log)
    assert not missing_log.exists(), "API 不能自行创建缺失日志"
    with patch.object(sys, "argv", [str(ROOT / "docker/images/ops/control_api.py"),
                                   "--state", str(state_path), "--access-log", str(missing_log)]), \
            patch.object(api, "require_wireguard_address", side_effect=AssertionError("日志校验必须早于监听")):
        log_failed(api.main)

    challenge_directory = Path(directory) / "control-source"
    challenge_directory.mkdir(mode=0o750)
    os.chown(challenge_directory, 0, 10001)
    challenge_path = challenge_directory / "challenge.json"
    receipt_path = log_directory / "source.receipt"
    receipt_path.write_bytes(b"")
    os.chown(receipt_path, 10001, 10001)
    receipt_path.chmod(0o640)
    nonce = "c" * 64
    challenge = {
        "schema_version": 1, "nonce": nonce, "expires_at": int(time.time()) + 20,
        "expected_source": STATE["peer"]["address"], "target": STATE["listen"]["address"],
        "port": STATE["listen"]["port"],
    }

    def register_challenge(value):
        challenge_path.write_text(json.dumps(value))
        challenge_path.chmod(0o640)
        os.chown(challenge_path, 0, 10001)

    assert api.read_source_challenge(challenge_path) is None
    register_challenge(challenge)
    assert api.read_source_challenge(challenge_path) == challenge
    for field, value in (("schema_version", True), ("schema_version", 2), ("nonce", "d" * 63),
                         ("nonce", "D" * 64), ("expires_at", True), ("expires_at", int(time.time()) + 60),
                         ("expected_source", STATE["listen"]["address"]), ("expected_source", "127.0.0.1"),
                         ("target", "10.077.0.1"), ("port", True), ("port", 1023), ("port", 65536)):
        register_challenge(dict(challenge, **{field: value}))
        rejected(api.read_source_challenge, challenge_path)
    register_challenge(dict(challenge, expires_at=int(time.time()) - 1))
    assert api.read_source_challenge(challenge_path) is None
    register_challenge(dict(challenge, extra=TOKEN))
    rejected(api.read_source_challenge, challenge_path)
    register_challenge(challenge)
    challenge_path.write_text(json.dumps(challenge)[:-1] + ',"nonce":"' + TOKEN + '"}')
    rejected(api.read_source_challenge, challenge_path)
    challenge_path.write_bytes(b"[" * 1100 + b"0" + b"]" * 1100)
    rejected(api.read_source_challenge, challenge_path)
    challenge_path.write_bytes(b" " * 4097)
    rejected(api.read_source_challenge, challenge_path)
    register_challenge(challenge)
    for mode in (0o600, 0o644, 0o660):
        challenge_path.chmod(mode)
        rejected(api.read_source_challenge, challenge_path)
    register_challenge(challenge)
    for uid, gid in ((10001, 10001), (0, 0)):
        os.chown(challenge_path, uid, gid)
        rejected(api.read_source_challenge, challenge_path)
    register_challenge(challenge)
    challenge_link = challenge_directory / "linked.json"
    challenge_link.symlink_to(challenge_path)
    rejected(api.read_source_challenge, challenge_link)
    challenge_hardlink = challenge_directory / "hard.json"
    os.link(challenge_path, challenge_hardlink)
    rejected(api.read_source_challenge, challenge_path)
    challenge_hardlink.unlink()
    challenge_directory.chmod(0o770)
    rejected(api.read_source_challenge, challenge_path)
    challenge_directory.chmod(0o750)
    challenge_arguments = [str(ROOT / "docker/images/ops/control_api.py"),
                           "--state", str(state_path), "--access-log", str(access_path),
                           "--source-challenge", str(challenge_path), "--source-receipt", str(receipt_path)]
    challenge_path.chmod(0o600)
    with patch.object(sys, "argv", challenge_arguments), \
            patch.object(api, "require_wireguard_address", side_effect=AssertionError("登记校验必须早于监听")):
        log_failed(api.main)
    register_challenge(challenge)
    receipt_path.chmod(0o600)
    with patch.object(sys, "argv", challenge_arguments), \
            patch.object(api, "require_wireguard_address", side_effect=AssertionError("回执校验必须早于监听")):
        log_failed(api.main)
    receipt_path.chmod(0o640)

    def challenge_request(*, path="/v1/health", headers=None, endpoints=None):
        from email.message import Message
        # 这里只核对登记和响应顺序，私网三元组为夹具，不冒充真实 WireGuard。
        handler = api.ControlHandler.__new__(api.ControlHandler)
        handler.server = Mock(source_challenge=challenge_path, source_receipt=receipt_path, access_log=access_path)
        handler.path = path
        handler.headers = Message()
        for key, value in (headers if headers is not None else [("X-Padm-Source-Challenge", nonce)]):
            handler.headers[key] = value
        handler.log_endpoints = endpoints or (
            STATE["peer"]["address"], STATE["listen"]["address"], STATE["listen"]["port"])
        return handler

    handler = challenge_request()
    assert handler.source_challenge(STATE) == challenge
    for headers in ([], [("X-Padm-Source-Challenge", "d" * 64)],
                    [("X-Padm-Source-Challenge", TOKEN)], [("X-Unregistered-Challenge", nonce)],
                    [("X-Padm-Source-Challenge", nonce), ("X-Padm-Source-Challenge", nonce)],
                    [("X-Padm-Source-Challenge", nonce), ("Authorization", "")],
                    [("X-Padm-Source-Challenge", nonce), ("Authorization", "Bearer " + TOKEN)]):
        assert challenge_request(headers=headers).source_challenge(STATE) is None
    assert challenge_request(path="/v1/health?nonce=" + nonce).source_challenge(STATE) is None
    assert challenge_request(endpoints=("10.77.0.3", "10.77.0.1", STATE["listen"]["port"])).source_challenge(STATE) is None
    register_challenge(dict(challenge, expected_source="10.77.0.3"))
    assert handler.source_challenge(STATE) is None
    register_challenge(dict(challenge, expires_at=int(time.time()) - 1))
    assert handler.source_challenge(STATE) is None
    challenge_path.unlink()
    assert handler.source_challenge(STATE) is None
    register_challenge(challenge)
    challenge_path.chmod(0o600)
    log_failed(handler.source_challenge, STATE)
    register_challenge(challenge)

    handler.request_version = "HTTP/1.1"
    handler.wfile = Mock()
    original_auth = access_path.read_bytes()
    with patch.object(api, "print", create=True) as output, \
            patch.object(api, "append_access_line", wraps=api.append_access_line) as appended:
        handler.reply(401, {"ok": False, "error": "unauthorized"}, handler.source_challenge(STATE))
        assert appended.call_count == 2
        assert appended.call_args_list[0].args[0] == access_path
        assert appended.call_args_list[1].args[0] == receipt_path
        output.assert_called_once()
        assert nonce not in output.call_args.args[0], "nonce 只能进入独立 receipt，不能进入 stdout"
    assert access_path.read_bytes() == original_auth + (output.call_args.args[0] + "\n").encode("ascii")
    expected_receipt = (
        r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z "
        rf"control-source nonce={nonce} status=401 source=10\.77\.0\.2 target=10\.77\.0\.1 "
        rf"port={STATE['listen']['port']}\n"
    )
    assert re.fullmatch(expected_receipt, receipt_path.read_text()) is not None
    original_receipt = receipt_path.read_bytes()
    receipt_path.chmod(0o600)
    handler.wfile = Mock()
    with patch.object(api, "print", create=True) as output:
        try:
            handler.reply(401, {"ok": False, "error": "unauthorized"}, challenge)
        except SystemExit as error:
            assert error.code == 78
        else:
            raise AssertionError("receipt 权限错误必须停止响应")
        assert output.call_count == 2
        output.assert_called_with("控制访问日志写入失败，服务已停止", file=sys.stderr, flush=True)
    handler.wfile.write.assert_not_called()
    assert receipt_path.read_bytes() == original_receipt
    receipt_path.chmod(0o640)
    handler.wfile = Mock()
    with patch.object(api.os, "fsync", side_effect=[None, OSError(TOKEN)]), \
            patch.object(api, "print", create=True) as output:
        try:
            handler.reply(401, {"ok": False, "error": "unauthorized"}, challenge)
        except SystemExit as error:
            assert error.code == 78
        else:
            raise AssertionError("receipt 同步失败必须停止响应")
        output.assert_called_with("控制访问日志写入失败，服务已停止", file=sys.stderr, flush=True)
    handler.wfile.write.assert_not_called()
    receipt_path.write_bytes(b"")
    challenge_path.unlink()

    def runtime_user():
        os.setgroups([])
        os.setgid(10001)
        os.setuid(10001)

    checked = subprocess.run(
        [sys.executable, str(ROOT / "docker/images/ops/control_api.py"), "--state", str(state_path), "--check"],
        preexec_fn=runtime_user, capture_output=True, timeout=3,
    )
    assert checked.returncode == 0 and checked.stdout == checked.stderr == b"", "默认容器用户应能只读检查状态"
    checked = subprocess.run(
        [sys.executable, str(ROOT / "docker/images/ops/control_api.py"), "--state", str(state_path),
         "--access-log", str(missing_log), "--check"],
        preexec_fn=runtime_user, capture_output=True, timeout=3,
    )
    assert checked.returncode == 0 and checked.stdout == checked.stderr == b"", "--check 不访问持久日志"
    checked = subprocess.run(
        [sys.executable, str(ROOT / "docker/images/ops/control_api.py"), "--state", str(state_path),
         "--access-log", str(missing_log), "--source-challenge", str(challenge_path),
         "--source-receipt", str(missing_log), "--check"],
        preexec_fn=runtime_user, capture_output=True, timeout=3,
    )
    assert checked.returncode == 0 and checked.stdout == checked.stderr == b"", "--check 不读取登记或回执"
    for arguments in (["--source-challenge", str(challenge_path)],
                      ["--source-receipt", str(receipt_path)],
                      ["--source-challenge", str(challenge_path), "--source-receipt", str(receipt_path)]):
        checked = subprocess.run(
            [sys.executable, str(ROOT / "docker/images/ops/control_api.py"), "--state", str(state_path),
             "--check", *arguments], preexec_fn=runtime_user, capture_output=True, timeout=3,
        )
        assert checked.returncode == 2 and not checked.stdout, "挑战参数必须成对并启用访问日志"
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

    with patch.object(api.socket, "getfqdn", side_effect=AssertionError("控制服务不应查询反向 DNS")):
        server = api.ControlServer(("127.0.0.1", 0), TestHandler)
    server.state_path = state_path
    server.listen = STATE["listen"]
    request_logs = []

    def capture_log(message, *, flush):
        assert flush
        request_logs.append(message)

    log_sink = patch.object(api, "print", capture_log, create=True)
    log_sink.start()
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

    def request(path="/v1/health", token=TOKEN, version="1", method="GET", authorization=None, extra_headers=None):
        connection = http.client.HTTPConnection(*server.server_address, timeout=3)
        headers = {
            "Authorization": f"Bearer {token}" if authorization is None else authorization,
            "X-Padm-Control-Version": version,
        }
        headers.update(extra_headers or {})
        connection.request(method, path, headers=headers)
        response = connection.getresponse()
        status, content = response.status, response.read()
        connection.close()
        return status, content

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen(1)
            with socket.create_connection(listener.getsockname(), timeout=2) as client:
                connected, _ = listener.accept()
                with connected:
                    handler = api.ControlHandler.__new__(api.ControlHandler)
                    handler.connection = connected
                    handler.server = server
                    handler.log_endpoints = api.request_log_tuple(connected)
                    before = len(request_logs)
                    for code in (True, False, "200", TOKEN, 99, 600, None):
                        handler.log_request(code, TOKEN)
                    handler.log_message(TOKEN, f"GET /{TOKEN}", 401)
                    assert len(request_logs) == before, "不可信状态和 HTTP 格式实参不得进入日志"
                    handler.log_request(HTTPStatus.UNAUTHORIZED, TOKEN)
                    assert len(request_logs) == before + 1
                    assert request_logs[-1].endswith(
                        f"status=401 source=127.0.0.1 target=127.0.0.1 port={listener.getsockname()[1]}"
                    ), "标准 HTTPStatus 必须记录真实 socket 来源与目标"
                    request_logs.pop()
                    handler.log_error(TOKEN, f"GET /{TOKEN}", 401)
                    assert len(request_logs) == before, "任意 HTTP 错误格式实参不能伪造关闭事件"
                    handler.log_error(TOKEN, TimeoutError(TOKEN))
                    assert len(request_logs) == before + 1
                    assert request_logs[-1].endswith(
                        f"status=connection_closed source=127.0.0.1 target=127.0.0.1 "
                        f"port={listener.getsockname()[1]}"
                    ), "HTTP 超时只能触发固定关闭事件，不得回显格式或异常原文"
                    request_logs.pop()
                    connected.close()
                    handler.log_request(HTTPStatus.UNAUTHORIZED, TOKEN)
                    assert len(request_logs) == before + 1
                    assert request_logs[-1].endswith(
                        f"status=401 source=127.0.0.1 target=127.0.0.1 port={listener.getsockname()[1]}"
                    ), "连接关闭后仍须保留已接受 socket 的真实鉴权失败来源"
                    request_logs.pop()
        for method, endpoint in (
                ("getpeername", ("::ffff:127.0.0.1", 1)),
                ("getpeername", ("127.000.0.1", 1)),
                ("getpeername", ("127.0.0.1\n" + TOKEN, 1)),
                ("getsockname", ("127.0.0.1", 0)),
                ("getsockname", ("127.0.0.1", True)),
                ("getsockname", ("127.0.0.1", "80")),
                ("getsockname", ("127.0.0.1", 80, 0, 0))):
            connection = Mock()
            connection.getpeername.return_value = ("127.0.0.1", 1)
            connection.getsockname.return_value = ("127.0.0.1", 80)
            getattr(connection, method).return_value = endpoint
            before = len(request_logs)
            api.request_log_event(401, api.request_log_tuple(connection))
            assert len(request_logs) == before, "不完整或非规范 socket 三元组不能伪造日志"
        connection = Mock()
        connection.getpeername.side_effect = OSError(TOKEN)
        api.request_log_event("connection_closed", api.request_log_tuple(connection))
        assert len(request_logs) == before, "socket 失败不得回显异常文本"
        endpoints = ("127.0.0.1", "127.0.0.1", server.server_address[1])
        original_log = access_path.read_bytes()
        with patch.object(api.os, "write", wraps=os.write) as write, \
                patch.object(api.os, "fsync", wraps=os.fsync) as sync:
            api.request_log_event(401, endpoints, access_path)
            write.assert_called_once()
            sync.assert_called_once()
        assert access_path.read_bytes() == original_log + (request_logs[-1] + "\n").encode("ascii")
        request_logs.pop()
        for tool, failure in (("write", 1), ("write", OSError(TOKEN)), ("fsync", OSError(TOKEN))):
            arguments = {"side_effect": failure} if isinstance(failure, OSError) else {"return_value": failure}
            with patch.object(api.os, tool, **arguments):
                log_failed(api.request_log_event, 401, endpoints, access_path)

        def fail_stdout(message, **arguments):
            if arguments.get("file") is not sys.stderr:
                raise BrokenPipeError(TOKEN)

        with patch.object(api, "print", side_effect=fail_stdout) as output:
            try:
                api.request_log_event(401, endpoints, access_path)
            except SystemExit as error:
                assert error.code == 78
            else:
                raise AssertionError("持久日志的 stdout 断管也必须停止服务")
            assert output.call_count == 2
            output.assert_called_with("控制访问日志写入失败，服务已停止", file=sys.stderr, flush=True)
        with patch.object(api, "open_access_log", wraps=api.open_access_log) as opened:
            log_failed(api.request_log_event, 401, None, access_path)
            opened.assert_not_called()
        access_path.write_bytes(b"")
        server.access_log = access_path
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
        assert request(f"/{TOKEN}?password={STATE['accounts'][0]['password']}", extra_headers={
            "X-Forwarded-For": "198.51.100.41",
            "Forwarded": 'for="198.51.100.42";host="log-injection"',
            "X-Real-IP": "198.51.100.43",
        })[0] == 404
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
        for mode in ("zero", "partial", "slow"):
            log_count = len(request_logs)
            blocked = socket.create_connection(server.server_address, timeout=2)
            started = threading.Event()

            def occupy():
                try:
                    if mode != "zero":
                        blocked.sendall(b"G")
                    started.set()
                    if mode == "slow":
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
            assert any("status=connection_closed source=127.0.0.1 " in line
                       for line in request_logs[log_count:]), f"{mode} 请求关闭必须记录真实 socket 来源"
    finally:
        server.shutdown()
        thread.join(timeout=3)
        server.server_close()
        log_sink.stop()
        assert not thread.is_alive()
    pattern = re.compile(
        r"(?P<time>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z) "
        r"control-request status=(?P<status>[1-5][0-9]{2}|connection_closed) "
        r"source=127\.0\.0\.1 target=127\.0\.0\.1 port=(?P<port>[0-9]+)"
    )
    statuses = set()
    for line in request_logs:
        record = pattern.fullmatch(line)
        assert record is not None, "访问与慢关闭日志必须只含固定字段和真实回环 socket 三元组"
        assert datetime.fromisoformat(record["time"]).utcoffset().total_seconds() == 0
        assert int(record["port"]) == server.server_address[1], "不能以模拟监听配置代替真实端口"
        statuses.add(record["status"])
    assert {"200", "401", "404", "400", "501", "connection_closed"} <= statuses
    assert access_path.read_bytes() == ("\n".join(request_logs) + "\n").encode("ascii"), \
        "真实响应与健康检查的持久日志必须逐字等于 stdout"
    logs = "\n".join(request_logs)
    for secret in (TOKEN, STATE["peer"]["token_sha256"], STATE["accounts"][0]["password"],
                   STATE["accounts"][0]["uuid"], "/v1/desired", "secret", "log-injection",
                   "198.51.100.41", "198.51.100.42", "198.51.100.43",
                   STATE["listen"]["address"], STATE["peer"]["address"]):
        assert secret not in logs, "日志不得记录凭据、路径、转发头或模拟来源"
    rejected(health)
    access_path.chmod(0o600)
    original_log = access_path.read_bytes()
    with api.ControlServer(("127.0.0.1", 0), TestHandler) as failed_server:
        failed_server.state_path = state_path
        failed_server.listen = STATE["listen"]
        failed_server.access_log = access_path
        with socket.create_connection(failed_server.server_address, timeout=2) as client, \
                patch.object(failed_server, "handle_error", side_effect=AssertionError("不能吞掉日志失败")):
            client.sendall(b"GET /v1/health HTTP/1.1\r\nHost: local\r\n\r\n")
            log_failed(failed_server._handle_request_noblock)
            assert client.recv(1) == b"", "日志权限失效必须先于任何 HTTP 响应退出"
    assert access_path.read_bytes() == original_log, "坏权限日志不能继续写入"

print("docker-control-api-regression-ok")
