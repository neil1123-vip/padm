#!/usr/bin/env python3
import concurrent.futures
import http.server
import json
import os
from pathlib import Path
import runpy
import shutil
import signal
import socket
import socketserver
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse


SCRIPT = Path(__file__).resolve()
helpers = runpy.run_path(str(SCRIPT.with_name("http-relay-published-real.py")))
command, stop, wait_ready, namespaces, exact = (
    helpers[name] for name in ("command", "stop", "wait_ready", "namespaces", "exact"))
HOST = helpers["HOST"]
TCP_PORT, UDP_PORT, TLS_PORT = 18080, 18081, 18443
BODY = b"padm-entry-port-alias-proof"
PORTS = {"xray": (35441, 36441), "sing-box": (35442, 36442)}


def record(server, transport, address):
    with server.lock, (server.root / "events.jsonl").open("a") as output:
        output.write(json.dumps(dict(transport=transport, source=address[0])) + "\n")


class TcpOrigin(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(2)
        if exact(self.request, len(BODY)) == BODY:
            record(self.server, "tcp", self.client_address)
            self.request.sendall(BODY)


class UdpOrigin(socketserver.BaseRequestHandler):
    def handle(self):
        data, stream = self.request
        if data.startswith(BODY):
            record(self.server, "udp", self.client_address)
            stream.sendto(data, self.client_address)


class TlsTarget(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *_):
        pass


class ThreadedTlsTarget(http.server.ThreadingHTTPServer):
    def finish_request(self, request, client_address):
        # TLS 必须在线程内握手，裸 TCP 就绪探测不能阻塞整个监听器的 accept。
        request.settimeout(3)
        try:
            with self.context.wrap_socket(request, server_side=True) as stream:
                print(f"entry-port-alias-target-handshake: source={client_address} "
                      f"tls={stream.version()} alpn={stream.selected_alpn_protocol()}", flush=True)
                self.RequestHandlerClass(stream, client_address, self)
        except (OSError, ssl.SSLError) as error:
            print(f"entry-port-alias-target-rejected: source={client_address} "
                  f"error={type(error).__name__}: {error}", flush=True)


def fixture(root):
    stopping = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stopping.set())
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_3
    context.set_alpn_protocols(["h2", "http/1.1"])
    context.load_cert_chain(root / "target.crt", root / "target.key")
    with socketserver.ThreadingTCPServer((HOST, TCP_PORT), TcpOrigin) as tcp, \
            socketserver.ThreadingUDPServer((HOST, UDP_PORT), UdpOrigin) as udp, \
            ThreadedTlsTarget((HOST, TLS_PORT), TlsTarget) as tls:
        tls.context = context
        for server in (tcp, udp, tls):
            server.daemon_threads = True
            server.root, server.lock = root, threading.Lock()
            threading.Thread(target=server.serve_forever,
                             kwargs=dict(poll_interval=0.02), daemon=True).start()
        (root / "ready").touch()
        stopping.wait()
        tcp.shutdown()
        udp.shutdown()
        tls.shutdown()


def socks(port, transport, timeout):
    stream = socket.create_connection(("127.0.0.1", port), timeout=timeout)
    stream.settimeout(timeout)
    try:
        stream.sendall(b"\x05\x01\x00")
        assert exact(stream, 2) == b"\x05\x00"
        destination = socket.inet_aton(HOST) + struct.pack("!H", TCP_PORT)
        if transport == "udp":
            destination = b"\x00" * 6
        stream.sendall(b"\x05" + bytes([1 if transport == "tcp" else 3]) + b"\x00\x01" +
                       destination)
        reply = exact(stream, 4)
        assert reply[:1] == b"\x05" and reply[2] == 0
        size = {1: 4, 4: 16}.get(reply[3])
        assert size is not None
        address = socket.inet_ntop(socket.AF_INET if size == 4 else socket.AF_INET6,
                                  exact(stream, size))
        relay_port = struct.unpack("!H", exact(stream, 2))[0]
        if reply[1]:
            raise ConnectionRefusedError
        return stream, address, relay_port
    except BaseException:
        stream.close()
        raise


