#!/usr/bin/env python3
import contextlib
import copy
import ipaddress
import json
import os
from pathlib import Path
import runpy
import shutil
import signal
import socket
import socketserver
import struct
import subprocess
import sys
import tempfile
import threading
import time


ROOT = Path(__file__).resolve().parents[2]
helpers = runpy.run_path(str(Path(__file__).with_name("routing-dns-hosts-real.py")))
node_helpers = runpy.run_path(str(Path(__file__).with_name("control-two-deployment-real.py")))
command, stop = (node_helpers[name] for name in ("command", "stop"))
Server, exact, request = (helpers[name] for name in ("Server", "exact", "request"))
BT_HANDSHAKE = helpers["BT_HANDSHAKE"]
HTTP_PORT, UDP_PORT, DNS_PORT, SOCKS_PORT, LOCAL_PORT = 8088, 8089, 5353, 1080, 2080
FIXTURE_ROOT = None
EVENT_LOCK = threading.Lock()


def event(kind, **values):
    with EVENT_LOCK, (FIXTURE_ROOT / "events.jsonl").open("a") as output:
        output.write(json.dumps(dict(kind=kind, **values)) + "\n")


class Origin(socketserver.BaseRequestHandler):
    def handle(self):
        conn = self.request
        conn.settimeout(3)
        family = 6 if self.server.address_family == socket.AF_INET6 else 4
        event("tcp", family=family, source=self.client_address[0])
        data = exact(conn, 1)
        if data == BT_HANDSHAKE[:1]:
            data += exact(conn, len(BT_HANDSHAKE) - 1)
        else:
            while b"\r\n\r\n" not in data:
                data += exact(conn, 1)
        if data.startswith(b"GET /routing-check "):
            conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 22\r\nConnection: close\r\n\r\n"
                         b"routing-destination-ok")
        elif data.startswith(BT_HANDSHAKE[:20]):
            conn.sendall(BT_HANDSHAKE)


class Dns(socketserver.BaseRequestHandler):
    def handle(self):
        data, channel = self.request
        offset, parts = 12, []
        while size := data[offset]:
            offset += 1
            parts.append(data[offset:offset + size].decode("ascii"))
            offset += size
        end = offset + 5
        name = ".".join(parts)
        kind, _ = struct.unpack("!HH", data[offset + 1:end])
        event("dns", name=name, qtype=kind)
        addresses = json.loads((FIXTURE_ROOT / "addresses.json").read_text())
        only4 = name in ("aonly.padm.invalid", "unmatched.test", "direct.padm.invalid")
        answer = b""
        if kind == 1 or (kind == 28 and not only4):
            family = socket.AF_INET if kind == 1 else socket.AF_INET6
            value = socket.inet_pton(family, addresses["v4" if kind == 1 else "v6"])
            answer = b"\xc0\x0c" + struct.pack("!HHIH", kind, 1, 1, len(value)) + value
        channel.sendto(data[:2] + struct.pack("!HHHHH", 0x8180, 1, int(bool(answer)), 0, 0) +
                       data[12:end] + answer, self.client_address)


class Datagram(socketserver.BaseRequestHandler):
    def handle(self):
        data, channel = self.request
        family = 6 if self.server.address_family == socket.AF_INET6 else 4
        event("udp", family=family, source=self.client_address[0], body=data.decode("ascii"))
        channel.sendto(data, self.client_address)


class UdpServer(socketserver.ThreadingUDPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address, handler):
        self.address_family = socket.AF_INET6 if ":" in address[0] else socket.AF_INET
        super().__init__(address, handler)

    def server_bind(self):
        if self.address_family == socket.AF_INET6:
            self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
        super().server_bind()


class TcpServer(Server):
    def server_bind(self):
        if self.address_family == socket.AF_INET6:
            self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
        super().server_bind()


