#!/usr/bin/env python3
import contextlib
import copy
import http.client
import io
import json
import os
import socket
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "docker/images/ops"))
import control_client as client

assert sys.platform == "linux" and os.getuid() == 0, "客户端回归必须使用 Linux root"


def identity(number):
    return f"{number:08d}-1111-4111-8111-{number:012d}"


def account(number):
    return {
        "id": identity(number), "name": f"账号{number}", "enabled": True,
        "uuid": identity(number + 100), "password": f"Password.-~@+=:{number:08d}",
        "shadowsocks_password": None,
    }


INVITATION = {
    "format": "padm-docker-control-invite", "schema_version": 1,
    "controller_id": identity(1), "node_id": identity(2),
    "listen": {"interface": "wg-padm", "address": "10.77.0.1", "port": 18080},
    "peer_address": "10.77.0.2", "token": "a" * 48,
    "expires_at": int(time.time()) + 3600,
}
SPEC = {
    "schema_version": 3,
    "core": {"protocols": [{
        "listener_id": "entry-main", "id": 1, "uuid": identity(9),
    }]},
    "accounts": [dict(account(3), listeners=["entry-main"])],
}
DESIRED = {
    "ok": True, "api_version": 1, "controller_id": identity(1),
    "node_id": identity(2), "revision": 7, "accounts": [account(4)],
}


def rejected(function, *args):
    try:
        function(*args)
    except (ValueError, OSError, KeyError, TypeError, AttributeError, RecursionError,
            http.client.HTTPException):
        return
    raise AssertionError("客户端未拒绝异常输入或响应")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        self.server.requests.append((self.path, self.client_address[0], self.headers))
        body = self.server.body
        self.send_response(self.server.status)
        for key, value in self.server.headers:
            self.send_header(key, value)
        self.end_headers()
        try:
            if self.server.delay:
                # 持续发送而非闲置，证明总时限不被零散读写延长。
                for byte in body:
                    self.wfile.write(bytes([byte]))
                    self.wfile.flush()
                    time.sleep(self.server.delay)
            else:
                self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass
        self.close_connection = True

    def log_message(self, *_args):
        pass


server = HTTPServer(("127.0.0.1", 0), Handler)
server.requests = []
thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.01})
thread.start()
real_connect = socket.create_connection
connections = []


def local_connect(address, timeout=socket._GLOBAL_DEFAULT_TIMEOUT, source_address=None, **kwargs):
    assert address == ("10.77.0.1", 18080)
    assert source_address == ("10.77.0.2", 0)
    connections.append((address, timeout, source_address))
    # 只把私网字面地址映射到 Linux loopback，保留真实 HTTPConnection 和源地址绑定。
    return real_connect(server.server_address, timeout=timeout,
                        source_address=("127.0.0.2", 0), **kwargs)


def publish(value=DESIRED, *, status=200, headers=None, raw=None, delay=0):
    server.body = raw if raw is not None else json.dumps(value, ensure_ascii=True).encode("ascii")
    server.status, server.delay = status, delay
    server.headers = headers if headers is not None else [
        ("Content-Type", "application/json"), ("Cache-Control", "no-store"),
        ("Content-Length", str(len(server.body))), ("Connection", "close"),
    ]


def cli(spec_path, invite_path, listeners=()):
    stdout, stderr = io.StringIO(), io.StringIO()
    arguments = ["control_client.py", "--spec", str(spec_path), "--invite", str(invite_path)]
    for listener in listeners:
        arguments.extend(["--listener", listener])
    status = 0
    with patch.object(sys, "argv", arguments), contextlib.redirect_stdout(stdout), \
            contextlib.redirect_stderr(stderr):
        try:
            client.main()
        except SystemExit as error:
            status = error.code
    return status, stdout.getvalue(), stderr.getvalue()


