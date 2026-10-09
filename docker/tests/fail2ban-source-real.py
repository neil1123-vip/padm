#!/usr/bin/env python3
import ipaddress
import json
import os
from pathlib import Path
import runpy
import selectors
import shutil
import socket
import ssl
import subprocess
import sys
import tempfile
import time


SCRIPT = Path(__file__).resolve()
ROOT = SCRIPT.parents[2]
helpers = runpy.run_path(str(SCRIPT.with_name("control-two-deployment-real.py")))
command, stop = (helpers[name] for name in ("command", "stop"))
PORT = 24444
HOST = {"ipv4": "198.18.2.1", "ipv6": "fd42:7061:646d:2::1"}
SOURCES = {
    "ipv4": ("198.18.2.2", "198.18.2.3"),
    "ipv6": ("fd42:7061:646d:2::2", "fd42:7061:646d:2::3"),
}


def wait_ready(probe, message, limit=15):
    deadline = time.monotonic() + limit
    while True:
        try:
            if probe():
                return
        except (OSError, AssertionError):
            pass
        assert time.monotonic() < deadline, message
        time.sleep(0.05)


def request(family, path, forged, port=PORT):
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    try:
        with socket.create_connection((HOST[family], int(port)), timeout=1) as stream:
            with context.wrap_socket(stream, server_hostname="source.padm.test") as tls:
                tls.sendall(
                    f"GET {path} HTTP/1.1\r\nHost: source.padm.test\r\n"
                    f"X-Forwarded-For: {forged}\r\nForwarded: for=\"{forged}\"\r\n"
                    "Connection: close\r\n\r\n".encode()
                )
                response = b""
                while b"\r\n" not in response:
                    part = tls.recv(1024)
                    assert part, "服务端在 HTTP 状态前关闭连接"
                    response += part
                    assert len(response) < 16384, "HTTP 响应头超限"
                return {"status": int(response.split(b" ", 2)[1])}
    except socket.timeout:
        return {"timeout": True}


def namespaces():
    processes = []
    try:
        for number in range(2):
            process = subprocess.Popen(["unshare", "--net", "--", "sleep", "180"])
            processes.append(process)
            wait_ready(lambda: Path(f"/proc/{process.pid}/ns/net").readlink() !=
                       Path("/proc/self/ns/net").readlink(), "客户端 netns 未隔离")
            enter = ["nsenter", "--target", str(process.pid), "--net", "--"]
            host, peer = f"fsh{number}", f"fsc{number}"
            command(["ip", "link", "add", host, "type", "veth", "peer", "name", peer])
            command(["ip", "link", "set", peer, "netns", str(process.pid)])
            command(["ip", "link", "set", host, "up"])
            command(enter + ["ip", "link", "set", "lo", "up"])
            command(enter + ["ip", "link", "set", peer, "up"])
            for family, prefix in (("ipv4", 32), ("ipv6", 128)):
                flags = [] if family == "ipv4" else ["-6"]
                gateway = HOST[family] if number == 0 else (
                    "198.18.2.4" if family == "ipv4" else "fd42:7061:646d:2::4")
                nodad = [] if family == "ipv4" else ["nodad"]
                command(["ip"] + flags + ["address", "add", f"{gateway}/{prefix}",
                                         "dev", host] + nodad)
                command(["ip"] + flags + ["route", "add", f"{SOURCES[family][number]}/{prefix}",
                                         "dev", host])
                command(enter + ["ip"] + flags + ["address", "add",
                        f"{SOURCES[family][number]}/{prefix}", "dev", peer] + nodad)
                command(enter + ["ip"] + flags + ["route", "add", f"{gateway}/{prefix}", "dev", peer])
                command(enter + ["ip"] + flags + ["route", "add", "default", "via", gateway,
                                                 "dev", peer])
            for scope in ("all", "default", peer):
                command(enter + ["sysctl", "-q", "-w", f"net.ipv4.conf.{scope}.rp_filter=0"])
        for scope in ("all", "default", "fsh0", "fsh1"):
            command(["sysctl", "-q", "-w", f"net.ipv4.conf.{scope}.rp_filter=0"])
        command(["sysctl", "-q", "-w", "net.ipv4.ip_forward=1"])
        command(["sysctl", "-q", "-w", "net.ipv6.conf.all.forwarding=1"])
        return processes
    except BaseException:
        for process in processes:
            stop(process)
        raise


def client(process, family, path="/", forged=None, port=PORT):
    return json.loads(command(
        ["nsenter", "--target", str(process.pid), "--net", "--", "python3", str(SCRIPT),
         "client", family, path, forged or SOURCES[family][1], str(port)], timeout=5))