class Proxy(socketserver.BaseRequestHandler):
    def handle(self):
        conn = self.request
        conn.settimeout(3)
        try:
            version, count = exact(conn, 2)
            assert version == 5 and 2 in exact(conn, count)
            conn.sendall(b"\x05\x02")
            assert exact(conn, 1) == b"\x01"
            user = exact(conn, exact(conn, 1)[0])
            password = exact(conn, exact(conn, 1)[0])
            assert (user, password) == (b"fixture-user", b"fixture-password")
            event("proxy-auth")
            conn.sendall(b"\x01\x00")
            assert exact(conn, 4) == b"\x05\x01\x00\x03"
            name = exact(conn, exact(conn, 1)[0]).decode("ascii")
            assert struct.unpack("!H", exact(conn, 2))[0] == HTTP_PORT
            event("proxy", name=name)
            addresses = json.loads((FIXTURE_ROOT / "addresses.json").read_text())
            with socket.create_connection((addresses["v4"], HTTP_PORT), timeout=3) as target:
                conn.sendall(b"\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00")
                target.sendall(conn.recv(4096))
                while data := target.recv(4096):
                    conn.sendall(data)
        except (EOFError, ConnectionResetError):
            return


def fixture(directory):
    global FIXTURE_ROOT
    FIXTURE_ROOT = Path(directory)
    stopping = threading.Event()
    signal.signal(signal.SIGTERM, lambda _number, _frame: stopping.set())
    with contextlib.ExitStack() as stack:
        servers = []
        for host in ("0.0.0.0", "::"):
            servers += [stack.enter_context(TcpServer((host, HTTP_PORT), Origin)),
                        stack.enter_context(UdpServer((host, UDP_PORT), Datagram))]
        servers += [stack.enter_context(UdpServer(("0.0.0.0", DNS_PORT), Dns)),
                    stack.enter_context(UdpServer(("0.0.0.0", 53), Dns)),
                    stack.enter_context(TcpServer(("0.0.0.0", SOCKS_PORT), Proxy))]
        for server in servers:
            threading.Thread(target=server.serve_forever, kwargs=dict(poll_interval=0.05),
                             daemon=True).start()
        (FIXTURE_ROOT / "ready").touch()
        stopping.wait()


def rows(directory):
    return [json.loads(line) for line in (directory / "events.jsonl").read_text().splitlines()]


def wait_ready(probe, limit=10):
    deadline = time.monotonic() + limit
    while True:
        try:
            if probe():
                return
        except (OSError, AssertionError):
            pass
        assert time.monotonic() < deadline, "真实 bridge 服务就绪超时"
        time.sleep(0.05)


def inspect_container(client, identity):
    return json.loads(command(client + ["inspect", identity]))[0]


def assert_permissions(value):
    host = value["HostConfig"]
    assert host["ReadonlyRootfs"] and not host["Privileged"]
    assert host["CapDrop"] == ["ALL"] and not host["CapAdd"] and not host["Devices"]
    assert not host["PortBindings"], "真实夹具不得发布宿主端口"
    assert value["Config"]["User"] == "10001:10001"


def ipv6_network(client):
    value = json.loads(command(client + ["network", "inspect", "padm-docker-ipv6"]))[0]
    assert value["EnableIPv6"], "生产辅助网络未启用 IPv6"
    assert value["Labels"]["io.padm.project"] == "padm-docker"
    assert value["Labels"]["io.padm.mode"] == "docker"
    assert any(ipaddress.ip_network(item["Subnet"]).version == 6 for item in value["IPAM"]["Config"])
    return value