def probe_one(item, phase):
    local_port, core, alias, auth, transport = item
    expected = auth == "valid" and (phase != "off" or not alias)
    accepted = False
    timeout = 2 if expected else 1
    started = time.monotonic()
    failure = ""
    try:
        control, address, port = socks(local_port, transport, timeout)
        with control:
            if transport == "tcp":
                control.sendall(BODY)
                accepted = exact(control, len(BODY)) == BODY
            else:
                address = "127.0.0.1" if address == "0.0.0.0" else address
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as stream:
                    stream.bind(("127.0.0.1", 0))
                    stream.settimeout(timeout)
                    payload = BODY + struct.pack("!H", local_port) + phase.encode()
                    stream.sendto(b"\x00\x00\x00\x01" + socket.inet_aton(HOST) +
                                  struct.pack("!H", UDP_PORT) + payload, (address, port))
                    response, _ = stream.recvfrom(65535)
                    assert response[:4] == b"\x00\x00\x00\x01"
                    accepted = response[10:] == payload
    except (OSError, EOFError) as error:
        failure = f"{type(error).__name__}: {error}"
    if accepted != expected:
        print(f"entry-port-alias-probe-failure: phase={phase} core={core} alias={alias} "
              f"auth={auth} transport={transport} elapsed={time.monotonic()-started:.3f}s "
              f"error={failure}", file=sys.stderr)
    assert accepted == expected, (phase, core, alias, auth, transport, accepted)


def probes(root, phase):
    items = json.loads((root / "probes.json").read_text())
    if phase == "off":
        for _, alias in PORTS.values():
            try:
                with socket.create_connection((HOST, alias), timeout=0.3):
                    raise AssertionError(f"alias {alias} 移除后仍接受新 TCP 连接")
            except ConnectionRefusedError:
                pass
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(items)) as pool:
        list(pool.map(lambda item: probe_one(item, phase), items))
    print(f"entry-port-alias-probes-{phase}-ok: fresh TCP/UDP/auth sockets", flush=True)


