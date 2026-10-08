#!/usr/bin/env python3
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDRESS = ("10.231.0.1", "10.231.0.2")


def diagnostic(node, output):
    for path in (node["path"] / "private").glob("*.json"):
        value = json.loads(path.read_text()).get("token")
        if isinstance(value, str):
            output = output.replace(value, "[已隐藏]")
    for spec in (node["path"] / "spec.json", node["path"] / "deployment/config/spec.json"):
        if spec.is_file():
            value = json.loads(spec.read_text())
            for account in value.get("accounts", []):
                for key in ("uuid", "password", "shadowsocks_password"):
                    credential = account.get(key)
                    if isinstance(credential, str):
                        output = output.replace(credential, "[已隐藏]")
            for entry in value["core"]["protocols"]:
                output = output.replace(entry["uuid"], "[已隐藏]")
    key = node["path"] / "secrets/net/wireguard/wg-padm.conf"
    if key.is_file():
        for value in re.findall(r"PrivateKey\s*=\s*(\S+)", key.read_text()):
            output = output.replace(value, "[已隐藏]")
    return re.sub(r"-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----",
                  "[已隐藏私钥]", output, flags=re.S)


def command(arguments, *, content=None, timeout=30):
    result = subprocess.run(arguments, input=content, capture_output=True, timeout=timeout)
    if result.returncode:
        raise AssertionError(
            f"{arguments[0]} 退出码 {result.returncode}："
            + result.stderr.decode(errors="replace").strip()
        )
    return result.stdout


def stop(process):
    if process.poll() is None:
        process.terminate()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def identity(number):
    return f"{number:08d}-1111-4111-8111-{number:012d}"


def save(path, value):
    path.write_text(json.dumps(value), encoding="ascii")
    path.chmod(0o600)


def enter(pid):
    return ["nsenter", "--target", str(pid), "--mount", "--net", "--pid", "--"]


def cli(node, *arguments, accepted=True):
    started = time.monotonic()
    try:
        result = subprocess.run(
            node["enter"] + ["bash", str(node["path"] / "bin/padm-docker"), *arguments],
            env=node["env"], capture_output=True, timeout=180,
        )
    except subprocess.TimeoutExpired as error:
        with (node["path"] / "cli.log").open("ab") as output:
            output.write((error.stdout or b"") + (error.stderr or b""))
        raise AssertionError("真实 CLI 超时：" + diagnostic(
            node, (error.stderr or b"").decode(errors="replace"))) from error
    with (node["path"] / "cli.log").open("ab") as output:
        output.write(result.stdout + result.stderr)
    print(f"docker-control-two-deployment-cli:{node['path'].name}:{':'.join(arguments[:2])}:"
          f"rc={result.returncode}:elapsed={time.monotonic()-started:.3f}s", flush=True)
    if accepted:
        assert result.returncode == 0, diagnostic(node, result.stdout.decode() + result.stderr.decode())
    else:
        assert result.returncode != 0, "异常真实 CLI 未拒绝"
    return result


def state(node):
    return json.loads((node["path"] / "deployment/config/spec.json").read_text())


def services(node):
    rows = command(node["docker"] + ["ps", "--all", "--filter", "label=com.docker.compose.project=padm-docker",
                                     "--format", "{{json .}}"]).splitlines()
    result = {}
    for row in rows:
        container = json.loads(row)["ID"]
        inspected = json.loads(command(node["docker"] + ["inspect", container]))[0]
        assert inspected["State"]["Running"]
        assert inspected["State"]["Health"]["Status"] == "healthy"
        assert inspected["HostConfig"]["ReadonlyRootfs"]
        assert inspected["HostConfig"]["CapDrop"] == ["ALL"]
        assert not inspected["HostConfig"]["Privileged"]
        service = inspected["Config"]["Labels"]["com.docker.compose.service"]
        if service == "net-wireguard":
            assert [cap.removeprefix("CAP_") for cap in inspected["HostConfig"]["CapAdd"]] == ["NET_ADMIN"]
        else:
            assert not inspected["HostConfig"]["CapAdd"]
        if service in ("net-wireguard", "control"):
            assert inspected["HostConfig"]["NetworkMode"] == "host"
            assert not inspected["HostConfig"]["PortBindings"]
            child_ns = command(node["docker"] + ["exec", container, "readlink", "/proc/self/ns/net"]).decode().strip()
            assert child_ns == os.readlink(f"/proc/{node['pid']}/ns/net")
        result[service] = {"id": inspected["Id"], "started_at": inspected["State"]["StartedAt"]}
    assert {"xray", "nginx", "net-wireguard"} <= result.keys()
    current = state(node)
    config = json.loads((node["path"] / "deployment/config/xray/config.json").read_text())
    clients = next(inbound["settings"]["clients"] for inbound in config["inbounds"]
                   if inbound["tag"] == "entry-ws")
    expected = [{"id": current["core"]["protocols"][0]["uuid"],
                 "email": current["core"]["protocols"][0]["uuid"]}]
    expected += [{"id": account["uuid"], "email": account["id"]} for account in current["accounts"]
                 if account["enabled"]]
    assert sorted(clients, key=lambda value: value["email"]) == sorted(expected, key=lambda value: value["email"]), \
        "真实核心账号与已提交规格不一致"
    return result