def prepare_config(root, core, mode, fixture_addresses):
    config = json.loads((root / f"{core}.{mode}.json").read_text())
    if core == "xray":
        server = config["dns"]["servers"][0]
        assert isinstance(server, dict)
        for server in config["dns"]["servers"]:
            if isinstance(server, dict) and server.get("address") == "192.0.2.53":
                server.update(address=fixture_addresses["v4"], port=DNS_PORT, timeoutMs=500)
        for key in config["dns"]["hosts"]:
            if key.endswith("hosts6.padm.invalid"):
                config["dns"]["hosts"][key] = fixture_addresses["v6"]
            elif key.endswith("hosts4.padm.invalid"):
                config["dns"]["hosts"][key] = fixture_addresses["v4"]
        for rule in config["routing"]["rules"]:
            if rule.get("ip") == ["192.0.2.199"]:
                rule["ip"] = [fixture_addresses["v6"]]
        outbound = next(item for item in config["outbounds"] if item["tag"] == "padm-socks5")
        outbound["settings"]["servers"][0].update(address=fixture_addresses["v4"], port=SOCKS_PORT)
        sniff = copy.deepcopy(next(item["sniffing"] for item in config["inbounds"]
                                   if item["tag"] != "padm-traffic-api"))
        config["inbounds"].append(dict(listen="0.0.0.0", port=LOCAL_PORT, tag="fixture-in",
                                      protocol="socks", settings=dict(auth="noauth", udp=True),
                                      sniffing=sniff))
    else:
        for server in config["dns"]["servers"]:
            if server["tag"] == "padm-dns":
                server.update(server=fixture_addresses["v4"], server_port=DNS_PORT)
            if server["tag"] == "padm-hosts":
                server["predefined"].update({"hosts6.padm.invalid": fixture_addresses["v6"],
                                             "hosts4.padm.invalid": fixture_addresses["v4"]})
        for rule in config["route"]["rules"]:
            for item in rule.get("rules", []):
                if item.get("ip_cidr") == ["192.0.2.199"]:
                    item["ip_cidr"] = [fixture_addresses["v6"]]
        outbound = next(item for item in config["outbounds"] if item["tag"] == "padm-socks5")
        outbound.update(server=fixture_addresses["v4"], server_port=SOCKS_PORT)
        config["inbounds"].append(dict(type="socks", tag="fixture-in", listen="0.0.0.0",
                                      listen_port=LOCAL_PORT))
    return config


def udp_request(host, target):
    with socket.create_connection((host, LOCAL_PORT), timeout=3) as control:
        control.sendall(b"\x05\x01\x00")
        assert exact(control, 2) == b"\x05\x00"
        control.sendall(b"\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00")
        header = exact(control, 4)
        assert header[:2] == b"\x05\x00"
        address = socket.inet_ntop({1: socket.AF_INET, 4: socket.AF_INET6}[header[3]],
                                  exact(control, {1: 4, 4: 16}[header[3]]))
        relay = struct.unpack("!H", exact(control, 2))[0]
        if address in ("0.0.0.0", "::"):
            address = host
        family = socket.AF_INET6 if ":" in address else socket.AF_INET
        with socket.socket(family, socket.SOCK_DGRAM) as channel:
            channel.settimeout(3)
            channel.sendto(b"\x00\x00\x00" + helpers["socks_address"](target) +
                           struct.pack("!H", UDP_PORT) + b"ipv6-bridge-proof", (address, relay))
            packet = channel.recv(4096)
            assert packet.endswith(b"ipv6-bridge-proof")


def rejected(host, target, directory, *, core, payload=None):
    before = rows(directory)
    try:
        assert not request(host, LOCAL_PORT, HTTP_PORT, target, pipelined=core == "xray",
                           payload=payload, timeout=5), f"未实际拒绝 {target}"
    except (EOFError, ConnectionResetError):
        pass
    except socket.timeout:
        raise AssertionError(f"{target}: 仅客户端超时，拒绝证据不足")
    delta = rows(directory)[len(before):]
    assert not any(row["kind"] in ("tcp", "proxy-auth", "proxy") for row in delta), (
        f"{target}: 拒绝前连接目的或 SOCKS5")
    return delta


def accepted(host, target, directory, family, *, core, http_host=None):
    before = rows(directory)
    assert request(host, LOCAL_PORT, HTTP_PORT, target, http_host, pipelined=core == "xray")
    delta = rows(directory)[len(before):]
    received = [row for row in delta if row["kind"] == "tcp"]
    assert len(received) == 1 and received[0]["family"] == family, (target, received)
    assert not ipaddress.ip_address(received[0]["source"]).is_loopback
    return delta


