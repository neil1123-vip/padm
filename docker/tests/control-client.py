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
from functools import partial
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


def rejected(function, *args, **kwargs):
    try:
        function(*args, **kwargs)
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


def local_connect(address, timeout=socket._GLOBAL_DEFAULT_TIMEOUT, source_address=None,
                  *, expected_port=18080, **kwargs):
    assert address == ("10.77.0.1", expected_port)
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


def cli(spec_path, invite_path, listeners=(), remap=False, reconnect=0, rebind=0):
    stdout, stderr = io.StringIO(), io.StringIO()
    arguments = ["control_client.py", "--spec", str(spec_path), "--invite", str(invite_path)]
    if remap:
        arguments.append("--remap")
    arguments.extend(["--reconnect"] * reconnect)
    arguments.extend(["--rebind"] * rebind)
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
        multi_spec = copy.deepcopy(SPEC)
        multi_spec["core"]["protocols"].append({
            "listener_id": "entry-secondary", "id": 4, "uuid": identity(10),
        })
        multi_original = copy.deepcopy(multi_spec)
        multi_joined = client.build_client_draft(
            multi_spec, INVITATION, ["entry-secondary", "entry-main", "entry-secondary"])
        mapped_account = dict(account(4), listeners=["entry-secondary", "entry-main"])
        assert multi_spec == multi_original
        assert multi_joined["control_sync"]["listener_ids"] == ["entry-secondary", "entry-main"]
        assert multi_joined["control_sync"]["managed_accounts"] == [mapped_account]
        assert multi_joined["accounts"] == SPEC["accounts"] + [mapped_account]
        assert multi_joined["core"] == multi_spec["core"]
        assert client.build_client_draft(multi_joined, INVITATION) == multi_joined
        remapped = client.build_client_draft(
            multi_joined, INVITATION, ["entry-main", "entry-main"], True)
        assert remapped["control_sync"]["listener_ids"] == ["entry-main"]
        assert remapped["control_sync"]["last_revision"] == multi_joined["control_sync"]["last_revision"]
        assert remapped["control_sync"]["last_digest"] == multi_joined["control_sync"]["last_digest"]
        assert remapped["accounts"] == joined["accounts"]
        assert remapped["core"] == multi_joined["core"]
        assert client.build_client_draft(remapped, INVITATION, ["entry-main"], True) == remapped
        assert multi_spec == multi_original

        reconnect_invite = copy.deepcopy(INVITATION)
        reconnect_invite["listen"]["port"] = 18081
        reconnect_invite["token"] = "b" * 48
        reconnect_source = copy.deepcopy(multi_joined)
        reconnect_source["traffic"] = {"unrelated": "unchanged"}
        reconnect_source["accounts"].append(dict(account(5), listeners=["entry-main"]))
        reconnect_original, reconnect_invite_original = copy.deepcopy(reconnect_source), copy.deepcopy(reconnect_invite)
        with patch.object(socket, "create_connection", side_effect=partial(local_connect, expected_port=18081)):
            reconnected = client.build_client_draft(reconnect_source, reconnect_invite, reconnect=True)
            expected = copy.deepcopy(reconnect_source)
            expected["control_sync"]["connection"]["listen"]["port"] = 18081
            assert reconnected == expected, "同版本重连只能改变 API port"
            assert client.build_client_draft(reconnected, reconnect_invite, reconnect=True) == reconnected
            assert connections[-1] == (("10.77.0.1", 18081), 5, ("10.77.0.2", 0))
            assert server.requests[-1][2].get_all("Authorization") == ["Bearer " + reconnect_invite["token"]]
            assert reconnect_invite["token"] not in json.dumps(reconnected)
            publish(dict(DESIRED, revision=8, accounts=[]))
            refreshed = client.build_client_draft(reconnect_source, reconnect_invite, reconnect=True)
            assert refreshed["accounts"] == [reconnect_source["accounts"][0], reconnect_source["accounts"][-1]]
            assert refreshed["control_sync"]["last_revision"] == 8
            assert refreshed["control_sync"]["connection"] == expected["control_sync"]["connection"]
            assert refreshed["core"] == reconnect_source["core"] and refreshed["traffic"] == reconnect_source["traffic"]
            publish()
        assert reconnect_source == reconnect_original and reconnect_invite == reconnect_invite_original

        rebind_invite = dict(INVITATION, controller_id=identity(6), node_id=identity(7), token="c" * 48,
                             listen=dict(INVITATION["listen"], port=18082))
        rebind_desired = dict(DESIRED, controller_id=identity(6), node_id=identity(7),
                              revision=1, accounts=[account(8)])
        rebind_source = copy.deepcopy(reconnect_source)
        rebind_original, rebind_invite_original = copy.deepcopy(rebind_source), copy.deepcopy(rebind_invite)
        publish(rebind_desired)
        with patch.object(socket, "create_connection", side_effect=partial(local_connect, expected_port=18082)):
            rebound = client.build_client_draft(rebind_source, rebind_invite, rebind=True)
            expected = copy.deepcopy(rebind_source)
            managed = dict(account(8), listeners=multi_joined["control_sync"]["listener_ids"])
            expected["accounts"] = [rebind_source["accounts"][0], rebind_source["accounts"][-1], managed]
            expected["control_sync"].update(
                controller_id=identity(6), node_id=identity(7), last_revision=1,
                last_digest=rebound["control_sync"]["last_digest"], managed_accounts=[managed],
                connection={"listen": rebind_invite["listen"], "peer_address": rebind_invite["peer_address"]})
            assert rebound == expected, "重绑定只能替换控制身份、连接和受管账号"
            assert rebound["control_sync"]["last_digest"] != rebind_source["control_sync"]["last_digest"]
            assert rebind_invite["token"] not in json.dumps(rebound)
            assert client.build_client_draft(rebound, rebind_invite, rebind=True) == rebound
            for response in (dict(rebind_desired, revision=0),
                             dict(rebind_desired, accounts=[account(12)])):
                publish(response)
                rejected(client.build_client_draft, rebound, rebind_invite, rebind=True)
            publish(rebind_desired)
            before = len(connections)
            for arguments in ({"listeners": ["entry-main"]}, {"remap": True}, {"reconnect": True}):
                rejected(client.build_client_draft, rebind_source, rebind_invite, rebind=True, **arguments)
            rejected(client.build_client_draft, rebind_source, rebind_invite)
            rejected(client.build_client_draft, rebind_source, rebind_invite, reconnect=True)
            rejected(client.build_client_draft, rebound, INVITATION)
            rejected(client.build_client_draft, rebound, INVITATION, reconnect=True)
            for failure in ("accounts", "snapshot", "duplicate-current", "duplicate-snapshot",
                            "mapping", "local", "revision", "digest"):
                drift = copy.deepcopy(rebind_source)
                if failure == "accounts":
                    drift["accounts"][1]["password"] += "changed"
                elif failure == "snapshot":
                    drift["control_sync"]["managed_accounts"][0]["password"] += "changed"
                elif failure == "duplicate-current":
                    drift["accounts"].append(copy.deepcopy(drift["accounts"][0]))
                elif failure == "duplicate-snapshot":
                    drift["control_sync"]["managed_accounts"] *= 2
                elif failure == "mapping":
                    drift["control_sync"]["listener_ids"] = ["entry-main"]
                elif failure == "local":
                    drift["accounts"][0]["uuid"] = drift["accounts"][-1]["uuid"]
                else:
                    drift["control_sync"]["last_" + failure] = True if failure == "revision" else "invalid"
                drift_original = copy.deepcopy(drift)
                rejected(client.build_client_draft, drift, rebind_invite, rebind=True)
                assert drift == drift_original
            for section, field, value in (("listen", "address", "10.77.0.3"),
                                          (None, "peer_address", "10.77.0.3")):
                invitation = copy.deepcopy(rebind_invite)
                (invitation[section] if section else invitation)[field] = value
                rejected(client.build_client_draft, rebind_source, invitation, rebind=True)
            assert len(connections) == before, "重绑定须先核验旧快照、账号和连接，参数冲突不能请求网络"
            for field, value in (("id", identity(3)), ("uuid", account(3)["uuid"]),
                                 ("password", account(3)["password"]), ("id", identity(4)),
                                 ("uuid", account(4)["uuid"]), ("password", account(4)["password"])):
                collision = dict(rebind_desired, accounts=[dict(account(8), **{field: value})])
                publish(collision)
                rejected(client.build_client_draft, rebind_source, rebind_invite, rebind=True)
            publish(dict(rebind_desired, accounts=[account(4)]))
            continued = client.build_client_draft(rebind_source, rebind_invite, rebind=True)
            assert continued["control_sync"]["managed_accounts"] == rebind_source["control_sync"]["managed_accounts"], \
                "同一账号仅在认证身份不变时保留历史累计归属"
            for response, status in ((dict(rebind_desired, controller_id=identity(1)), 200),
                                     (rebind_desired, 401)):
                publish(response, status=status)
                rejected(client.build_client_draft, rebind_source, rebind_invite, rebind=True)
            with patch.object(socket, "create_connection", side_effect=OSError("failed")):
                rejected(client.build_client_draft, rebind_source, rebind_invite, rebind=True)
        assert rebind_source == rebind_original and rebind_invite == rebind_invite_original
        publish()
        returned = client.build_client_draft(rebound, INVITATION, rebind=True)
        assert returned["control_sync"]["controller_id"] == INVITATION["controller_id"], \
            "仍获认证的旧邀请只有再次显式重绑定才能切回"
        assert returned["accounts"] == [rebind_source["accounts"][0], rebind_source["accounts"][-1],
                                       rebind_source["accounts"][1]]
        assert returned["traffic"] == rebind_source["traffic"]

        ss_spec = copy.deepcopy(multi_spec)
        ss_spec["core"]["protocols"].append({
            "listener_id": "entry-ss", "id": 30, "uuid": identity(11),
            "shadowsocks": {"server_password": "AgICAgICAgICAgICAgICAg=="},
        })
        ss_desired = copy.deepcopy(DESIRED)
        ss_desired["accounts"][0]["shadowsocks_password"] = "AQEBAQEBAQEBAQEBAQEBAQ=="
        ss_original, invite_original = copy.deepcopy(ss_desired), copy.deepcopy(INVITATION)
        publish(ss_desired)
        ss_joined = client.build_client_draft(ss_spec, INVITATION, ["entry-main"])
        ss_joined["traffic"] = {"unrelated": "unchanged"}
        assert ss_joined["accounts"][1]["shadowsocks_password"] is None
        ss_remapped = client.build_client_draft(ss_joined, INVITATION, ["entry-ss", "entry-secondary"], True)
        assert ss_remapped["control_sync"]["listener_ids"] == ["entry-ss", "entry-secondary"]
        assert ss_remapped["accounts"][1]["shadowsocks_password"] == ss_desired["accounts"][0]["shadowsocks_password"]
        assert ss_remapped["accounts"][0] == ss_joined["accounts"][0]
        assert ss_remapped["core"] == ss_joined["core"] and ss_remapped["traffic"] == ss_joined["traffic"]
        assert client.build_client_draft(ss_remapped, INVITATION, ["entry-ss", "entry-secondary"], True) == ss_remapped
        ss_removed = client.build_client_draft(ss_remapped, INVITATION, ["entry-main"], True)
        assert ss_removed == ss_joined
        assert ss_desired == ss_original and INVITATION == invite_original

        rebind_ss_desired = dict(rebind_desired, accounts=[
            dict(account(8), shadowsocks_password=ss_desired["accounts"][0]["shadowsocks_password"])])
        publish(rebind_ss_desired)
        with patch.object(socket, "create_connection", side_effect=partial(local_connect, expected_port=18082)):
            rejected(client.build_client_draft, ss_remapped, rebind_invite, rebind=True)
        publish(ss_desired)
        for section in ("accounts", "snapshot", "mapping"):
            drift = copy.deepcopy(ss_joined)
            if section == "mapping":
                drift["control_sync"]["listener_ids"] = ["entry-secondary"]
            else:
                drift["accounts"][1]["password"] += "changed"
                if section == "snapshot":
                    drift["control_sync"]["managed_accounts"][0]["password"] += "changed"
            rejected(client.build_client_draft, drift, INVITATION, ["entry-ss"], True)
            rejected(client.build_client_draft, drift, INVITATION, reconnect=True)
        for request in (dict(ss_desired, revision=6), DESIRED):
            publish(request)
            rejected(client.build_client_draft, ss_joined, INVITATION, ["entry-ss"], True)
            rejected(client.build_client_draft, ss_joined, INVITATION, reconnect=True)
        publish()
        rejected(client.build_client_draft, multi_joined, INVITATION, ["entry-ss"], True)
        ss_missing = client.build_client_draft(ss_spec, INVITATION, ["entry-main"])
        rejected(client.build_client_draft, ss_missing, INVITATION, ["entry-ss"], True)
        publish(ss_desired)
        for section in ("accounts", "core"):
            collision = copy.deepcopy(ss_joined)
            if section == "accounts":
                collision["accounts"][0]["shadowsocks_password"] = ss_desired["accounts"][0]["shadowsocks_password"]
            else:
                collision["core"]["protocols"][-1]["shadowsocks"]["server_password"] = ss_desired["accounts"][0]["shadowsocks_password"]
            rejected(client.build_client_draft, collision, INVITATION, ["entry-ss"], True)
        publish()
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
            rejected(client.build_client_draft, multi_joined, INVITATION, listeners, True)
        rejected(client.build_client_draft, multi_joined, INVITATION, None, True)
        rejected(client.build_client_draft, multi_joined, INVITATION, ["entry-main"])
        rejected(client.build_client_draft, SPEC, INVITATION, ["entry-main"], True)
        rejected(client.build_client_draft, SPEC, INVITATION, reconnect=True)
        rejected(client.build_client_draft, multi_joined, INVITATION, ["entry-main"], reconnect=True)
        rejected(client.build_client_draft, multi_joined, INVITATION, remap=True, reconnect=True)
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
            rejected(client.build_client_draft, drift, INVITATION, ["entry-main"], True)
            rejected(client.build_client_draft, drift, INVITATION, reconnect=True)
        for section, field, value in (("listen", "port", 18081), ("listen", "port", 18080.0),
                                      ("listen", "address", "10.77.0.3"),
                                      (None, "peer_address", "10.77.0.3")):
            drift = copy.deepcopy(joined)
            connection = drift["control_sync"]["connection"]
            (connection[section] if section else connection)[field] = value
            rejected(client.build_client_draft, drift, INVITATION)
            rejected(client.build_client_draft, drift, INVITATION, ["entry-main"], True)
        legacy = copy.deepcopy(joined)
        del legacy["control_sync"]["connection"]
        rejected(client.build_client_draft, legacy, INVITATION)
        rejected(client.build_client_draft, legacy, INVITATION, reconnect=True)
        for section, field, value in (("listen", "interface", "wg-other"), ("listen", "port", 18080.0),
                                      ("listen", "address", "10.77.0.3"), (None, "peer_address", "10.77.0.3")):
            drift = copy.deepcopy(joined)
            connection = drift["control_sync"]["connection"]
            (connection[section] if section else connection)[field] = value
            rejected(client.build_client_draft, drift, INVITATION, reconnect=True)
        assert len(connections) == before, "无效邀请、映射或状态不能发起网络请求"

        for field, value in (("controller_id", identity(6)), ("node_id", identity(6)),
                             ("api_version", 2), ("api_version", True), ("revision", 6)):
            publish(dict(DESIRED, **{field: value}))
            rejected(client.build_client_draft, joined, INVITATION)
            rejected(client.build_client_draft, joined, INVITATION, reconnect=True)
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
            save(spec_path, multi_spec)
            source = spec_path.read_bytes()
            status, output, errors = cli(spec_path, invite_path, ["entry-secondary", "entry-main"])
            assert status == 0 and json.loads(output) == multi_joined and not errors
            assert spec_path.read_bytes() == source
            save(spec_path, multi_joined)
            source = spec_path.read_bytes()
            status, output, errors = cli(spec_path, invite_path, ["entry-main", "entry-main"], True)
            assert status == 0 and json.loads(output) == remapped and not errors
            assert spec_path.read_bytes() == source and INVITATION["token"] not in output
            for listeners in ([], ["entry-missing"], [INVITATION["token"]]):
                status, output, errors = cli(spec_path, invite_path, listeners, True)
                assert status == 78 and not output and errors
                assert spec_path.read_bytes() == source and INVITATION["token"] not in errors
            save(spec_path, reconnect_source)
            save(invite_path, reconnect_invite)
            source, invite_source = spec_path.read_bytes(), invite_path.read_bytes()
            with patch.object(socket, "create_connection", side_effect=partial(local_connect, expected_port=18081)):
                status, output, errors = cli(spec_path, invite_path, reconnect=True)
            assert status == 0 and json.loads(output) == reconnected and not errors
            assert spec_path.read_bytes() == source and invite_path.read_bytes() == invite_source
            assert reconnect_invite["token"] not in output
            before = len(connections)
            for arguments in ({"reconnect": 2}, {"remap": True, "reconnect": True},
                              {"listeners": ["entry-main"], "reconnect": True}):
                status, output, errors = cli(spec_path, invite_path, **arguments)
                assert status == 78 and not output and errors
                assert spec_path.read_bytes() == source and invite_path.read_bytes() == invite_source
                assert reconnect_invite["token"] not in errors
            assert len(connections) == before, "重连参数冲突不能发起网络请求"
            with patch.object(socket, "create_connection", side_effect=OSError("failed")):
                status, output, errors = cli(spec_path, invite_path, reconnect=True)
            assert status == 78 and not output and errors and reconnect_invite["token"] not in errors
            assert spec_path.read_bytes() == source and invite_path.read_bytes() == invite_source
            save(spec_path, rebind_source)
            save(invite_path, rebind_invite)
            source, invite_source = spec_path.read_bytes(), invite_path.read_bytes()
            publish(rebind_desired)
            with patch.object(socket, "create_connection", side_effect=partial(local_connect, expected_port=18082)):
                status, output, errors = cli(spec_path, invite_path, rebind=True)
                assert status == 0 and json.loads(output) == rebound and not errors
                assert rebind_invite["token"] not in output
                assert spec_path.read_bytes() == source and invite_path.read_bytes() == invite_source
                before = len(connections)
                for arguments in ({"rebind": 2}, {"rebind": True, "listeners": ["entry-main"]},
                                  {"rebind": True, "remap": True}, {"rebind": True, "reconnect": True}):
                    status, output, errors = cli(spec_path, invite_path, **arguments)
                    assert status == 78 and not output and errors
                    assert rebind_invite["token"] not in errors
                    assert spec_path.read_bytes() == source and invite_path.read_bytes() == invite_source
                assert len(connections) == before, "重绑定参数重复或冲突不能发起网络请求"
                publish(rebind_desired, status=401)
                status, output, errors = cli(spec_path, invite_path, rebind=True)
                assert status == 78 and not output and errors and rebind_invite["token"] not in errors
                assert spec_path.read_bytes() == source and invite_path.read_bytes() == invite_source
            publish()
            save(invite_path, INVITATION)
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