def client_config(root, phase):
    spec = json.loads((root / f"{phase}.spec.json").read_text())
    links = [urllib.parse.urlsplit(line) for line in
             (root / f"{phase}.links").read_text().splitlines()]
    assert len(links) == len(spec["core"]["protocols"]) == 2
    links = {urllib.parse.unquote(link.fragment): link for link in links}
    config = dict(log=dict(level="warn"), inbounds=[], outbounds=[], route=dict(rules=[]))
    xray = dict(log=dict(loglevel="warning"), inbounds=[], outbounds=[], routing=dict(rules=[]))
    items = []
    local_port = 2081
    for entry in spec["core"]["protocols"]:
        core = entry["core"]
        link = links[entry["name"]]
        base, alias_port = PORTS[core]
        assert link.hostname == entry["server"] and link.port == (
            alias_port if phase == "selected" else base)
        print(f"entry-port-alias-share-port-{phase}: {core}={link.port}", flush=True)
        ports = [link.port, alias_port if link.port == base else base]
        for port in ports:
            alias = port == alias_port
            for auth in ("valid", "wrong"):
                tag = f"{core}-{port}-{auth}"
                if core == "xray":
                    reality = entry["reality"]
                    query = {key: value[0] for key, value in
                             urllib.parse.parse_qs(link.query).items()}
                    assert link.scheme == "vless" and link.username == entry["uuid"]
                    assert query["pbk"] == reality["public_key"] and query["sid"] == reality["short_id"]
                    xray["inbounds"].append(dict(
                        tag=tag, listen="127.0.0.1", port=local_port, protocol="socks",
                        settings=dict(auth="noauth", udp=False)))
                    xray["outbounds"].append(dict(
                        tag=tag, protocol="vless", settings=dict(vnext=[dict(
                            address=HOST, port=port, users=[dict(
                                id=link.username if auth == "valid" else
                                "99999999-9999-4999-8999-999999999999",
                                encryption=query["encryption"], flow=query["flow"])])]),
                        streamSettings=dict(network=query["type"], security=query["security"],
                                            realitySettings=dict(
                                                serverName=query["sni"], fingerprint=query["fp"],
                                                publicKey=query["pbk"], shortId=query["sid"]))))
                    xray["routing"]["rules"].append(dict(type="field", inboundTag=[tag],
                                                        outboundTag=tag))
                else:
                    ss = entry["shadowsocks"]
                    assert link.scheme == "ss" and urllib.parse.unquote(link.username) == ss["method"]
                    server_key, user_key = urllib.parse.unquote(link.password).split(":")
                    assert (server_key, user_key) == (ss["server_password"], ss["user_password"])
                    user_key = user_key if auth == "valid" else "AAAAAAAAAAAAAAAAAAAAAA=="
                    config["inbounds"].append(dict(type="socks", tag=tag, listen="127.0.0.1",
                                                   listen_port=local_port))
                    config["outbounds"].append(dict(
                        tag=tag, server=HOST, server_port=port, type="shadowsocks",
                        method=urllib.parse.unquote(link.username), password=server_key + ":" + user_key))
                    config["route"]["rules"].append(dict(inbound=[tag], action="route", outbound=tag))
                for transport in (("tcp",) if core == "xray" else ("tcp", "udp")):
                    items.append((local_port, core, alias, auth, transport))
                local_port += 1
    (root / "client.json").write_text(json.dumps(config))
    (root / "client-xray.json").write_text(json.dumps(xray))
    (root / "probes.json").write_text(json.dumps(items))


def inspect(docker, identity, core, phase):
    value = json.loads(command(docker + ["inspect", identity]))[0]
    host = value["HostConfig"]
    assert value["State"]["Running"] and value["Config"]["User"] == "10001:10001"
    assert host["ReadonlyRootfs"] and not host["Privileged"]
    assert host["CapDrop"] == ["ALL"] and not host["CapAdd"] and not host["Devices"]
    assert "no-new-privileges:true" in host["SecurityOpt"]
    fields = dict(line.split(":", 1) for line in
                  Path(f"/proc/{value['State']['Pid']}/status").read_text().splitlines()
                  if ":" in line)
    assert fields["Uid"].split() == ["10001"] * 4
    assert int(fields["CapEff"], 16) == 0 and int(fields["CapBnd"], 16) == 0
    base, alias = PORTS[core]
    for transport in (("tcp",) if core == "xray" else ("tcp", "udp")):
        expected = [dict(HostIp="0.0.0.0", HostPort=str(base))]
        if phase != "off":
            expected.append(dict(HostIp="0.0.0.0", HostPort=str(alias)))
        assert sorted(host["PortBindings"][f"{base}/{transport}"], key=lambda row: row["HostPort"]) == expected
    return value["NetworkSettings"]["Networks"]["padm-docker"]["IPAddress"]


def target_ready():
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    context.minimum_version = ssl.TLSVersion.TLSv1_3
    context.set_alpn_protocols(["http/1.1"])
    with socket.create_connection((HOST, TLS_PORT), timeout=0.2) as stream, \
            context.wrap_socket(stream, server_hostname="target.padm.test") as tls:
        assert tls.version() == "TLSv1.3" and tls.selected_alpn_protocol() == "http/1.1"
        tls.sendall(b"GET / HTTP/1.1\r\nHost: target.padm.test\r\nConnection: close\r\n\r\n")
        return tls.recv(1024).startswith(b"HTTP/1.0 200")