def network_manage(client, action, *, valid=True):
    environment = dict(os.environ, DOCKER_HOST=client[-1])
    result = subprocess.run(
        ["bash", "-c", 'source "$1"; dockerIPv6NetworkManage "$2"', "_",
         str(ROOT / "install-docker.sh"), action], env=environment, capture_output=True, timeout=20)
    assert (result.returncode == 0) == valid, result.stderr.decode(errors="replace")


def network_exists(client):
    return bool(command(client + ["network", "ls", "-q", "--filter", "name=^padm-docker-ipv6$"]).strip())


def run(root):
    assert os.getuid() == 0 and sys.platform == "linux" and Path("/.dockerenv").is_file()
    links = json.loads(command(["ip", "-j", "link", "show"]))
    assert {item["ifname"] for item in links} == {"lo"}, "不得借用已有接口或宿主网络"
    inputs = json.loads(Path("/node-images.json").read_text())
    node_path = Path(tempfile.mkdtemp(prefix=".tmp-routing-ipv6-", dir="/n"))
    node_path.chmod(0o755)
    fixture_path = node_path / "fixture"
    fixture_path.mkdir(mode=0o755)
    os.chown(fixture_path, 10001, 10001)
    (fixture_path / "events.jsonl").touch(mode=0o644)
    os.chown(fixture_path / "events.jsonl", 10001, 10001)
    daemon = None
    client = ["docker", "--host", f"unix://{node_path}/docker.sock"]
    with (node_path / "daemon.log").open("wb") as log:
        try:
            daemon = subprocess.Popen(
                ["dockerd", "--host", client[-1], "--data-root", str(node_path / "docker"),
                 "--exec-root", str(node_path / "run"), "--pidfile", str(node_path / "daemon.pid"),
                 "--feature", "containerd-snapshotter=true", "--storage-driver", "overlayfs",
                 "--bip", "172.30.0.1/24"], stdout=log, stderr=log)
            wait_ready(lambda: subprocess.run(client + ["info"], capture_output=True).returncode == 0, 30)
            command(client + ["load", "--input", "/node-images.tar"], timeout=120)
            for item in inputs.values():
                assert inspect_image(client, item["reference"]) == item["image_id"]
            compose_source = json.loads((root / "selective.compose.json").read_text())
            assert compose_source["networks"]["ipv6"]["enable_ipv6"] is True
            for core in ("xray", "sing-box"):
                assert compose_source["services"][core]["networks"] == ["default", "ipv6"]
            base_source = json.loads((root / "control.compose.json").read_text())
            assert "ipv6" not in base_source["networks"]
            compose_source["services"] = {}
            compose_source["services"]["fixture"] = dict(
                image=inputs["ops"]["image_id"], user="10001:10001", read_only=True, cap_drop=["ALL"],
                security_opt=["no-new-privileges:true"], networks=["default", "ipv6"],
                entrypoint=["python3", "/work/docker/tests/routing-ipv6-real.py", "fixture", "/proof"],
                volumes=[dict(type="bind", source=str(ROOT / "docker/tests"),
                              target="/work/docker/tests", read_only=True),
                         dict(type="bind", source=str(fixture_path), target="/proof")])
            fixture_compose = node_path / "fixture.compose.json"
            fixture_compose.write_text(json.dumps(compose_source))
            fixture_command = client + ["compose", "--project-name", "padm-docker",
                                         "--file", str(fixture_compose)]
            command(fixture_command + ["up", "-d", "--pull", "never"], timeout=40)
            identity = command(fixture_command + ["ps", "-q", "fixture"]).decode().strip()
            value = inspect_container(client, identity)
            assert_permissions(value)
            default_v4 = value["NetworkSettings"]["Networks"]["padm-docker"]["IPAddress"]
            origin_v6 = value["NetworkSettings"]["Networks"]["padm-docker-ipv6"]["GlobalIPv6Address"]
            assert ipaddress.ip_address(default_v4).version == 4
            assert ipaddress.ip_address(origin_v6).version == 6
            ipv6_network(client)
            network_manage(client, "check")
            network_manage(client, "cleanup")
            assert network_exists(client), "清理误断开仍有服务的辅助网络"
            fixture_addresses = dict(v4=default_v4, v6=origin_v6)
            (fixture_path / "addresses.json").write_text(json.dumps(fixture_addresses))
            wait_ready(lambda: (fixture_path / "ready").is_file())
            for core in ("xray", "sing-box"):
                for mode in ("control", "selective", "global", "off"):
                    path = node_path / f"{core}.{mode}.json"
                    path.write_text(json.dumps(prepare_config(root, core, mode, fixture_addresses)))
                    path.chmod(0o644)
                    compose = json.loads((root / f"{mode}.compose.json").read_text())
                    service = compose["services"][core]
                    # 不覆写生产网络；只使用测试 SOCKS 入站、无宿主端口和当前配置快照。
                    service.update(image=inputs[core]["image_id"], user="10001:10001", ports=[],
                                   dns=[default_v4],
                                   volumes=[dict(type="bind", source=str(path),
                                                 target="/config.json", read_only=True)],
                                   entrypoint=[f"/usr/local/bin/{core}"], command=["run", "-c", "/config.json"],
                                   healthcheck=dict(disable=True), restart="no")
                    compose["services"] = {core: service}
                    compose_path = node_path / f"{core}.{mode}.compose.json"
                    compose_path.write_text(json.dumps(compose))
                    core_command = client + ["compose", "--project-name", "padm-docker",
                                             "--file", str(compose_path),
                                             "--profile", f"core-{core}"]
                    validate = ["-test", "-config", "/config.json"] if core == "xray" else [
                        "check", "-c", "/config.json"]
                    command(core_command + ["run", "--rm", "--no-deps", core] + validate, timeout=30)
                    command(core_command + ["up", "-d", "--pull", "never"], timeout=40)
                    identity = command(core_command + ["ps", "-q", core]).decode().strip()
                    value = inspect_container(client, identity)
                    assert_permissions(value)
                    network_values = value["NetworkSettings"]["Networks"]
                    host = network_values["padm-docker"]["IPAddress"]
                    if mode in ("selective", "global"):
                        ipv6_network(client)
                        address = network_values["padm-docker-ipv6"]["GlobalIPv6Address"]
                        assert ipaddress.ip_address(address).version == 6
                        assert not ipaddress.ip_address(address).is_loopback
                        routes = command(["nsenter", "--target", str(value["State"]["Pid"]),
                                          "--net", "ip", "-6", "route", "show", "default"]).decode()
                        assert routes.startswith("default via "), "辅助网络未提供 IPv6 默认路由"
                    else:
                        assert "padm-docker-ipv6" not in network_values
                    wait_ready(lambda: listener(host))
                    if mode in ("control", "off"):
                        accepted(host, "aonly.padm.invalid", fixture_path, 4, core=core)
                    else:
                        target = "matched.padm.invalid" if mode == "selective" else "global.padm.invalid"
                        delta = accepted(host, target, fixture_path, 6, core=core)
                        assert not any(row["kind"].startswith("proxy") for row in delta)
                        if mode == "global":
                            delta = accepted(host, "matched.padm.invalid", fixture_path, 4, core=core)
                            assert [row["name"] for row in delta if row["kind"] == "proxy"] == [
                                "matched.padm.invalid"]
                        delta = rejected(host, "aonly.padm.invalid", fixture_path, core=core)
                        assert any(row["kind"] == "dns" and row["qtype"] == 28 for row in delta)
                        assert not any(row["kind"] == "dns" and row["qtype"] == 1 for row in delta)
                        accepted(host, "hosts6.padm.invalid", fixture_path, 6, core=core)
                        rejected(host, "hosts4.padm.invalid", fixture_path, core=core)
                        accepted(host, default_v4, fixture_path, 4, core=core)
                        assert not rejected(host, origin_v6, fixture_path, core=core)
                        accepted(host, "direct.padm.invalid", fixture_path, 4, core=core)
                        assert not rejected(host, "blocked.padm.invalid", fixture_path, core=core)
                        assert not rejected(host, target, fixture_path,
                                            core=core, payload=BT_HANDSHAKE)
                        delta = accepted(host, "proxy.test", fixture_path, 4, core=core)
                        assert [row["name"] for row in delta if row["kind"] == "proxy"] == ["proxy.test"]
                        before = rows(fixture_path)
                        udp_request(host, target)
                        delta = rows(fixture_path)[len(before):]
                        received = [row for row in delta if row["kind"] == "udp"]
                        assert len(received) == 1 and received[0]["family"] == 6
                    if mode == "global":
                        delta = rejected(host, "unmatched.test", fixture_path, core=core)
                        assert any(row["kind"] == "dns" and row["qtype"] == 28 for row in delta)
                        # Xray 固定版本的 localdns 先 LookupIP 再过滤；允许 A 查询，但不得用 A 地址连接。
                    else:
                        accepted(host, "unmatched.test", fixture_path, 4, core=core)
                    assert inspect_container(client, identity)["State"]["Running"]
                    command(core_command + ["rm", "-s", "-f"], timeout=30)
                    checks = ("default-bridge/TCPv4/no-ipv6-attachment"
                              if mode in ("control", "off") else
                              "default-bridge/IPv6-default-route/AAAA-address-only/TCP/UDP/priority")
                    print(f"routing-ipv6-bridge-{core}-{mode}: "
                          f"{checks} checks passed", flush=True)
            command(fixture_command + ["rm", "-s", "-f"], timeout=30)
            assert ipv6_network(client)["Containers"] == {}
            network_manage(client, "cleanup")
            assert not network_exists(client), "关闭后未删除精确 owned 的空辅助网络"
            command(client + ["network", "inspect", "padm-docker"])
            command(client + ["network", "create", "--ipv6", "--label", "io.padm.mode=docker",
                              "--label", "io.padm.project=padm-docker",
                              "--label", "io.padm.component=foreign", "padm-docker-ipv6"])
            network_manage(client, "check", valid=False)
            network_manage(client, "cleanup")
            assert network_exists(client), "清理删除了未知归属辅助网络"
            command(client + ["network", "rm", "padm-docker-ipv6"])
            print("routing-ipv6-bridge-environment=" +
                  json.dumps(dict(origin=fixture_addresses, image_ids=inputs), sort_keys=True), flush=True)
        except BaseException:
            diagnostic = subprocess.run(client + ["ps", "-aq"], capture_output=True, timeout=10)
            for identity in diagnostic.stdout.decode().split() if not diagnostic.returncode else []:
                result = subprocess.run(client + ["logs", identity], capture_output=True, timeout=10)
                print((result.stdout + result.stderr).decode(errors="replace"), file=sys.stderr)
            if daemon is not None and diagnostic.returncode == 0 and diagnostic.stdout.strip():
                result = subprocess.run(client + ["rm", "-f"] + diagnostic.stdout.decode().split(),
                                        capture_output=True, timeout=30)
                if result.returncode:
                    print(result.stderr.decode(errors="replace"), file=sys.stderr)
            raise
        finally:
            active_error = sys.exc_info()[0] is not None
            if daemon is not None:
                stop(daemon)
            if (node_path / "daemon.log").is_file():
                print((node_path / "daemon.log").read_text()[-5000:], file=sys.stderr)
            # daemon 已停后仅删除本次隔离卷中的副本，不残留镜像层和配置。
            assert node_path.parent == Path("/n") and node_path.name.startswith(".tmp-routing-ipv6-")
            try:
                shutil.rmtree(node_path)
            except OSError as error:
                print(f"routing-ipv6-cleanup: {error}", file=sys.stderr)
                if not active_error:
                    raise


def inspect_image(client, reference):
    return json.loads(command(client + ["image", "inspect", reference]))[0]["Id"]


def listener(host):
    with socket.create_connection((host, LOCAL_PORT), timeout=0.2):
        return True


if __name__ == "__main__":
    if sys.argv[1] == "fixture":
        fixture(sys.argv[2])
    else:
        run(Path(sys.argv[1]))