def inspect(docker, identity):
    return json.loads(command(docker + ["inspect", identity]))[0]


def witness(docker, identity, client_processes, family, listener, port, internal_port,
            reject=None, history_uri=None):
    # 离线编排改写了镜像身份，只替换容器审计；挑战、真实日志与来源匹配仍执行生产函数。
    script = r'''
source "$1"
dockerFail2banSourceContainer() {
    [[ "$1" == "$PADM_TEST_SOURCE_LISTENER" && "$2" == "$PADM_TEST_SOURCE_FAMILY" ]] || return 1
    docker inspect "$PADM_TEST_SOURCE_CONTAINER" | jq -ce \
      --argjson public "$PADM_TEST_SOURCE_PORT" --argjson internal "$PADM_TEST_SOURCE_INTERNAL" \
      --argjson hosts "$PADM_TEST_SOURCE_HOSTS" '
      select(length == 1) | .[0] |
      select(.State.Running == true and .State.Restarting == false) |
      {id:.Id,started_at:.State.StartedAt,restart_count:.RestartCount,
       public_port:$public,internal_port:$internal,domain:"source.padm.test",
       networks:(.NetworkSettings.Networks | to_entries |
         map({name:.key,id:.value.NetworkID}) | sort_by(.name)),
       addresses:($hosts + [.NetworkSettings.Networks[] |
         .IPAddress,.Gateway,.GlobalIPv6Address,.IPv6Gateway] | map(select(. != "")) | unique)}
    '
}
dockerFail2banSourceWitness "$2" "$3"
'''
    environment = dict(os.environ, DOCKER_HOST=docker[-1],
                       PADM_TEST_SOURCE_CONTAINER=identity, PADM_TEST_SOURCE_LISTENER=listener,
                       PADM_TEST_SOURCE_FAMILY=family, PADM_TEST_SOURCE_PORT=str(port),
                       PADM_TEST_SOURCE_INTERNAL=str(internal_port),
                       PADM_TEST_SOURCE_HOSTS=json.dumps(list(HOST.values()) +
                           ["198.18.2.4", "fd42:7061:646d:2::4"]))
    if history_uri is None:
        history_uri = "/.well-known/padm-source/" + "f" * 48
    assert client(client_processes[0], family, history_uri, port=port) == {"status": 204}
    process = subprocess.Popen(
        ["bash", "-u", "-c", script, "test", str(ROOT / "install-docker.sh"), listener,
         SOURCES[family][0]], env=environment, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE)
    try:
        with selectors.DefaultSelector() as reader:
            reader.register(process.stdout, selectors.EVENT_READ)
            assert reader.select(timeout=5), "生产来源见证未输出挑战"
            first = process.stdout.readline().strip()
        assert first.startswith("source-challenge="), first
        challenge = json.loads(first.removeprefix("source-challenge="))
        assert challenge["public_port"] == port and challenge["family"] == family
        assert challenge["domain"] == "source.padm.test"
        uri = challenge["uri"]
        assert uri.startswith("/.well-known/padm-source/") and len(uri.rsplit("/", 1)[1]) == 48
        log = docker + ["logs", identity]
        assert uri.encode() not in command(log), "fresh challenge 已存在于历史日志"
        if reject == "port":
            wrong_port = PORT + 1 if port == PORT else PORT
            assert client(client_processes[0], family, uri, port=wrong_port) == {"status": 204}
        elif reject == "source":
            assert client(client_processes[1], family, uri,
                          forged=SOURCES[family][0], port=port) == {"status": 204}
        else:
            # 历史 URI 和重放的旧挑战不能满足新 nonce，正确请求仍使用伪造头验证真实首字段。
            assert client(client_processes[0], family, history_uri, port=port) == {"status": 204}
            time.sleep(0.2)
            assert process.poll() is None, "历史或重放日志提前满足了生产见证"
            assert client(client_processes[0], family, uri, port=port) == {"status": 204}
        output, error = process.communicate(timeout=8)
        if reject is not None:
            assert process.returncode != 0 and "source-verified=" not in output, (reject, output, error)
            print(f"fail2ban-production-source-reject-{reject}=passed", flush=True)
            return uri
        assert process.returncode == 0, (first, output, error)
        assert "source-verified=" in output, (first, output, error)
        proof = next(json.loads(line.removeprefix("source-verified="))
                     for line in output.splitlines() if line.startswith("source-verified="))
        assert {key: value for key, value in proof.items() if key != "source"} == dict(
            listener_id=listener, family=family, public_port=port, internal_port=internal_port), proof
        assert ipaddress.ip_address(proof["source"]) == ipaddress.ip_address(SOURCES[family][0]), proof
        print("fail2ban-production-source-witness=" + json.dumps(
            dict(listener_id=listener, family=family, public_port=port, proof=proof),
            sort_keys=True), flush=True)
        return uri
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()