try:
    publish()
    with patch.object(client, "require_wireguard_address") as require, \
            patch.object(socket, "create_connection", side_effect=local_connect):
        original = copy.deepcopy(SPEC)
        joined = client.build_client_draft(SPEC, INVITATION, ["entry-main", "entry-main"])
        assert SPEC == original
        assert joined["control_sync"]["listener_ids"] == ["entry-main"]
        assert joined["control_sync"]["last_revision"] == 7
        assert joined["control_sync"]["connection"] == {
            "listen": INVITATION["listen"], "peer_address": INVITATION["peer_address"]}
        assert INVITATION["token"] not in json.dumps(joined)
        assert "expires_at" not in joined["control_sync"]["connection"]
        assert joined["accounts"][0] == SPEC["accounts"][0]
        assert joined["accounts"][1]["id"] == identity(4)
        assert client.build_client_draft(joined, INVITATION) == joined
        path, address, headers = server.requests[-1]
        assert path == "/v1/desired" and address == "127.0.0.2"
        assert headers.get_all("Authorization") == ["Bearer " + INVITATION["token"]]
        assert headers.get_all("X-Padm-Control-Version") == ["1"]
        assert connections[-1] == (("10.77.0.1", 18080), 5, ("10.77.0.2", 0))
        require.assert_called_with({
            "listen": {"interface": "wg-padm", "address": "10.77.0.2"}})
        with patch.object(client.time, "monotonic", side_effect=[10.0, 10.15]), \
                patch.object(client.threading, "Timer", wraps=threading.Timer) as timer:
            assert client.fetch_desired(INVITATION) == DESIRED
            assert abs(timer.call_args.args[0] - 4.85) < 0.000001

        local_extra = copy.deepcopy(joined)
        local_extra["accounts"].append(dict(account(5), listeners=["entry-main"]))
        assert client.build_client_draft(local_extra, INVITATION) == local_extra
        advanced = dict(DESIRED, revision=8, accounts=[])
        publish(advanced)
        emptied = client.build_client_draft(joined, INVITATION)
        assert emptied["accounts"] == SPEC["accounts"]
        assert emptied["control_sync"]["last_revision"] == 8
        publish()

        before = len(connections)
        for field, value in (
                ("format", "wrong"), ("schema_version", 2), ("schema_version", True),
                ("controller_id", identity(2)), ("controller_id", 1), ("node_id", None),
                ("peer_address", "10.77.0.1"), ("peer_address", "127.0.0.2"),
                ("peer_address", "8.8.8.8"), ("peer_address", 1),
                ("token", "a" * 47), ("token", "A" * 48), ("token", None),
                ("expires_at", int(time.time()) - 1), ("expires_at", True),
                ("expires_at", 9007199254740992)):
            rejected(client.build_client_draft, SPEC, dict(INVITATION, **{field: value}), ["entry-main"])
        for field, value in (("address", "127.0.0.1"), ("address", "controller.example"),
                             ("interface", "wg-other"), ("port", True), ("port", 1)):
            invitation = copy.deepcopy(INVITATION)
            invitation["listen"][field] = value
            rejected(client.build_client_draft, SPEC, invitation, ["entry-main"])
        for listeners in ([], ["entry-missing"], [None]):
            rejected(client.build_client_draft, SPEC, INVITATION, listeners)
        for role in ("control", "control_sync"):
            occupied = copy.deepcopy(SPEC)
            occupied[role] = {}
            rejected(client.build_client_draft, occupied, INVITATION, ["entry-main"])
        rejected(client.build_client_draft, dict(SPEC, schema_version=3.0), INVITATION, ["entry-main"])
        for field, value in (("node_id", identity(6)), ("controller_id", identity(6)),
                             ("schema_version", True), ("listener_ids", ["entry-missing"])):
            drift = copy.deepcopy(joined)
            drift["control_sync"][field] = value
            rejected(client.build_client_draft, drift, INVITATION)
        for section, field, value in (("listen", "port", 18081), ("listen", "port", 18080.0),
                                      ("listen", "address", "10.77.0.3"),
                                      (None, "peer_address", "10.77.0.3")):
            drift = copy.deepcopy(joined)
            connection = drift["control_sync"]["connection"]
            (connection[section] if section else connection)[field] = value
            rejected(client.build_client_draft, drift, INVITATION)
        legacy = copy.deepcopy(joined)
        del legacy["control_sync"]["connection"]
        rejected(client.build_client_draft, legacy, INVITATION)
        assert len(connections) == before, "无效邀请、映射或状态不能发起网络请求"

        for field, value in (("controller_id", identity(6)), ("node_id", identity(6)),
                             ("api_version", 2), ("api_version", True), ("revision", 6)):
            publish(dict(DESIRED, **{field: value}))
            rejected(client.build_client_draft, joined, INVITATION)
        collision = copy.deepcopy(DESIRED)
        collision["accounts"][0]["uuid"] = SPEC["accounts"][0]["uuid"]
        publish(collision)
        rejected(client.build_client_draft, SPEC, INVITATION, ["entry-main"])
        assert SPEC == original

        for status in (401, 302, 500):
            publish(status=status)
            rejected(client.fetch_desired, INVITATION)
        nonce = "b" * 64
        publish({"ok": False, "error": "unauthorized"}, status=401)
        client.source_probe("10.77.0.1", 18080, "10.77.0.2", nonce)
        path, address, probe_headers = server.requests[-1]
        assert path == "/v1/health" and address == "127.0.0.2"
        assert probe_headers.get_all("X-Padm-Source-Challenge") == [nonce]
        assert probe_headers.get_all("Authorization") is None, "来源探测不得携带授权"
        before = len(connections)
        for arguments in (("8.8.8.8", 18080, "10.77.0.2", nonce),
                          ("10.77.0.1", True, "10.77.0.2", nonce),
                          ("10.77.0.1", 18080, "10.77.0.1", nonce),
                          ("10.77.0.1", 18080, "10.77.0.2", nonce + "\n")):
            rejected(client.source_probe, *arguments)
        assert len(connections) == before
        for body, status in (({"ok": True}, 401), ({"ok": False, "error": "unauthorized"}, 200),
                             ({"ok": False, "error": "unauthorized"}, 302)):
            publish(body, status=status)
            rejected(client.source_probe, "10.77.0.1", 18080, "10.77.0.2", nonce)
        publish({"ok": False, "error": "unauthorized"}, status=401, delay=0.025)
        with patch.object(client, "REQUEST_TIMEOUT", 0.2):
            started = time.monotonic()
            rejected(client.source_probe, "10.77.0.1", 18080, "10.77.0.2", nonce)
            assert time.monotonic() - started < 1, "来源探测必须沿用请求总时限"
        publish()
        headers = [
            ("Content-Type", "application/json"), ("Cache-Control", "no-store"),
            ("Content-Length", str(len(server.body))),
        ]
        for key, value in (("Content-Type", "application/json"), ("Cache-Control", "no-store"),
                           ("Content-Length", str(len(server.body))), ("Transfer-Encoding", "chunked")):
            publish(headers=headers + [(key, value)])
            rejected(client.fetch_desired, INVITATION)
        for length in ("01", "-1", "+1", "1.0", str(client.MAX_STATE_BYTES + 1)):
            publish(headers=headers[:2] + [("Content-Length", length)])
            rejected(client.fetch_desired, INVITATION)
        publish(headers=headers[:2])
        rejected(client.fetch_desired, INVITATION)
        publish(headers=[("Content-Type", "text/plain")] + headers[1:])
        rejected(client.fetch_desired, INVITATION)
        publish(headers=[headers[0], ("Cache-Control", "public"), headers[2]])
        rejected(client.fetch_desired, INVITATION)
        for body in (b"{", b"[]", b'{"ok":true,"ok":true}', b'{"name":"\xff"}',
                     b"[" * 1100 + b"0" + b"]" * 1100):
            publish(raw=body)
            rejected(client.fetch_desired, INVITATION)
        publish(headers=headers[:2] + [("Content-Length", str(len(server.body) + 1))])
        rejected(client.fetch_desired, INVITATION)
        publish(delay=0.025)
        with patch.object(client, "REQUEST_TIMEOUT", 0.2):
            started = time.monotonic()
            rejected(client.fetch_desired, INVITATION)
            assert time.monotonic() - started < 1, "慢速响应必须按总时限结束"
        publish()

        with tempfile.TemporaryDirectory(prefix=".tmp-control-client-") as directory:
            spec_path, invite_path = Path(directory) / "spec.json", Path(directory) / "invite.json"

            def save(path, value):
                path.write_text(json.dumps(value), encoding="utf-8")
                path.chmod(0o600)

            save(spec_path, SPEC)
            save(invite_path, INVITATION)
            source = spec_path.read_bytes()
            status, output, errors = cli(spec_path, invite_path, ["entry-main"])
            assert status == 0 and json.loads(output) == joined and not errors
            assert INVITATION["token"] not in output
            assert spec_path.read_bytes() == source
            save(spec_path, joined)
            source = spec_path.read_bytes()
            assert cli(spec_path, invite_path)[0] == 0
            for failure in ("network", "permission", "duplicate", "fifo", "link"):
                save(invite_path, INVITATION)
                connection_patch = contextlib.nullcontext()
                if failure == "network":
                    connection_patch = patch.object(socket, "create_connection", side_effect=OSError("failed"))
                elif failure == "permission":
                    invite_path.chmod(0o644)
                elif failure == "duplicate":
                    invite_path.write_text('{"token":"secret","token":"secret"}')
                elif failure == "fifo":
                    invite_path.unlink()
                    os.mkfifo(invite_path, 0o600)
                else:
                    invite_path.unlink()
                    invite_path.symlink_to(spec_path)
                with connection_patch:
                    status, output, errors = cli(spec_path, invite_path)
                assert status == 78 and not output and errors
                assert INVITATION["token"] not in errors and "secret" not in errors
                assert spec_path.read_bytes() == source
                invite_path.unlink()
finally:
    server.shutdown()
    server.server_close()
    thread.join(timeout=2)

print("docker-control-client-regression-ok")