def run(root):
    assert os.getuid() == 0 and sys.platform == "linux" and Path("/.dockerenv").is_file()
    assert {item["ifname"] for item in json.loads(command(["ip", "-j", "link", "show"]))} == {
        "lo"}, "不得借用宿主接口或已有网络"
    inputs = json.loads(Path("/node-images.json").read_text())
    node = Path(tempfile.mkdtemp(prefix=".tmp-entry-alias-", dir="/n"))
    node.chmod(0o755)
    docker = ["docker", "--host", f"unix://{node}/docker.sock"]
    daemon, clients, processes = None, [], []
    started = time.monotonic()
    (root / "events.jsonl").touch()
    with (root / "daemon.log").open("wb") as daemon_log:
        try:
            daemon = subprocess.Popen([
                "dockerd", "--host", docker[-1], "--data-root", str(node / "docker"),
                "--exec-root", str(node / "run"), "--pidfile", str(node / "daemon.pid"),
                "--feature", "containerd-snapshotter=true", "--storage-driver", "overlayfs",
                "--bip", "172.30.0.1/24"], stdout=daemon_log, stderr=daemon_log)
            wait_ready(lambda: subprocess.run(docker + ["info"], capture_output=True).returncode == 0, 30)
            command(docker + ["load", "--input", "/node-images.tar"], timeout=120)
            for item in inputs.values():
                image = json.loads(command(docker + ["image", "inspect", item["reference"]]))[0]
                assert image["Id"] == item["image_id"]
            clients = namespaces()
            command(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                     "-subj", "/CN=target.padm.test", "-keyout", str(root / "target.key"),
                     "-out", str(root / "target.crt")])
            with (root / "target.log").open("wb") as log:
                origin = subprocess.Popen(["python3", str(SCRIPT), "fixture", str(root)],
                                          stdout=log, stderr=log)
            processes.append(origin)
            wait_ready(lambda: (root / "ready").is_file())
            wait_ready(target_ready)
            assert origin.poll() is None
            for core in PORTS:
                identity = command(docker + ["create", inputs[core]["image_id"]]).decode().strip()
                command(docker + ["cp", identity + f":/usr/local/bin/{core}", str(root / core)])
                command(docker + ["rm", identity])
                (root / core).chmod(0o755)
            for core in PORTS:
                config = json.loads((root / f"on.{core}.json").read_text())
                if core == "xray":
                    inbound = next(item for item in config["inbounds"] if item["tag"] == "entry-xray")
                    inbound["streamSettings"]["realitySettings"]["target"] = f"{HOST}:{TLS_PORT}"
                    assert inbound["settings"]["clients"][0]["id"] == \
                        "11111111-1111-4111-8111-111111111111"
                else:
                    assert config["experimental"]["v2ray_api"]["stats"]["users"] == [
                        "22222222-2222-4222-8222-222222222222"]
                path = node / f"{core}.json"
                path.write_text(json.dumps(config))
                path.chmod(0o644)
            enter = ["nsenter", "--target", str(clients[0].pid), "--net", "--"]
            for phase in ("on", "selected", "off"):
                client_config(root, phase)
                current = json.loads((root / f"{phase}.compose.json").read_text())
                current["services"] = {core: current["services"][core] for core in PORTS}
                for core, service in current["services"].items():
                    ports = list(service["ports"])
                    service.update(image=inputs[core]["image_id"],
                                   volumes=[dict(type="bind", source=str(node / f"{core}.json"),
                                                 target="/config.json", read_only=True)],
                                   entrypoint=[f"/usr/local/bin/{core}"],
                                   command=["run", "-c", "/config.json"],
                                   healthcheck=dict(disable=True), restart="no")
                    assert service["ports"] == ports
                path = node / "compose.json"
                path.write_text(json.dumps(current))
                compose = docker + ["compose", "--project-name", "padm-docker", "--file", str(path),
                                     "--profile", "core-xray", "--profile", "core-sing-box"]
                command(compose + ["up", "-d", "--pull", "never"], timeout=30)
                addresses = set()
                for core in PORTS:
                    identity = command(compose + ["ps", "-q", core]).decode().strip()
                    addresses.add(inspect(docker, identity, core, phase))
                published = [port for ports in PORTS.values()
                             for port in (ports if phase != "off" else ports[:1])]
                wait_ready(lambda: subprocess.run(
                    enter + ["python3", "-c",
                             "import socket; " + "; ".join(
                                 f"socket.create_connection(('{HOST}',{port}),.2).close()"
                                 for port in published)],
                    capture_output=True).returncode == 0)
                phase_clients = []
                for core, filename in (("xray", "client-xray.json"), ("sing-box", "client.json")):
                    with (root / f"client-{core}-{phase}.log").open("wb") as log:
                        client = subprocess.Popen(enter + [str(root / core), "run", "-c",
                                                           str(root / filename)],
                                                  stdout=log, stderr=log)
                    processes.append(client)
                    phase_clients.append(client)
                wait_ready(lambda: subprocess.run(
                    enter + ["python3", "-c",
                             "import socket; socket.create_connection(('127.0.0.1',2081),.1).close(); "
                             "socket.create_connection(('127.0.0.1',2085),.1).close()"],
                    capture_output=True).returncode == 0)
                assert all(client.poll() is None for client in phase_clients) and origin.poll() is None
                before = len((root / "events.jsonl").read_text().splitlines())
                output = command(enter + ["python3", str(SCRIPT), "probes", str(root), phase], timeout=10)
                print(output.decode().strip(), flush=True)
                events = [json.loads(line) for line in
                          (root / "events.jsonl").read_text().splitlines()[before:]]
                assert {row["source"] for row in events} <= addresses
                assert {transport: sum(row["transport"] == transport for row in events)
                        for transport in ("tcp", "udp")} == (
                            dict(tcp=4, udp=2) if phase != "off" else dict(tcp=2, udp=1)), events
                assert all(client.poll() is None for client in phase_clients) and origin.poll() is None
                for client in phase_clients:
                    stop(client)
                print(f"entry-port-alias-{phase}: production ports/NAT/auth/UID10001/cap0/ro passed",
                      flush=True)
            print("entry-port-alias-real-environment=" + json.dumps(dict(
                host=HOST, image_ids=inputs, elapsed=round(time.monotonic() - started, 3))),
                  flush=True)
        except BaseException:
            print("entry-port-alias-origin-events=" + (root / "events.jsonl").read_text(),
                  file=sys.stderr)
            result = subprocess.run(docker + ["ps", "-aq"], capture_output=True, timeout=10)
            for identity in result.stdout.decode().split() if not result.returncode else []:
                log = subprocess.run(docker + ["logs", identity], capture_output=True, timeout=10)
                print((log.stdout + log.stderr).decode(errors="replace"), file=sys.stderr)
            raise
        finally:
            active_error = sys.exc_info()[0] is not None
            for process in processes + clients:
                stop(process)
            if daemon is not None:
                try:
                    result = subprocess.run(docker + ["ps", "-aq"], capture_output=True, timeout=5)
                    if not result.returncode and result.stdout.strip():
                        command(docker + ["rm", "-f"] + result.stdout.decode().split(), timeout=15)
                finally:
                    stop(daemon)
            if active_error:
                print((root / "daemon.log").read_text()[-4000:], file=sys.stderr)
            assert node.parent == Path("/n") and node.name.startswith(".tmp-entry-alias-")
            shutil.rmtree(node)


if __name__ == "__main__":
    if sys.argv[1] == "fixture":
        fixture(Path(sys.argv[2]))
    elif sys.argv[1] == "probes":
        probes(Path(sys.argv[2]), sys.argv[3])
    else:
        run(Path(sys.argv[1]))