def run(root):
    assert os.getuid() == 0 and sys.platform == "linux" and Path("/.dockerenv").is_file()
    assert {item["ifname"] for item in json.loads(command(["ip", "-j", "link", "show"]))} == {
        "lo"}, "不得借用宿主接口或已有网络"
    inputs = json.loads(Path("/node-images.json").read_text())
    assert {"xray", "nginx", "net"} <= inputs.keys()
    node = Path(tempfile.mkdtemp(prefix=".tmp-fail2ban-source-", dir="/n"))
    node.chmod(0o755)
    daemon, clients = None, []
    docker = ["docker", "--host", f"unix://{node}/docker.sock"]
    started = time.monotonic()
    with (node / "daemon.log").open("wb") as log:
        try:
            daemon = subprocess.Popen([
                "dockerd", "--host", docker[-1], "--data-root", str(node / "docker"),
                "--exec-root", str(node / "run"), "--pidfile", str(node / "daemon.pid"),
                "--feature", "containerd-snapshotter=true", "--storage-driver", "overlayfs",
                "--bip", "172.30.0.1/24", "--ipv6", "--fixed-cidr-v6", "fd42:7061:646d:30::/64"],
                stdout=log, stderr=log)
            wait_ready(lambda: subprocess.run(docker + ["info"], capture_output=True).returncode == 0,
                       "隔离 daemon 未就绪", 30)
            command(docker + ["load", "--input", "/node-images.tar"], timeout=120)
            for item in inputs.values():
                image = json.loads(command(docker + ["image", "inspect", item["reference"]]))[0]
                assert image["Id"] == item["image_id"]
            clients = namespaces()
            entrypoint = node / "entrypoint.sh"
            shutil.copyfile(ROOT / "docker/images/net/entrypoint.sh", entrypoint)
            entrypoint.chmod(0o755)
            evidence = {"ipv4": "unverified", "dual_ipv4": "unverified",
                        "ipv6": "unverified", "image_ids": inputs}
            for mode in ("ipv4", "dual"):
                deployment = node / mode
                command(["cp", "-a", str(root / mode), str(deployment)])
                source = json.loads((deployment / "compose.json").read_text())
                source["services"] = {name: source["services"][name]
                                      for name in ("xray", "nginx", "net-fail2ban")}
                for name, service in source["services"].items():
                    service["image"] = inputs["net" if name == "net-fail2ban" else name]["image_id"]
                    for volume in service["volumes"]:
                        volume["source"] = volume["source"].replace(
                            "${PADM_DOCKER_ROOT}", str(deployment)).replace(
                            "${PADM_NET_ROOT}", str(deployment))
                    service["restart"] = "no"
                service = source["services"]["net-fail2ban"]
                # 离线夹具解析自己的固定机名，保留 Fail2ban ignoreself 检查。
                service["hostname"] = "source-fixture.padm.test"
                service["extra_hosts"] = ["source-fixture.padm.test:127.0.0.1"]
                service["volumes"].append(dict(
                    type="bind", source=str(entrypoint),
                    target="/usr/local/bin/padm-entrypoint", read_only=True))
                service["entrypoint"] = ["sh", "/usr/local/bin/padm-entrypoint"]
                compose_path = deployment / "compose.json"
                compose_path.write_text(json.dumps(source))
                compose = docker + ["compose", "--project-name", "padm-docker", "--file",
                                    str(compose_path), "--profile", "*"]
                command(compose + ["up", "-d", "--pull", "never"], timeout=50)
                identities = {name: command(compose + ["ps", "-q", name]).decode().strip()
                              for name in source["services"]}
                nginx = inspect(docker, identities["nginx"])
                host = nginx["HostConfig"]
                assert host["ReadonlyRootfs"] and not host["Privileged"]
                assert host["CapDrop"] == ["ALL"] and not host["CapAdd"]
                assert nginx["Config"]["User"] == "10001:10001"
                for public_port, internal_port in ((PORT, 8443), (PORT + 1, 8444)):
                    assert host["PortBindings"][f"{internal_port}/tcp"] == [
                        dict(HostIp="0.0.0.0", HostPort=str(public_port))] + (
                        [dict(HostIp="::", HostPort=str(public_port))] if mode == "dual" else [])
                networks = nginx["NetworkSettings"]["Networks"]
                assert set(networks) == {"padm-docker"} | (
                    {"padm-docker-ipv6"} if mode == "dual" else set()), networks
                if mode == "dual":
                    ipv6_network = json.loads(command(docker + [
                        "network", "inspect", "padm-docker-ipv6"]))[0]
                    assert ipv6_network["EnableIPv6"] and ipv6_network["Driver"] == "bridge"
                    assert all(ipv6_network["Labels"].get(name) == value for name, value in {
                        "io.padm.mode": "docker", "io.padm.project": "padm-docker",
                        "io.padm.component": "routing-ipv6"}.items())
                    assert networks["padm-docker-ipv6"]["GlobalIPv6Address"], networks
                net = inspect(docker, identities["net-fail2ban"])
                print("fail2ban-source-inspect-caps=" + json.dumps(dict(
                    cap_add=net["HostConfig"]["CapAdd"], cap_drop=net["HostConfig"]["CapDrop"])),
                    flush=True)
                assert net["HostConfig"]["NetworkMode"] == "host"
                assert [name.removeprefix("CAP_") for name in net["HostConfig"]["CapAdd"]] == [
                    "NET_ADMIN"], net["HostConfig"]["CapAdd"]
                assert net["HostConfig"]["CapDrop"] == ["ALL"] and not net["HostConfig"]["Privileged"]
                wait_ready(lambda: subprocess.run(
                    docker + ["exec", identities["net-fail2ban"], "fail2ban-client", "status", "padm-nginx"],
                    capture_output=True).returncode == 0, "Fail2ban 未就绪")
                families = ("ipv4",) if mode == "ipv4" else ("ipv4", "ipv6")
                history_uri = None
                for family in families:
                    wait_ready(lambda: client(clients[0], family).get("status") == 200,
                               f"{family} 发布连接未就绪")
                    for listener, public_port, internal_port in (
                            ("entry-source-ws", PORT, 8443), ("entry-source-ws2", PORT + 1, 8444)):
                        history_uri = witness(docker, identities["nginx"], clients, family,
                                              listener, public_port, internal_port, history_uri=history_uri)
                    if mode == "ipv4":
                        for reason in ("port", "source"):
                            witness(docker, identities["nginx"], clients, family,
                                    "entry-source-ws", PORT, 8443, reject=reason)
                    assert client(clients[0], family) == {"status": 200}
                    access = deployment / "logs/nginx/access.log"
                    wait_ready(lambda: access.stat().st_size > 0, f"{family} 请求没有真实日志")
                    source_address, forged = SOURCES[family]
                    line = access.read_text().splitlines()[-1]
                    assert line.startswith(source_address + " "), f"{family} 真实来源丢失：{line}"
                    exec_net = docker + ["exec", identities["net-fail2ban"], "fail2ban-client"]
                    def query_bans():
                        response = json.loads(command(docker + [
                            "exec", identities["net-fail2ban"], "python3", "-c",
                            "import json; from fail2ban.client.csocket import CSocket; "
                            "s=CSocket('/run/fail2ban/fail2ban.sock'); "
                            "r=s.send(['get','padm-nginx','banip']); s.close(); print(json.dumps(r))"]))
                        assert response[0] == 0, response
                        return set(response[1])
                    assert not query_bans()
                    for attempt in range(3):
                        assert client(clients[0], family, f"/.env?attempt={attempt}", forged) == {
                            "status": 404}
                    print(f"fail2ban-source-real-{family}-access:\n" + access.read_text(), flush=True)
                    print(command(docker + ["exec", identities["net-fail2ban"], "fail2ban-regex",
                          "--print-all-matched", "/var/log/padm/nginx/access.log",
                          "/etc/fail2ban/filter.d/padm-nginx.conf"]).decode(), flush=True)
                    wait_ready(lambda: source_address in query_bans(), f"{family} 日志未触发封禁")
                    assert query_bans() == {source_address}, "伪造头污染封禁地址"
                    table = "iptables" if family == "ipv4" else "ip6tables"
                    # 同时证明真实 DNAT/DOCKER-USER DROP，不接受只有超时的间接结论。
                    save_rules = docker + ["exec", identities["net-fail2ban"], table + "-save", "-c"]
                    rules = command(save_rules).decode()
                    drop_line = next(line for line in rules.splitlines()
                                     if f"-s {source_address}/" in line and "-j DROP" in line)
                    count = int(drop_line.split(":", 1)[0].lstrip("["))
                    before = access.read_text()
                    assert client(clients[0], family) == {"timeout": True}
                    after_rules = command(save_rules).decode()
                    after_line = next(line for line in after_rules.splitlines()
                                      if f"-s {source_address}/" in line and "-j DROP" in line)
                    assert int(after_line.split(":", 1)[0].lstrip("[")) > count
                    assert access.read_text() == before, "被封连接仍进入 Nginx"
                    assert client(clients[1], family) == {"status": 200}, "封禁误伤第二客户端"
                    if mode == "dual":
                        other = "ipv6" if family == "ipv4" else "ipv4"
                        assert client(clients[0], other) == {"status": 200}, "封禁误伤另一地址族"
                    command(exec_net + ["set", "padm-nginx", "unbanip", source_address])
                    wait_ready(lambda: source_address not in query_bans(), f"{family} 解封未完成")
                    wait_ready(lambda: client(clients[0], family) == {"status": 200},
                               "解封未恢复真实连接")
                    evidence["dual_ipv4" if mode == "dual" and family == "ipv4" else family] = "passed"
                    print(f"fail2ban-source-real-{mode}-{family}: source/forged-header/filter/"
                          "DNAT/DROP-counter/second-client/unban passed", flush=True)
                command(docker + ["exec", identities["net-fail2ban"],
                                   "/usr/local/bin/padm-entrypoint", "fail2ban-health"])
                for name, identity in identities.items():
                    result = subprocess.run(docker + ["logs", identity], capture_output=True, check=True)
                    (root / f"{mode}.{name}.log").write_bytes(result.stdout + result.stderr)
                command(compose + ["down", "--timeout", "10"], timeout=25)
                assert not (deployment / "data/net/fail2ban/fail2ban.state").exists()
                for table in ("iptables-save", "ip6tables-save"):
                    remaining = command(docker + [
                        "run", "--rm", "--network", "host", "--cap-drop", "ALL",
                        "--cap-add", "NET_ADMIN", "--read-only", "--security-opt",
                        "no-new-privileges:true", "--entrypoint", table, inputs["net"]["image_id"]])
                    assert b"padm-f2b" not in remaining, f"停止后残留 {table} Fail2ban 资源"
            evidence["elapsed"] = round(time.monotonic() - started, 3)
            print("fail2ban-source-real-evidence=" + json.dumps(evidence, sort_keys=True), flush=True)
            assert all(evidence[family] == "passed" for family in ("ipv4", "dual_ipv4", "ipv6"))
        except BaseException:
            result = subprocess.run(docker + ["ps", "-aq"], capture_output=True, timeout=10)
            for identity in result.stdout.decode().split() if not result.returncode else []:
                diagnostic = subprocess.run(docker + ["logs", identity], capture_output=True, timeout=10)
                print((diagnostic.stdout + diagnostic.stderr).decode(errors="replace"), file=sys.stderr)
            raise
        finally:
            active_error = sys.exc_info()[0] is not None
            cleanup_error = None
            for client_process in clients:
                stop(client_process)
            if daemon is not None:
                try:
                    result = subprocess.run(docker + ["ps", "-aq"], capture_output=True, timeout=5)
                    if result.returncode == 0 and result.stdout.strip():
                        command(docker + ["rm", "-f"] + result.stdout.decode().split(), timeout=15)
                except (AssertionError, subprocess.TimeoutExpired) as error:
                    cleanup_error = error
                finally:
                    stop(daemon)
            if active_error or cleanup_error:
                print((node / "daemon.log").read_text()[-4000:], file=sys.stderr)
            assert node.parent == Path("/n") and node.name.startswith(".tmp-fail2ban-source-")
            try:
                # daemon 退出可能留下 netns 绑定挂载，只卸载本次隔离目录的子挂载。
                mounts = [line.split()[4] for line in Path("/proc/self/mountinfo").read_text().splitlines()
                          if line.split()[4].startswith(str(node) + "/")]
                for mount in sorted(mounts, key=lambda value: value.count("/"), reverse=True):
                    command(["umount", "--lazy", "--", mount], timeout=5)
                shutil.rmtree(node)
            except (OSError, AssertionError, subprocess.TimeoutExpired) as error:
                print(f"fail2ban-source-cleanup: {error}", file=sys.stderr)
                if not active_error:
                    raise
            if cleanup_error:
                raise cleanup_error


if __name__ == "__main__":
    if sys.argv[1] == "client":
        print(json.dumps(request(*sys.argv[2:6])))
    else:
        run(Path(sys.argv[1]))