def reachable(node, invitation):
    connection = json.loads(invitation.read_text())["listen"]
    output = command(node["enter"] + [
        "curl", "-sS", "--noproxy", "*", "--interface", ADDRESS[1], "--max-time", "5",
        "--retry", "4", "--retry-all-errors", "--retry-delay", "1",
        f"http://{connection['address']}:{connection['port']}/v1/health",
    ], timeout=35)
    assert json.loads(output) == {"ok": False, "error": "unauthorized"}


def unauthorized(node, invitation):
    result = command(node["enter"] + ["python3", "-c", """
import http.client, json, sys
invite = json.load(open(sys.argv[1]))
connection = http.client.HTTPConnection(
    invite["listen"]["address"], invite["listen"]["port"], timeout=5,
    source_address=(invite["peer_address"], 0))
try:
    connection.request("GET", "/v1/desired", headers={
        "Authorization": "Bearer " + invite["token"], "X-Padm-Control-Version": "1"})
    response = connection.getresponse()
    assert response.status == 401
    assert json.loads(response.read()) == {"ok": False, "error": "unauthorized"}
finally:
    connection.close()
""", str(invitation)], timeout=8)
    assert not result


def interrupted_sync(node, invitation, number=None):
    before = state(node)
    previous = services(node)["xray"]["id"]
    root = node["path"] / "deployment"
    originals = {path: path.read_bytes() for path in (
        root / "config/xray/config.json", root / "deployment.json", root / "compose.json", root / "images.env",
    )}
    started = time.monotonic()
    # 主控重建后先确认隧道已重新握手，再把故障注入限定到应用事务。
    reachable(node, invitation)
    with (node["path"] / "cli.log").open("ab") as output:
        process = subprocess.Popen(
            node["enter"] + ["setsid", "--wait", "--", "bash", str(node["path"] / "bin/padm-docker"),
                             "control", "sync", "--invite", str(invitation)],
            env=node["env"], stdout=output, stderr=subprocess.STDOUT, start_new_session=True,
        )
        transaction_pid = None
        try:
            deadline = time.monotonic() + 150
            while True:
                assert process.poll() is None, "真实切换前 CLI 已退出：" + diagnostic(
                    node, (node["path"] / "cli.log").read_text(errors="replace")[-4000:])
                rows = command(node["docker"] + [
                    "ps", "--no-trunc", "--quiet",
                    "--filter", "label=com.docker.compose.project=padm-docker",
                    "--filter", "label=com.docker.compose.service=xray",
                ]).decode().split()
                new = None
                for container in rows:
                    if container == previous:
                        continue
                    actual = json.loads(command(node["docker"] + ["inspect", container]))[0]
                    if actual["State"]["Running"] and actual["Name"] == "/padm-docker-xray-1":
                        new = container
                        break
                if new:
                    actual = json.loads(command(node["docker"] + ["inspect", new]))[0]
                    assert actual["Config"]["Labels"]["io.padm.component"] == "xray"
                    assert actual["State"]["Running"] and \
                        state(node)["control_sync"]["last_revision"] > before["control_sync"]["last_revision"]
                    children = Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().split()
                    assert len(children) == 1
                    transaction_pid = int(children[0])
                    if os.getpgid(transaction_pid) != transaction_pid:
                        children = Path(f"/proc/{transaction_pid}/task/{transaction_pid}/children").read_text().split()
                        assert len(children) == 1
                        transaction_pid = int(children[0])
                    assert os.getpgid(transaction_pid) == transaction_pid and transaction_pid != process.pid
                    command(node["docker"] + ["pause", new])
                    if number is not None:
                        os.killpg(transaction_pid, number)
                    break
                assert time.monotonic() < deadline, "未观察到真实候选核心启动"
                time.sleep(0.1)
            status = process.wait(timeout=150)
            assert status == (14 if number is None else 128 + number), f"真实失败恢复退出码异常：{status}"
        finally:
            if transaction_pid is not None:
                try:
                    os.killpg(transaction_pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
    assert state(node) == before, "真实同步失败未恢复原规格"
    assert all(path.read_bytes() == content for path, content in originals.items()), "真实同步失败未恢复部署文件"
    services(node)
    assert not list(root.glob(".candidate.*")) and not list(root.glob(".control-client.*"))
    assert not (root / "locks/deployment.lock").exists()
    label = "health" if number is None else signal.Signals(number).name
    print(f"docker-control-two-deployment-restore:{label}:elapsed={time.monotonic()-started:.3f}s", flush=True)


def traffic(node, image):
    path = node["path"] / "client"
    path.mkdir(mode=0o755)
    current = state(node)
    domain = current["tls"]["domain"]
    (path / "ca.crt").write_bytes((node["path"] / "secrets/tls" / f"{domain}.crt").read_bytes())
    config = {
        "inbounds": [{"type": "socks", "listen": "127.0.0.1", "listen_port": 1080}],
        "outbounds": [{
            "type": "vless", "server": "127.0.0.1", "server_port": 35466,
            "uuid": current["accounts"][0]["uuid"],
            "tls": {"enabled": True, "server_name": domain, "certificate_path": "/input/ca.crt"},
            "transport": {"type": "ws", "path": "/control-testws", "headers": {"Host": domain}},
        }],
    }
    save(path / "config.json", config)
    (path / "config.json").chmod(0o644)
    server = subprocess.Popen(node["enter"] + ["python3", "-c", """
from http.server import BaseHTTPRequestHandler, HTTPServer
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"padm-real-control-traffic\\n" * 2048
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *arguments):
        pass
HTTPServer(("0.0.0.0", 38999), Handler).serve_forever()
"""], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    client = None
    try:
        client = command(node["docker"] + [
            "run", "-d", "--network", "host", "--read-only", "--cap-drop", "ALL",
            "--security-opt", "no-new-privileges:true", "--user", "10001:10001",
            "--mount", f"type=bind,src={path},dst=/input,readonly",
            "--tmpfs", "/tmp:rw,noexec,nosuid,nodev,size=16m",
            image, "run", "-c", "/input/config.json",
        ]).decode().strip()
        deadline = time.monotonic() + 10
        while True:
            result = subprocess.run(node["enter"] + [
                "curl", "-fsS", "--max-time", "3", "--noproxy", "",
                "--socks5-hostname", "127.0.0.1:1080", "http://172.31.0.1:38999/proof",
            ], capture_output=True, timeout=5)
            if not result.returncode:
                assert result.stdout == b"padm-real-control-traffic\n" * 2048
                break
            if time.monotonic() >= deadline:
                raise AssertionError(result.stderr.decode() +
                                     command(node["docker"] + ["logs", client]).decode())
            time.sleep(0.1)
        cli(node, "traffic", "collect")
        ledger = json.loads((node["path"] / "deployment/data/traffic/state.json").read_text())
        totals = ledger["accounts"][current["accounts"][0]["id"]]
        assert totals["upload"] > 0 and totals["download"] >= len(result.stdout)
        assert totals["baseline"]["xray"], "真实流量采集缺少核心基线"
        print("docker-control-two-deployment-real-traffic-ok", flush=True)
        return totals
    finally:
        if client:
            command(node["docker"] + ["rm", "--force", client])
        stop(server)


def main():
    assert os.getuid() == 0 and Path("/.dockerenv").is_file(), "仅在隔离 Linux 测试容器运行"
    assert [link["ifname"] for link in json.loads(command(["ip", "-j", "link"]))] == ["lo"], \
        "测试不得使用宿主或外部网络"
    archive = Path("/node-images.tar")
    assert archive.is_file(), "缺少离线镜像归档"
    inputs = json.loads(Path("/node-images.json").read_text(encoding="utf-8-sig"))
    images = {name: value["reference"] for name, value in inputs.items()}
    holders, daemons, crons, nodes, seeds = [], [], [], [], []
    proofs = []
    names = ["pn" + uuid.uuid4().hex[:10] for _ in range(2)]
    with tempfile.TemporaryDirectory(prefix=".tmp-control-deploy-", dir="/n") as directory:
        root = Path(directory)
        root.chmod(0o700)
        try:
            for index, role in enumerate(("controller", "controlled")):
                node = root / role
                node.mkdir(mode=0o700)
                for relative in ("run", "cron", "cron.d", "bin", "home", "tmp", "private", "secrets/tls",
                                 "secrets/net/wireguard"):
                    (node / relative).mkdir(parents=True, mode=0o700)
                holder = subprocess.Popen(
                    ["unshare", "--net", "--mount", "--propagation", "private", "--pid", "--fork", "--kill-child",
                     "--mount-proc", "--", "sleep", "3600"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                )
                holders.append(holder)
                deadline = time.monotonic() + 5
                while True:
                    assert holder.poll() is None, "节点隔离进程失败"
                    children = Path(f"/proc/{holder.pid}/task/{holder.pid}/children").read_text().split()
                    if children:
                        pid = int(children[0])
                        if os.readlink(f"/proc/{pid}/ns/net") != os.readlink("/proc/self/ns/net"):
                            break
                    assert time.monotonic() < deadline, "节点网络空间创建超时"
                    time.sleep(0.02)
                ns = enter(pid)
                for source, target in (("run", "/run"), ("cron", "/var/spool/cron/crontabs"),
                                       ("cron.d", "/etc/cron.d")):
                    command(ns + ["mount", "--bind", str(node / source), target])
                command(ns + ["ip", "link", "set", "lo", "up"])
                with (node / "cron.log").open("wb") as output:
                    cron = subprocess.Popen(ns + ["cron", "-f"], stdout=output, stderr=subprocess.STDOUT)
                crons.append(cron)
                socket = f"unix://{node}/docker.sock"
                with (node / "daemon.log").open("wb") as output:
                    daemon = subprocess.Popen(
                        ns + ["dockerd", "--host", socket, "--host", "unix:///run/docker.sock",
                              "--data-root", str(node / "docker"),
                              "--exec-root", str(node / "run/docker"), "--pidfile", str(node / "run/daemon.pid"),
                              "--feature", "containerd-snapshotter=true", "--storage-driver", "overlayfs",
                              "--bip", "172.31.0.1/24"],
                        stdout=output, stderr=subprocess.STDOUT,
                    )
                daemons.append(daemon)
                client = ns + ["docker", "--host", socket]
                deadline = time.monotonic() + 20
                while True:
                    if daemon.poll() is not None:
                        raise AssertionError((node / "daemon.log").read_text())
                    try:
                        result = subprocess.run(
                            client + ["info", "--format", "{{json .}}"], capture_output=True, timeout=3,
                        )
                    except subprocess.TimeoutExpired:
                        assert time.monotonic() < deadline, (node / "daemon.log").read_text()
                        continue
                    if not result.returncode:
                        break
                    assert time.monotonic() < deadline, "隔离 daemon 启动超时"
                    time.sleep(0.1)
                info = json.loads(result.stdout)
                assert info["OSType"] == "linux" and "name=rootless" not in info["SecurityOptions"]
                command(client + ["load", "--input", str(archive)], timeout=120)
                for name, item in inputs.items():
                    actual = json.loads(command(client + ["image", "inspect", item["reference"]]))[0]
                    assert actual["Id"] == item["image_id"], f"离线 {name} 镜像内容失配"
                env = os.environ | {
                    "DOCKER_HOST": socket, "PADM_DOCKER_INSTALL_DIR": str(node / "deployment"),
                    "PADM_DOCKER_BIN_DIR": str(node / "bin"), "HOME": str(node / "home"),
                    "TMPDIR": str(node / "tmp"), "PYTHONDONTWRITEBYTECODE": "1",
                    "PADM_DOCKER_HEALTH_TIMEOUT": "8",
                }
                nodes.append({"path": node, "pid": pid, "enter": ns, "docker": client, "env": env})
                proofs.append({"role": role, "engine_id": info["ID"],
                               "netns": os.readlink(f"/proc/{pid}/ns/net")})
            assert proofs[0]["engine_id"] != proofs[1]["engine_id"]
            assert proofs[0]["netns"] != proofs[1]["netns"]
            command(["ip", "link", "add", names[0], "type", "veth", "peer", "name", names[1]])
            keys, public = [], []
            for index, node in enumerate(nodes):
                command(["ip", "link", "set", names[index], "netns", str(node["pid"])])
                command(node["enter"] + ["ip", "link", "set", names[index], "name", "underlay"])
                command(node["enter"] + ["ip", "address", "add", f"192.0.2.{index + 1}/30",
                                         "dev", "underlay"])
                command(node["enter"] + ["ip", "link", "set", "underlay", "up"])
                key = command(["wg", "genkey"])
                keys.append(key.decode().strip())
                public.append(command(["wg", "pubkey"], content=key).decode().strip())
            for index, node in enumerate(nodes):
                path = node["path"]
                domain = f"node-{index}.padm.test"
                certificate = path / "secrets/tls" / f"{domain}.crt"
                private = path / "secrets/tls" / f"{domain}.key"
                command(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2",
                         "-subj", f"/CN={domain}", "-addext", f"subjectAltName=DNS:{domain}",
                         "-keyout", str(private), "-out", str(certificate)])
                private.chmod(0o600)
                certificate.chmod(0o600)
                configuration = path / "secrets/net/wireguard/wg-padm.conf"
                configuration.write_text(
                    f"[Interface]\nPrivateKey = {keys[index]}\nAddress = {ADDRESS[index]}/32\n"
                    f"ListenPort = 51820\n[Peer]\nPublicKey = {public[1-index]}\n"
                    f"AllowedIPs = {ADDRESS[1-index]}/32\nEndpoint = 192.0.2.{2-index}:51820\n"
                    "PersistentKeepalive = 1\n"
                )
                configuration.chmod(0o600)
                spec = {
                    "schema_version": 3,
                    "release": {"version": "3.15.0", "manifest_sha256": "1" * 64,
                                "signature_identity": "local-test-only-not-release-verified"},
                    "core": {"type": "xray", "secondary_type": None, "protocols": [{
                        "id": 21, "core": "xray", "listener_id": "entry-ws", "server": domain,
                        "public_port": 35466, "address_families": ["ipv4"], "name": "vless-ws",
                        "uuid": identity(index + 10), "websocket": {
                            "domain": domain, "path": "control-test",
                            "backend_port": 31297, "tls_port": 8443,
                        },
                    }]},
                    "tls": {"domain": domain}, "subscription": {"enabled": False, "token": "0" * 16},
                    "images": images,
                    "host_integrations": [{
                        "type": "wireguard", "profile": "net-wireguard", "firewall_rules": [],
                        "devices": ["wg-padm"], "schedules": [],
                        "settings": {"config_file": "wg-padm.conf", "interface": "wg-padm"},
                    }],
                    "accounts": [{
                        "id": identity(index + 20), "name": "local-account", "enabled": True,
                        "uuid": identity(index + 30), "password": f"Local.-~@+=:Secret:{index}",
                        "shadowsocks_password": None, "listeners": ["entry-ws"],
                    }],
                }
                save(path / "spec.json", spec)
                process = subprocess.Popen(
                    node["enter"] + ["bash", str(ROOT / "docker/tests/control-deployment-node.sh"),
                                     str(path)],
                    env=node["env"], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                )
                seeds.append((process, node, spec))
            for index, (process, node, spec) in enumerate(seeds):
                path = node["path"]
                stdout, stderr = process.communicate(timeout=180)
                result = subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)
                (path / "seed.log").write_bytes(result.stdout + result.stderr)
                if result.returncode:
                    output = result.stderr.decode(errors="replace")
                    private_log = path / "seed-private.log"
                    if private_log.is_file():
                        output += private_log.read_text(errors="replace")
                    for member in nodes:
                        output = diagnostic(member, output)
                    raise AssertionError(output[-6000:])
                output = command(node["docker"] + ["ps", "--format", "{{json .}}"])
                assert b"healthy" in output, "真实部署服务未通过健康检查"
                print(f"docker-control-two-deployment-seed-ok:{proofs[index]['role']}", flush=True)
            controller, controlled = nodes
            original_local = state(controlled)["accounts"][0]
            cli(controller, "control", "init", "--address", ADDRESS[0], "--port", "39778",
                "--peer-address", ADDRESS[1], "--yes")
            initial_services = services(controller)
            assert "control" in initial_services
            invite = controller["path"] / "private/invite.json"
            cli(controller, "control", "invite", "--output", str(invite), "--yes")
            controlled_invite = controlled["path"] / "private/invite.json"
            save(controlled_invite, json.loads(invite.read_text()))
            cli(controlled, "control", "join", "--invite", str(controlled_invite),
                "--listener", "entry-ws", "--yes")
            joined = state(controlled)
            assert joined["accounts"][0] == original_local
            assert joined["control_sync"]["last_revision"] == state(controller)["control"]["revision"]
            before_services = services(controlled)
            assert set(before_services) == {"xray", "nginx", "net-wireguard"}
            cli(controlled, "control", "sync", "--invite", str(controlled_invite))
            assert services(controlled) == before_services, "真实幂等同步重建了服务"
            assert state(controlled) == joined
            print("docker-control-two-deployment-join-idempotency-ok", flush=True)
            traffic_before = traffic(controlled, images["sing-box"])
            command(controlled["enter"] + ["ip", "route", "replace", ADDRESS[0] + "/32", "dev", "underlay"])
            cli(controlled, "control", "sync", "--invite", str(controlled_invite), accepted=False)
            command(controlled["enter"] + ["ip", "route", "replace", ADDRESS[0] + "/32",
                                           "dev", "wg-padm", "src", ADDRESS[1]])
            alias = json.loads(command(controlled["enter"] + ["ip", "-d", "-j", "link", "show", "wg-padm"]))[
                0]["ifalias"]
            command(controlled["enter"] + ["ip", "link", "set", "wg-padm", "alias", "outside-owner"])
            cli(controlled, "control", "sync", "--invite", str(controlled_invite), accepted=False)
            command(controlled["enter"] + ["ip", "link", "set", "wg-padm", "alias", alias])
            assert state(controlled) == joined and services(controlled) == before_services
            command(controlled["enter"] + ["ip", "link", "set", "underlay", "down"])
            started = time.monotonic()
            cli(controlled, "control", "sync", "--invite", str(controlled_invite), accepted=False)
            assert time.monotonic() - started < 20, "真实断网同步超出总时限"
            assert state(controlled) == joined and services(controlled) == before_services
            command(controlled["enter"] + ["ip", "link", "set", "underlay", "up"])
            cli(controlled, "control", "sync", "--invite", str(controlled_invite))
            assert state(controlled) == joined and services(controlled) == before_services
            upstream_path = controller["path"] / "deployment/config/control/state.json"
            upstream = upstream_path.read_bytes()
            try:
                conflict = json.loads(upstream)
                conflict["accounts"][0]["name"] = "same-version-conflict"
                upstream_path.write_text(json.dumps(conflict), encoding="ascii")
                cli(controlled, "control", "sync", "--invite", str(controlled_invite), accepted=False)
                assert state(controlled) == joined and services(controlled) == before_services
                conflict = json.loads(upstream)
                conflict["revision"] -= 1
                upstream_path.write_text(json.dumps(conflict), encoding="ascii")
                cli(controlled, "control", "sync", "--invite", str(controlled_invite), accepted=False)
                assert state(controlled) == joined and services(controlled) == before_services
            finally:
                upstream_path.write_bytes(upstream)
            cli(controlled, "control", "sync", "--invite", str(controlled_invite))
            assert state(controlled) == joined and services(controlled) == before_services
            print("docker-control-two-deployment-network-conflict-recovery-ok", flush=True)
            cli(controller, "account", "disable", identity(20))
            for number in (None, signal.SIGINT, signal.SIGTERM):
                interrupted_sync(controlled, controlled_invite, number)
            cli(controlled, "control", "sync", "--invite", str(controlled_invite))
            updated = state(controlled)
            assert updated["accounts"][0] == original_local
            assert updated["control_sync"]["last_revision"] > joined["control_sync"]["last_revision"]
            assert updated["accounts"][1]["enabled"] is False
            assert services(controlled)["xray"]["id"] != before_services["xray"]["id"]
            cli(controlled, "traffic", "collect")
            totals = json.loads((controlled["path"] / "deployment/data/traffic/state.json").read_text())[
                "accounts"][original_local["id"]]
            assert totals["upload"] >= traffic_before["upload"] and \
                totals["download"] >= traffic_before["download"] and \
                totals["limit_bytes"] == traffic_before["limit_bytes"]
            rotated = controller["path"] / "private/rotated.json"
            cli(controller, "control", "invite", "--output", str(rotated), "--yes")
            reachable(controlled, controlled_invite)
            unauthorized(controlled, controlled_invite)
            cli(controlled, "control", "sync", "--invite", str(controlled_invite), accepted=False)
            assert state(controlled) == updated
            save(controlled_invite, json.loads(rotated.read_text()))
            cli(controlled, "control", "sync", "--invite", str(controlled_invite))
            assert state(controlled) == updated
            cli(controller, "control", "revoke", "--yes")
            reachable(controlled, controlled_invite)
            unauthorized(controlled, controlled_invite)
            cli(controlled, "control", "sync", "--invite", str(controlled_invite), accepted=False)
            assert state(controlled) == updated
            services(controller)
            services(controlled)
            for node in nodes:
                assert not list((node["path"] / "deployment").glob(".candidate.*"))
                assert not list((node["path"] / "deployment").glob(".control-client.*"))
            for node in nodes:
                logs = (node["path"] / "cli.log").read_bytes()
                logs += (node["path"] / "seed.log").read_bytes()
                logs += (node["path"] / "seed-private.log").read_bytes()
                for service, item in services(node).items():
                    logs += command(node["docker"] + ["logs", item["id"]])
                secrets = [json.loads(path.read_text())["token"] for path in (invite, rotated)]
                secrets += keys
                for member in nodes:
                    for spec in (json.loads((member["path"] / "spec.json").read_text()), state(member)):
                        for account in spec["accounts"]:
                            secrets += [value for name in ("uuid", "password", "shadowsocks_password")
                                        if isinstance(value := account[name], str)]
                        secrets += [entry["uuid"] for entry in spec["core"]["protocols"]]
                    secrets += [(member["path"] / "secrets/tls" /
                                 f"{state(member)['tls']['domain']}.key").read_text().strip()]
                assert all(secret.encode() not in logs for secret in secrets), "真实 CLI 日志泄露秘密"
            proofs[0]["scope"] = "real-compose-control-transactions-from-installed-fixture"
            print("docker-control-two-deployment-sync-rotation-revoke-ok", flush=True)
        finally:
            failed = sys.exc_info()[0] is not None
            cleanup_errors = []
            for node in reversed(nodes):
                try:
                    containers = command(node["docker"] + ["ps", "--all", "--quiet"]).decode().split()
                    if containers:
                        command(node["docker"] + ["rm", "--force", *containers], timeout=30)
                except Exception as error:
                    cleanup_errors.append(f"节点 {node['path'].name} 容器：{type(error).__name__}")
            for process in reversed(daemons + crons + holders):
                try:
                    stop(process)
                except Exception as error:
                    cleanup_errors.append(f"节点进程 {process.pid}：{type(error).__name__}")
            for process, node, _ in seeds:
                try:
                    stop(process)
                except Exception as error:
                    cleanup_errors.append(f"节点 {node['path'].name} seed：{type(error).__name__}")
                for stream in (process.stdout, process.stderr):
                    if stream is not None:
                        try:
                            stream.close()
                        except Exception as error:
                            cleanup_errors.append(f"节点 {node['path'].name} seed 管道：{type(error).__name__}")
            try:
                deadline = time.monotonic() + 5
                while any(Path(f"/proc/{node['pid']}/ns/net").exists() for node in nodes):
                    assert time.monotonic() < deadline, "节点网络空间未清理"
                    time.sleep(0.02)
            except Exception as error:
                cleanup_errors.append(f"节点网络空间：{type(error).__name__}")
            for name in names:
                try:
                    subprocess.run(["ip", "link", "delete", name], capture_output=True, timeout=3)
                except Exception as error:
                    cleanup_errors.append(f"节点链路 {name}：{type(error).__name__}")
            if cleanup_errors:
                print("节点环境清理诊断：" + "\n".join(cleanup_errors), file=sys.stderr)
                if not failed:
                    raise AssertionError("节点环境清理失败")
    print("docker-control-two-deployment-environment-proof=" + json.dumps(proofs, sort_keys=True))
    print("docker-control-two-deployment-environment-ok")


if __name__ == "__main__":
    main()
