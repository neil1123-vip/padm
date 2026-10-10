#!/usr/bin/env python3
import hashlib
import http.client
import json
import os
import re
import runpy
import shlex
import shutil
import socket
import socketserver
import subprocess
import sys
import tempfile
import time
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

SCRIPT = Path(__file__).resolve()
ROOT = SCRIPT.parents[2]
helpers = runpy.run_path(str(SCRIPT.with_name("control-two-node-real.py")))
run, stop, namespace, identity = (helpers[name] for name in ("run", "stop", "namespace", "identity"))
TARGET, OTHER_TARGET, PEER, PORT = "10.231.0.1", "10.231.0.3", "10.231.0.2", 39778
TOKEN, WS_TOKEN = "a" * 48, "0123456789abcdef0123456789abcdef"


def wait_ready(probe, message, limit=15):
    deadline = time.monotonic() + limit
    while True:
        if probe():
            return
        assert time.monotonic() < deadline, message
        time.sleep(0.05)


def request(address, port, mode):
    try:
        if mode == "closed":
            with socket.create_connection((address, int(port)), timeout=1, source_address=(PEER, 0)):
                return {"closed": True}
        connection = http.client.HTTPConnection(
            address, int(port), timeout=1, source_address=(PEER, 0))
        try:
            headers = {"Connection": "close"}
            if mode == "authorized":
                headers.update(Authorization="Bearer " + TOKEN, **{"X-Padm-Control-Version": "1"})
            elif mode.startswith("nonce:"):
                headers["X-Padm-Source-Challenge"] = mode.removeprefix("nonce:")
            connection.request("GET", "/v1/health", headers=headers)
            response = connection.getresponse()
            response.read()
            return {"status": response.status}
        finally:
            connection.close()
    except (TimeoutError, socket.timeout):
        return {"timeout": True}
    except (ConnectionRefusedError, http.client.RemoteDisconnected) as error:
        return {"not_ready": type(error).__name__}


def client(pid, address=TARGET, port=PORT, mode="unauthorized"):
    return json.loads(run([sys.executable, str(SCRIPT), "--request", address, str(port), mode], pid, timeout=4))


def other_target_api(directory):
    listen = json.loads((directory / "state.json").read_text())["listen"]

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            content = b'{"ok":false,"error":"unauthorized"}'
            self.send_response(401)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(content)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(content)
            self.close_connection = True

        def log_request(self, code="-", size="-"):
            source = self.connection.getpeername()[0]
            target, port = self.connection.getsockname()
            timestamp = datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
            line = f"{timestamp} control-request status={code} source={source} target={target} port={port}\n"
            with (directory / "logs/auth.log").open("ab") as output:
                output.write(line.encode("ascii"))

        def log_message(self, message_format, *args):
            pass

    class Server(HTTPServer):
        def server_bind(self):
            socketserver.TCPServer.server_bind(self)
            self.server_name, self.server_port = self.server_address

    # 此端点只提供异目标负例，不绕过生产 API 对受管主地址的校验。
    Server((listen["address"], listen["port"]), Handler).serve_forever()


def configure(work):
    spec = work / "spec.json"
    spec.write_text(json.dumps({"control": {"role": "main", "listen": {
        "interface": "wg-padm", "address": TARGET, "port": PORT}}}))
    run(["bash", "-Eeuo", "pipefail", "-c",
         'source "$1/install-docker.sh"; dockerGenerateControlFail2banConfig "$2" "$3" 3 600 3600',
         "fixture", str(ROOT), str(spec), str(work)])
    source = (ROOT / "docker/images/net/entrypoint.sh").read_text()
    marker = 'case "${1:-idle}" in'
    assert source.count(marker) == 1
    (work / "net-functions.sh").write_text(source.split(marker, 1)[0])
    state_root = work / "net-state"
    state_root.mkdir(mode=0o750)
    os.chown(state_root, 0, 10001)
    (state_root / "fail2ban.sqlite3").write_bytes(b"ws-database-scope-marker\n")
    return state_root


def api_files(work, address, port):
    directory = work / f"api-{address}-{port}"
    directory.mkdir(mode=0o750)
    os.chown(directory, 0, 10001)
    logs, challenges = directory / "logs", directory / "challenges"
    for path in (logs, challenges):
        path.mkdir(mode=0o750)
        os.chown(path, 0, 10001)
    for name in ("auth.log", "source.receipt", "auth.lock"):
        path = logs / name
        path.touch(mode=0o640)
        os.chown(path, 0 if name == "auth.lock" else 10001, 10001)
    state = {
        "schema_version": 1, "role": "main", "node_id": identity(1), "revision": 0,
        "listen": {"interface": "wg-padm", "address": address, "port": port},
        "peer": {"id": identity(2), "address": PEER, "enabled": True,
                 "expires_at": int(time.time()) + 3600,
                 "token_sha256": hashlib.sha256(TOKEN.encode()).hexdigest()},
        "accounts": [],
    }
    path = directory / "state.json"
    path.write_text(json.dumps(state))
    path.chmod(0o640)
    os.chown(path, 0, 10001)
    return directory


def wireguard(work, holders):
    original = os.readlink("/proc/self/ns/net")
    for _ in range(2):
        process = subprocess.Popen(["unshare", "--net", "--", "sleep", "3600"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        holders.append(process)
        wait_ready(lambda: process.poll() is None and os.readlink(f"/proc/{process.pid}/ns/net") != original,
                   "独立控制网络空间未就绪", 5)
    controller, controlled = (process.pid for process in holders)
    names = ["fc" + uuid.uuid4().hex[:10], "fp" + uuid.uuid4().hex[:10]]
    run(["ip", "link", "add", names[0], "type", "veth", "peer", "name", names[1]])
    for name, pid in zip(names, (controller, controlled)):
        run(["ip", "link", "set", name, "netns", str(pid)])
        run(["ip", "link", "set", name, "name", "underlay"], pid)
        run(["ip", "link", "set", "lo", "up"], pid)
    keys, public = [], []
    for index in range(2):
        path = work / f"wg-key-{index}"
        key = run(["wg", "genkey"])
        path.write_bytes(key)
        path.chmod(0o600)
        keys.append(path)
        public.append(run(["wg", "pubkey"], content=key).decode().strip())
    for index, pid in enumerate((controller, controlled)):
        run(["ip", "address", "add", f"192.0.2.{index + 1}/30", "dev", "underlay"], pid)
        run(["ip", "link", "set", "underlay", "up"], pid)
        run(["ip", "link", "add", "wg-padm", "type", "wireguard"], pid)
        addresses = (TARGET, OTHER_TARGET) if index == 0 else (PEER,)
        peers = (PEER,) if index == 0 else (TARGET, OTHER_TARGET)
        run(["wg", "set", "wg-padm", "private-key", str(keys[index]), "listen-port", "51820",
             "peer", public[1 - index], "allowed-ips", ",".join(f"{address}/32" for address in peers),
             "endpoint", f"192.0.2.{2 - index}:51820", "persistent-keepalive", "1"], pid)
        for address in addresses:
            run(["ip", "address", "add", f"{address}/32", "dev", "wg-padm"], pid)
        run(["ip", "link", "set", "wg-padm", "up"], pid)
        for address in peers:
            run(["ip", "route", "add", f"{address}/32", "dev", "wg-padm"], pid)
    assert os.readlink(f"/proc/{controller}/ns/net") != os.readlink(f"/proc/{controlled}/ns/net")
    return controller, controlled


def main():
    assert os.getuid() == 0 and Path("/.dockerenv").is_file() and sys.platform == "linux"
    assert {item["ifname"] for item in json.loads(run(["ip", "-j", "link"]))} == {"lo"}, \
        "真实 INPUT 验收不得借用宿主接口或 Socket"
    inputs = json.loads(Path("/node-images.json").read_text(encoding="utf-8-sig"))
    assert {"ops", "net"} <= inputs.keys() and Path("/node-images.tar").is_file()
    work = Path(tempfile.mkdtemp(prefix=".tmp-control-fail2ban-", dir="/n"))
    work.chmod(0o750)
    os.chown(work, 0, 10001)
    holders, daemon, containers, docker = [], None, [], None
    started = time.monotonic()
    try:
        state_root = configure(work)
        controller, controlled = wireguard(work, holders)
        docker = namespace(controller) + ["docker", "--host", f"unix://{work}/docker.sock"]
        with (work / "daemon.log").open("wb") as output:
            daemon = subprocess.Popen(namespace(controller) + [
                "dockerd", "--host", docker[-1], "--data-root", str(work / "docker"),
                "--exec-root", str(work / "run"), "--pidfile", str(work / "daemon.pid"),
                "--feature", "containerd-snapshotter=true", "--storage-driver", "overlayfs",
                "--bridge", "none", "--iptables=false", "--ip6tables=false"],
                stdout=output, stderr=subprocess.STDOUT)
        wait_ready(lambda: subprocess.run(docker + ["info"], capture_output=True, timeout=3).returncode == 0,
                   "隔离服务端 daemon 未就绪", 30)
        run(docker + ["load", "--input", "/node-images.tar"], timeout=120)
        for item in inputs.values():
            assert json.loads(run(docker + ["image", "inspect", item["reference"]]))[0]["Id"] == item["image_id"]

        def create(arguments):
            container = run(docker + ["run", "-d", "--read-only", "--cap-drop", "ALL",
                                      "--security-opt", "no-new-privileges:true", "--network", "host",
                                      *arguments], timeout=20).decode().strip()
            containers.append(container)
            return container

        api_paths = {}
        for address, port in ((TARGET, PORT), (OTHER_TARGET, PORT), (TARGET, PORT + 1)):
            directory = api_files(work, address, port)
            api_paths[address, port] = directory
            arguments = ["--user", "10001:10001", "--mount", f"type=bind,src={directory},dst=/input"]
            if address == OTHER_TARGET:
                source, destination = SCRIPT, "/opt/padm/fixture/control-fail2ban-real.py"
                arguments.extend([
                    "--mount", f"type=bind,src={SCRIPT.parent},dst=/opt/padm/fixture,readonly",
                    "--entrypoint", "python3", inputs["ops"]["reference"],
                    destination, "--other-api", "/input"])
            else:
                source, destination = ROOT / "docker/images/ops/control_api.py", "/opt/padm/control_api.py"
                arguments.extend([
                    "--mount", f"type=bind,src={source},dst={destination},readonly",
                    "--entrypoint", "python3", inputs["ops"]["reference"], destination,
                    "--state", "/input/state.json", "--access-log", "/input/logs/auth.log",
                    "--access-lock", "/input/logs/auth.lock",
                    "--source-challenge", "/input/challenges/challenge.json",
                    "--source-receipt", "/input/logs/source.receipt"])
            container = create(arguments)
            actual = json.loads(run(docker + ["inspect", container]))[0]
            assert actual["Config"]["User"] == "10001:10001" and not actual["HostConfig"]["CapAdd"]
            assert run(docker + ["exec", container, "sha256sum", destination]).split()[0].decode() == \
                hashlib.sha256(source.read_bytes()).hexdigest()
            status = 401 if address == OTHER_TARGET else 200
            wait_ready(lambda: client(controlled, address, port, "authorized") == {"status": status},
                       "真实 HTTP 端点未就绪")
        main_api = api_paths[TARGET, PORT]
        auth = main_api / "logs/auth.log"
        receipt = main_api / "logs/source.receipt"
        negative = []
        for _ in range(3):
            assert client(controlled, mode="authorized") == {"status": 200}
            assert client(controlled, mode="closed") == {"closed": True}
            for address, port in ((OTHER_TARGET, PORT), (TARGET, PORT + 1)):
                assert client(controlled, address, port) == {"status": 401}
        wait_ready(lambda: b"status=connection_closed" in auth.read_bytes(), "真实关闭连接未写脱敏日志")
        negative.extend(auth.read_bytes().splitlines(keepends=True))
        for key in ((OTHER_TARGET, PORT), (TARGET, PORT + 1)):
            negative.extend((api_paths[key] / "logs/auth.log").read_bytes().splitlines(keepends=True))
        nonce = "d" * 64
        registration = main_api / "challenges/challenge.json"
        registration.write_text(json.dumps({
            "schema_version": 1, "nonce": nonce, "expires_at": int(time.time()) + 30,
            "expected_source": PEER, "target": TARGET, "port": PORT}))
        registration.chmod(0o640)
        os.chown(registration, 0, 10001)
        assert client(controlled, mode="nonce:" + nonce) == {"status": 401}
        registration.unlink()
        assert f"nonce={nonce} status=401 source={PEER}".encode() in receipt.read_bytes()
        negative.extend(receipt.read_bytes().splitlines(keepends=True) * 3)
        (work / "negative.log").write_bytes(b"".join(negative))
        # 独立负例保留真实日志格式，挑战请求的普通 401 不混入后面的 retry 计数。
        auth.write_bytes(b"".join(negative))

        config = work / "config/net/control-fail2ban"
        mounts = [
            "--mount", f"type=bind,src={state_root},dst=/var/lib/padm/net",
            "--mount", f"type=bind,src={main_api / 'logs'},dst=/var/log/padm/control,readonly",
            "--mount", f"type=bind,src={work},dst=/test,readonly",
            "--mount", f"type=bind,src={ROOT / 'docker/images/net/entrypoint.sh'},dst=/usr/local/bin/padm-entrypoint,readonly",
        ]
        for source, target in (
            ("padm.local", "jail.d/padm.local"), ("fail2ban.local", "fail2ban.local"),
            ("padm-control.conf", "filter.d/padm-control.conf"),
            ("padm-control-input.conf", "action.d/padm-control-input.conf"),
        ):
            mounts.extend(["--mount", f"type=bind,src={config / source},dst=/etc/fail2ban/{target},readonly"])
        net_args = ["--user", "0:10001", "--cap-add", "NET_ADMIN",
                    "--tmpfs", "/run:rw,noexec,nosuid,nodev", "--tmpfs", "/tmp:rw,noexec,nosuid,nodev",
                    "--hostname", "control-fixture.padm.test",
                    "--add-host", "control-fixture.padm.test:127.0.0.1", *mounts]
        kernel = create([*net_args, "--entrypoint", "sh", inputs["net"]["reference"],
                         "-c", "exec tail -f /dev/null"])
        execute = docker + ["exec", kernel]
        assert run(execute + ["sha256sum", "/usr/local/bin/padm-entrypoint"]).split()[0].decode() == \
            hashlib.sha256((ROOT / "docker/images/net/entrypoint.sh").read_bytes()).hexdigest()
        run(execute + ["iptables", "-w", "-N", "DOCKER-USER"])
        # WS 使用生产 owner/action 建立独立资源，再验证 INPUT 动作不改动其完整快照。
        seed = ('. /test/net-functions.sh; fb_root=$STATE_ROOT; fb_token=' + WS_TOKEN +
                '; fb_chain=padm-f2b-0123456789ab; fb_ports=24444; fb_ipv6=no; '
                'fail2ban_state_write; fail2ban_resources start iptables; '
                'fail2ban_action ban ' + WS_TOKEN + ' iptables -w ' + PEER)
        run(execute + ["sh", "-eu", "-c", seed])
        ws_state = (state_root / "fail2ban.state").read_bytes()
        ws_database = (state_root / "fail2ban.sqlite3").read_bytes()

        def ws_rules():
            rules = run(execute + ["iptables", "-w", "-S"]).decode().splitlines()
            return [line for line in rules if "DOCKER-USER" in line or "padm-f2b-" in line]

        ws_snapshot = ws_rules()

        def ws_unchanged():
            assert ws_rules() == ws_snapshot and (state_root / "fail2ban.state").read_bytes() == ws_state
            assert (state_root / "fail2ban.sqlite3").read_bytes() == ws_database

        regex = run(execute + ["fail2ban-regex", "/test/negative.log",
                               "/etc/fail2ban/filter.d/padm-control.conf"]).decode()
        assert re.search(r"Failregex:\s+0 total", regex), "200/关闭连接/错误目标端口/nonce 回执触发认证 filter：" + regex
        # 同名和同地址不能冒充 WireGuard；暂时保留真实接口，拒绝后原样恢复。
        run(execute + ["ip", "link", "set", "wg-padm", "name", "wg-fixture"])
        dummy = False
        try:
            run(execute + ["ip", "link", "add", "wg-padm", "type", "dummy"])
            dummy = True
            run(execute + ["ip", "address", "add", TARGET + "/32", "dev", "wg-padm"])
            run(execute + ["ip", "link", "set", "wg-padm", "up"])
            before = run(execute + ["iptables", "-w", "-S"])
            rejected = subprocess.run(execute + ["sh", "/usr/local/bin/padm-entrypoint",
                "preflight", "fail2ban-control", TARGET, str(PORT), "unowned"],
                capture_output=True, timeout=8)
            assert rejected.returncode != 0 and b"WireGuard" in rejected.stderr, rejected.stderr.decode()
            assert before == run(execute + ["iptables", "-w", "-S"]) and \
                not (state_root / "fail2ban-control.state").exists(), "dummy 接口预检写入控制资源"
            ws_unchanged()
        finally:
            if dummy:
                run(execute + ["ip", "link", "delete", "wg-padm"])
            run(execute + ["ip", "link", "set", "wg-fixture", "name", "wg-padm"])
        run(execute + ["sh", "/usr/local/bin/padm-entrypoint",
                       "preflight", "fail2ban-control", TARGET, str(PORT), "unowned"])
        jail = create([*net_args, "--entrypoint", "sh", inputs["net"]["reference"],
                       "/usr/local/bin/padm-entrypoint", "fail2ban-control", TARGET, str(PORT)])
        actual = json.loads(run(docker + ["inspect", jail]))[0]
        assert actual["Config"]["User"] == "0:10001" and actual["HostConfig"]["CapDrop"] == ["ALL"]
        assert [cap.removeprefix("CAP_") for cap in actual["HostConfig"]["CapAdd"]] == ["NET_ADMIN"]
        assert not actual["HostConfig"]["Privileged"] and actual["HostConfig"]["ReadonlyRootfs"]
        jail_exec = docker + ["exec", jail]

        def ready():
            result = subprocess.run(jail_exec + ["fail2ban-client", "status", "padm-control"],
                                    capture_output=True, timeout=3)
            return result.returncode == 0

        def bans():
            result = json.loads(run(jail_exec + ["python3", "-c",
                "import json; from fail2ban.client.csocket import CSocket; "
                "s=CSocket('/run/fail2ban/fail2ban.sock'); r=s.send(['get','padm-control','banip']); "
                "s.close(); print(json.dumps(r))"]))
            assert result[0] == 0, result
            return set(result[1])

        wait_ready(ready, "真实控制 Fail2ban jail 未就绪")
        assert not bans(), "负例或 nonce 回执提前触发封禁"
        owner = state_root / "fail2ban-control.state"
        wait_ready(owner.exists, "独立控制 owner 未写入")
        original_owner = owner.read_bytes()
        token = re.search(rb"^token=([a-f0-9]{32})$", original_owner, re.M).group(1).decode()
        chain, comment = "padm-f2bc-" + token[:12], "padm-f2bc:" + token
        expected_hook = ["-A", "INPUT", "-d", TARGET + "/32", "-p", "tcp", "-m", "tcp",
                         "--dport", str(PORT), "-m", "conntrack", "--ctstate", "NEW",
                         "-m", "comment", "--comment", comment, "-j", chain]
        hooks = [shlex.split(line) for line in run(execute + ["iptables", "-w", "-S"]).decode().splitlines()
                 if line.startswith("-A INPUT ") and chain in line]
        assert hooks == [expected_hook], "控制 INPUT hook 未精确绑定目标、TCP 端口与 NEW"
        assert run(jail_exec + ["sh", "/usr/local/bin/padm-entrypoint", "fail2ban-control-health"]) == b""
        rules_before = run(execute + ["iptables", "-w", "-S"])
        for mutation in ("uid", "token"):
            if mutation == "uid":
                os.chown(owner, 10001, 10001)
            else:
                owner.write_bytes(original_owner.replace(token.encode(), b"f" * 32))
            rejected = subprocess.run(jail_exec + ["sh", "/usr/local/bin/padm-entrypoint",
                "fail2ban-control-action", "ban", token, "iptables", "-w", "10.231.0.9"],
                capture_output=True, timeout=8)
            assert rejected.returncode != 0 and run(execute + ["iptables", "-w", "-S"]) == rules_before, \
                "被替换 owner 被接受或改变内核规则"
            os.chown(owner, 0, 10001)
            owner.write_bytes(original_owner)
        ws_unchanged()

        for _ in range(3):
            if PEER in bans():
                break
            assert client(controlled).get("status") == 401
            time.sleep(0.2)
        wait_ready(lambda: bans() == {PEER}, "真实 Peer 401 未达到 retry 封禁")
        rules = run(execute + ["iptables-save", "-c"]).decode()
        drop = next(line for line in rules.splitlines() if "padm-f2bc-" in line and
                    f"-s {PEER}/32" in line and "-j DROP" in line)
        count = int(drop.split(":", 1)[0].lstrip("["))
        log_before = auth.read_bytes()
        assert client(controlled, mode="authorized") == {"timeout": True}
        dropped = run(execute + ["iptables-save", "-c"]).decode()
        new_drop = next(line for line in dropped.splitlines() if "padm-f2bc-" in line and
                        f"-s {PEER}/32" in line and "-j DROP" in line)
        assert int(new_drop.split(":", 1)[0].lstrip("[")) > count, "封禁未命中真实 INPUT DROP"
        assert auth.read_bytes() == log_before, "被封请求仍进入生产 API"
        for address, port in ((OTHER_TARGET, PORT), (TARGET, PORT + 1)):
            assert client(controlled, address, port) == {"status": 401}, "封禁误伤另一目标或端口"
        ws_unchanged()

        def terminate():
            run(docker + ["stop", "--time", "10", jail], timeout=20)
            assert json.loads(run(docker + ["inspect", jail]))[0]["State"]["ExitCode"] == 0
            assert not owner.exists()
            assert b"padm-f2bc" not in run(execute + ["iptables", "-w", "-S"])
            ws_unchanged()
            database = state_root / "control-fail2ban.sqlite3"
            assert database.is_file() and database.stat().st_size > 0
            digest = hashlib.sha256(database.read_bytes()).digest()
            run(execute + ["sh", "/usr/local/bin/padm-entrypoint",
                           "preflight", "fail2ban-control", TARGET, str(PORT), "unowned"])
            assert hashlib.sha256(database.read_bytes()).digest() == digest

        terminate()
        assert client(controlled, mode="authorized") == {"status": 200}
        run(docker + ["start", jail])
        wait_ready(ready, "真实控制 jail 重启未就绪")
        wait_ready(lambda: bans() == {PEER}, "独立 SQLite 未恢复控制封禁")
        restored_owner = owner.read_bytes()
        assert restored_owner != original_owner
        jails = json.loads(run(jail_exec + ["python3", "-c",
            "import json,sqlite3; c=sqlite3.connect('/var/lib/padm/net/control-fail2ban.sqlite3'); "
            "print(json.dumps(c.execute('select name from jails').fetchall())); c.close()"]))
        assert jails == [["padm-control"]], "控制数据库混入其它 scope"
        ws_unchanged()
        run(jail_exec + ["fail2ban-client", "set", "padm-control", "unbanip", PEER])
        wait_ready(lambda: not bans(), "真实解封未完成")
        assert client(controlled, mode="authorized") == {"status": 200}
        terminate()
        run(execute + ["sh", "-eu", "-c", '. /test/net-functions.sh; fail2ban_cleanup "' + WS_TOKEN + '"'])
        assert not (state_root / "fail2ban.state").exists()
        assert b"padm-f2b" not in run(execute + ["iptables", "-w", "-S"])
        print("docker-control-fail2ban-real-proof=" + json.dumps({
            "scope": "real-ipv4-input-action-jail-only", "netns": [
                os.readlink(f"/proc/{pid}/ns/net") for pid in (controller, controlled)],
            "api_uid": 10001, "net_uid_gid": "0:10001", "net_cap_add": ["NET_ADMIN"],
            "other_target_endpoint": "stdlib-http-negative-only",
            "filter_negative_matrix": "passed", "peer_401_input_drop_counter": "passed",
            "wireguard_kind_preflight_and_exact_new_hook": "passed",
            "target_port_and_ws_isolation": "passed", "owner_replacement": "passed",
            "sqlite_scope_restart_unban_term": "passed", "elapsed": round(time.monotonic() - started, 3),
        }, sort_keys=True), flush=True)
    finally:
        failed = sys.exc_info()[0] is not None
        cleanup_failed = False
        if docker is not None:
            for container in reversed(containers):
                if failed:
                    try:
                        result = subprocess.run(docker + ["logs", container], capture_output=True, timeout=5)
                        print((result.stdout + result.stderr).decode(errors="replace")[-4000:], file=sys.stderr)
                    except subprocess.TimeoutExpired as error:
                        print(str(error), file=sys.stderr)
                try:
                    result = subprocess.run(docker + ["rm", "--force", container], capture_output=True, timeout=10)
                    if result.returncode:
                        cleanup_failed = True
                        print((result.stdout + result.stderr).decode(errors="replace"), file=sys.stderr)
                except subprocess.TimeoutExpired as error:
                    cleanup_failed = True
                    print(str(error), file=sys.stderr)
        if daemon is not None:
            stop(daemon)
            if failed:
                print((work / "daemon.log").read_text(errors="replace")[-4000:], file=sys.stderr)
        for holder in reversed(holders):
            stop(holder)
        mounts = [line.split()[4] for line in Path("/proc/self/mountinfo").read_text().splitlines()
                  if line.split()[4].startswith(str(work) + "/")]
        for mount in sorted(mounts, key=lambda value: value.count("/"), reverse=True):
            run(["umount", "--lazy", "--", mount], timeout=5)
        assert work.parent == Path("/n") and work.name.startswith(".tmp-control-fail2ban-")
        shutil.rmtree(work)
        assert {item["ifname"] for item in json.loads(run(["ip", "-j", "link"]))} == {"lo"}
        if cleanup_failed and not failed:
            raise AssertionError("本轮容器清理失败，原始错误已输出")
    print("docker-control-fail2ban-real-regression-ok")


if __name__ == "__main__":
    if sys.argv[1:2] == ["--request"]:
        print(json.dumps(request(*sys.argv[2:5])))
    elif sys.argv[1:2] == ["--other-api"]:
        other_target_api(Path(sys.argv[2]))
    else:
        main()
