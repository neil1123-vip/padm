#!/usr/bin/env python3
import concurrent.futures
import http.server
import json
import os
from pathlib import Path
import re
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
HOSTS = helpers["HOSTS"]
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
    local_port, core, family, alias, auth, transport = item
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
                address = {"0.0.0.0": "127.0.0.1", "::": "::1"}.get(address, address)
                socket_family = socket.AF_INET6 if ":" in address else socket.AF_INET
                bind = ("::1", 0) if socket_family == socket.AF_INET6 else ("127.0.0.1", 0)
                destination = (address, port, 0, 0) if socket_family == socket.AF_INET6 else (address, port)
                with socket.socket(socket_family, socket.SOCK_DGRAM) as stream:
                    stream.bind(bind)
                    stream.settimeout(timeout)
                    payload = BODY + struct.pack("!H", local_port) + phase.encode()
                    stream.sendto(b"\x00\x00\x00\x01" + socket.inet_aton(HOST) +
                                  struct.pack("!H", UDP_PORT) + payload, destination)
                    response, _ = stream.recvfrom(65535)
                    assert response[:4] == b"\x00\x00\x00\x01"
                    accepted = response[10:] == payload
    except (OSError, EOFError) as error:
        failure = f"{type(error).__name__}: {error}"
    if accepted != expected:
        print(f"entry-port-alias-probe-failure: phase={phase} core={core} family={family} alias={alias} "
              f"auth={auth} transport={transport} elapsed={time.monotonic()-started:.3f}s "
              f"error={failure}", file=sys.stderr)
    assert accepted == expected, (phase, core, family, alias, auth, transport, accepted)


def probes(root, phase):
    items = json.loads((root / "probes.json").read_text())
    if phase == "off":
        for host in HOSTS.values():
            for _, alias in PORTS.values():
                try:
                    with socket.create_connection((host, alias), timeout=0.3):
                        raise AssertionError(f"{host}:{alias} 移除后仍接受新 TCP 连接")
                except ConnectionRefusedError:
                    pass
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(items)) as pool:
        list(pool.map(lambda item: probe_one(item, phase), items))
    print(f"entry-port-alias-probes-{phase}-ok: IPv4+IPv6 fresh TCP/UDP/auth sockets", flush=True)


def client_config(root, phase):
    spec = json.loads((root / f"{phase}.spec.json").read_text())
    links = [urllib.parse.urlsplit(line) for line in
             (root / f"{phase}.links").read_text().splitlines()]
    assert len(links) == len(spec["core"]["protocols"]) == 2
    links = {urllib.parse.unquote(link.fragment): link for link in links}
    family_links = {}
    for family in HOSTS:
        parsed = [urllib.parse.urlsplit(line) for line in
                  (root / f"{phase}.{family}.links").read_text().splitlines()]
        assert len(parsed) == len(links)
        family_links[family] = {urllib.parse.unquote(link.fragment): link for link in parsed}
    config = dict(log=dict(level="warn"), inbounds=[], outbounds=[], route=dict(rules=[]))
    xray = dict(log=dict(loglevel="warning"), inbounds=[], outbounds=[], routing=dict(rules=[]))
    items = []
    local_port = 2081
    for entry in spec["core"]["protocols"]:
        core = entry["core"]
        base, alias_port = PORTS[core]
        original = links[entry["name"]]
        assert original.hostname == entry["server"] and original.port == (
            alias_port if phase == "selected" else base)
        for family, host in HOSTS.items():
            link = family_links[family][entry["name"]]
            assert link.hostname == host and link.port == original.port
            assert link.scheme == original.scheme and link.username == original.username
            assert link.password == original.password and link.query == original.query
            if family == "ipv6":
                assert f"@[{host}]:{link.port}" in link.geturl()
            print(f"entry-port-alias-share-port-{phase}: {core}/{family}={link.port}", flush=True)
            ports = [link.port, alias_port if link.port == base else base]
            for port in ports:
                alias = port == alias_port
                for auth in ("valid", "wrong"):
                    tag = f"{core}-{family}-{port}-{auth}"
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
                                address=link.hostname, port=port, users=[dict(
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
                            tag=tag, server=link.hostname, server_port=port, type="shadowsocks",
                            method=urllib.parse.unquote(link.username), password=server_key + ":" + user_key))
                        config["route"]["rules"].append(dict(inbound=[tag], action="route", outbound=tag))
                    for transport in (("tcp",) if core == "xray" else ("tcp", "udp")):
                        items.append((local_port, core, family, alias, auth, transport))
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
        expected = [dict(HostIp=address, HostPort=str(port))
                    for address in ("0.0.0.0", "::")
                    for port in ((base, alias) if phase != "off" else (base,))]
        bindings = host["PortBindings"][f"{base}/{transport}"]
        assert sorted(host["PortBindings"][f"{base}/{transport}"],
                      key=lambda row: (row["HostIp"], row["HostPort"])) == sorted(
                          expected, key=lambda row: (row["HostIp"], row["HostPort"])), bindings
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


def port_range_capabilities(root, image_id):
    binary = str(root / "sing-box")
    version = command([binary, "version"]).decode().strip()
    for protocol in ("hysteria2", "tuic"):
        outbound = dict(type=protocol, tag="range-client", server=HOST, server_port=36461,
                        password="11111111-1111-4111-8111-111111111111",
                        tls=dict(enabled=True, server_name="target.padm.test", alpn=["h3"],
                                 certificate_path=str(root / "target.crt")))
        if protocol == "tuic":
            outbound["uuid"] = "11111111-1111-4111-8111-111111111111"
        for mode in ("single", "range"):
            if mode == "range":
                del outbound["server_port"]
                outbound["server_ports"] = ["36461:36462"]
            path = root / "port-range-client.json"
            path.write_text(json.dumps(dict(outbounds=[outbound])))
            result = subprocess.run([binary, "check", "-c", str(path)],
                                    capture_output=True, text=True, timeout=10)
            print("entry-port-range-capability=" + json.dumps(dict(
                protocol=protocol, mode=mode, image_id=image_id, version=version,
                exit_code=result.returncode, stdout=result.stdout, stderr=result.stderr)),
                  flush=True)
            # 基线先通过，才能把范围失败归因于客户端字段能力。
            if mode == "single" or protocol == "hysteria2":
                assert result.returncode == 0, result.stderr
            else:
                assert result.returncode != 0 and "server_ports" in result.stderr and \
                    "unknown field" in result.stderr, result.stderr


def hy2_dnat_probe(root, cert, enter, off_enter, processes, server_address):
    # 仅在本轮隔离宿主 netns 验证双栈 DNAT 到已有发布口；不提供生产管理入口。
    token = os.urandom(16).hex()
    chain = "PADM_HOP_" + token[:12]
    comment = "padm-hop:" + token
    owned, outside = [], []
    baseline = {}
    client = dict(log=dict(level="warn"), inbounds=[], outbounds=[], route=dict(rules=[]))
    items = []
    for family, address in HOSTS.items():
        for remote_port in (36561, 36562):
            tag = f"hy2-dnat-{family}-{remote_port}"
            local_port = 24101 + len(client["inbounds"])
            client["inbounds"].append(dict(type="socks", tag=tag, listen="127.0.0.1",
                                           listen_port=local_port))
            client["outbounds"].append(dict(
                type="hysteria2", tag=tag, server=address, server_port=remote_port,
                password="33333333-3333-4333-8333-333333333333",
                tls=dict(enabled=True, server_name="hy2.padm.test", alpn=["h3"],
                         certificate_path=str(cert))))
            client["route"]["rules"].append(dict(inbound=[tag], action="route", outbound=tag))
            items.extend((local_port, "hy2", family, True, "valid", transport)
                         for transport in ("tcp", "udp"))
    path = root / "hy2-dnat-client.json"
    path.write_text(json.dumps(client))
    command([str(root / "sing-box"), "check", "-c", str(path)])

    def add(table, arguments, ledger):
        command([table, "-w", "-t", "nat"] + arguments)
        if arguments[0] == "-N":
            removal = ["-X", arguments[1]]
        elif arguments[0] == "-I":
            removal = ["-D", arguments[1]] + arguments[3:]
        else:
            removal = ["-D"] + arguments[1:]
        ledger.append((table, removal))

    def revoke(ledger):
        while ledger:
            table, arguments = ledger[-1]
            command([table, "-w", "-t", "nat"] + arguments)
            ledger.pop()

    def snapshot(table):
        return command([table, "-w", "-t", "nat", "-S"])

    try:
        for family, address in HOSTS.items():
            table = "iptables" if family == "ipv4" else "ip6tables"
            assert "(nf_tables)" in command([table, "--version"]).decode()
            add(table, ["-N", "PADM_HOP_OUTSIDE"], outside)
            add(table, ["-A", "PADM_HOP_OUTSIDE", "-m", "comment",
                        "--comment", "outside-hop", "-j", "RETURN"], outside)
            add(table, ["-A", "PREROUTING", "-i", "prh2", "-p", "udp", "-d", address,
                        "--dport", "36999", "-j", "PADM_HOP_OUTSIDE"], outside)
            baseline[table] = snapshot(table)
        for stage in ("on", "off", "restored"):
            if stage == "off":
                revoke(owned)
                for table in baseline:
                    assert snapshot(table) == baseline[table], "撤销改变了 Docker 或外部 NAT 规则"
            else:
                for family, address in HOSTS.items():
                    table = "iptables" if family == "ipv4" else "ip6tables"
                    target = f"{address}:35461" if family == "ipv4" else f"[{address}]:35461"
                    add(table, ["-N", chain], owned)
                    add(table, ["-A", chain, "-p", "udp", "-d", address,
                                "--dport", "36561:36562", "-m", "comment", "--comment", comment,
                                "-j", "DNAT", "--to-destination", target], owned)
                    add(table, ["-I", "PREROUTING", "1", "-i", "prh+", "-p", "udp", "-d", address,
                                "--dport", "36561:36562", "-m", "comment", "--comment", comment,
                                "-j", chain], owned)
            # 撤销用此前无跳跃流量的第二来源，避免旧 QUIC/conntrack 掩盖新连接结果。
            stage_enter = enter if stage == "on" else off_enter
            log_path = root / f"client-hy2-dnat-{stage}.log"
            with log_path.open("wb") as log:
                process = subprocess.Popen(stage_enter + [str(root / "sing-box"), "run", "-c", str(path)],
                                           stdout=log, stderr=log)
            processes.append(process)
            wait_ready(lambda: subprocess.run(
                stage_enter + ["python3", "-c", "import socket; socket.create_connection("
                         "('127.0.0.1',24101),.2).close()"], capture_output=True).returncode == 0)
            before = len((root / "events.jsonl").read_text().splitlines())
            rows = items if stage != "off" else [
                (*item[:4], "removed", item[5]) for item in items]
            (root / "probes.json").write_text(json.dumps(rows))
            print(command(stage_enter + ["python3", str(SCRIPT), "probes", str(root),
                                   f"hy2-dnat-{stage}"], timeout=5).decode().strip(), flush=True)
            events = [json.loads(line) for line in
                      (root / "events.jsonl").read_text().splitlines()[before:]]
            if stage == "off":
                assert not events, events
            else:
                assert {row["source"] for row in events} == {server_address}, events
                assert {transport: sum(row["transport"] == transport for row in events)
                        for transport in ("tcp", "udp")} == dict(tcp=4, udp=4), events
            assert process.poll() is None
            stop(process)
            print("entry-hy2-dnat-proof=" + json.dumps(dict(
                stage=stage, token=token, chain=chain, events=len(events),
                client_pid=process.pid, fresh_client=True, families=list(HOSTS),
                client_scope="first-source" if stage == "on" else "second-source",
                target_port=35461, range=[36561, 36562], backend="iptables-nft")), flush=True)
        revoke(owned)
        for table in baseline:
            assert snapshot(table) == baseline[table], "重建后撤销改变了非本轮规则"
    finally:
        revoke(owned)
        revoke(outside)


def hy2_range_probe(root, node, docker, image_id, enter, off_enter, processes):
    cert, key = node / "hy2.crt", node / "hy2.key"
    command(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
             "-subj", "/CN=hy2.padm.test", "-addext", "subjectAltName=DNS:hy2.padm.test",
             "-keyout", str(key), "-out", str(cert)])
    os.chown(key, 10001, 10001)
    key.chmod(0o600)
    config_path = node / "hy2.json"
    config_path.write_bytes((root / "hy2.json").read_bytes())
    config_path.chmod(0o644)
    current = json.loads((root / "hy2.compose.json").read_text())
    service = current["services"]["sing-box"]
    current["services"] = {"sing-box": service}
    service.update(image=image_id, entrypoint=["/usr/local/bin/sing-box"],
                   command=["run", "-c", "/config.json"],
                   healthcheck=dict(disable=True), restart="no",
                   volumes=[dict(type="bind", source=str(source), target=target, read_only=True)
                            for source, target in (
                                (config_path, "/config.json"),
                                (cert, "/etc/padm/secrets/tls/hy2.padm.test.crt"),
                                (key, "/etc/padm/secrets/tls/hy2.padm.test.key"))])
    compose_path = node / "hy2.compose.json"
    compose_path.write_text(json.dumps(current))
    compose = docker + ["compose", "--project-name", "padm-docker", "--file", str(compose_path),
                       "--profile", "core-sing-box"]
    command(compose + ["up", "-d", "--pull", "never"], timeout=30)
    identity = command(compose + ["ps", "-q", "sing-box"]).decode().strip()
    value = json.loads(command(docker + ["inspect", identity]))[0]
    host = value["HostConfig"]
    assert value["State"]["Running"] and value["Config"]["Image"] == image_id
    assert value["Config"]["User"] == "10001:10001" and host["ReadonlyRootfs"]
    assert not host["Privileged"] and host["CapDrop"] == ["ALL"] and not host["CapAdd"]
    assert not host["Devices"] and "no-new-privileges:true" in host["SecurityOpt"]
    expected = [
        dict(HostIp=address, HostPort=str(port))
        for port in (35461, 36461, 36462) for address in ("0.0.0.0", "::")]
    assert set(host["PortBindings"]) == {"35461/udp"}
    assert sorted(host["PortBindings"]["35461/udp"],
                  key=lambda row: (row["HostIp"], row["HostPort"])) == sorted(
                      expected, key=lambda row: (row["HostIp"], row["HostPort"])), host["PortBindings"]
    server_address = value["NetworkSettings"]["Networks"]["padm-docker"]["IPAddress"]
    for mode in ("fixed", "range"):
        client = dict(log=dict(level="warn"), inbounds=[], outbounds=[], route=dict(rules=[]))
        items, negative = [], []
        for family, address in HOSTS.items():
            for remote_port in ((36461, 36462) if mode == "fixed" else (0,)):
                cases = ("valid", "wrong", "wrong-sni", "untrusted") if (
                    mode == "fixed" and remote_port == 36461) else ("valid",)
                for auth in cases:
                    local_port = 24001 + len(client["inbounds"])
                    tag = f"hy2-{family}-{remote_port}-{auth}"
                    outbound = dict(type="hysteria2", tag=tag, server=address,
                                    password="33333333-3333-4333-8333-333333333333",
                                    tls=dict(enabled=True, server_name="hy2.padm.test", alpn=["h3"],
                                             certificate_path=str(cert)))
                    if mode == "range":
                        outbound.update(server_ports=["36461:36462"], hop_interval="5s")
                    else:
                        outbound["server_port"] = remote_port
                    if auth == "wrong":
                        outbound["password"] = "wrong-password"
                    elif auth == "wrong-sni":
                        outbound["tls"]["server_name"] = "wrong.padm.test"
                    elif auth == "untrusted":
                        del outbound["tls"]["certificate_path"]
                    client["inbounds"].append(dict(type="socks", tag=tag, listen="127.0.0.1",
                                                   listen_port=local_port))
                    client["outbounds"].append(outbound)
                    client["route"]["rules"].append(dict(inbound=[tag], action="route", outbound=tag))
                    rows = [(local_port, "hy2", family, True, auth, transport)
                            for transport in ("tcp", "udp")]
                    (items if auth == "valid" else negative).extend(rows)
        path = root / "hy2-client.json"
        path.write_text(json.dumps(client))
        command([str(root / "sing-box"), "check", "-c", str(path)])
        counters = {}
        if mode == "range":
            # 计数链只在本次客户端 netns 内；固定端口进程已退出，不混入其它流量。
            for family, address in HOSTS.items():
                table = "iptables" if family == "ipv4" else "ip6tables"
                chain = "PADM_HY2_RANGE"
                command(enter + [table, "-w", "-t", "mangle", "-N", chain])
                for port in (36461, 36462):
                    command(enter + [table, "-w", "-t", "mangle", "-A", chain, "-p", "udp",
                                     "-d", address, "--dport", str(port), "-j", "RETURN"])
                command(enter + [table, "-w", "-t", "mangle", "-A", "OUTPUT", "-p", "udp",
                                 "-d", address, "--dport", "36461:36462", "-j", chain])
        log_path = root / f"client-hy2-{mode}.log"
        with log_path.open("wb") as log:
            process = subprocess.Popen(enter + [str(root / "sing-box"), "run", "-c", str(path)],
                                       stdout=log, stderr=log)
        processes.append(process)
        wait_ready(lambda: subprocess.run(
            enter + ["python3", "-c", f"import socket; socket.create_connection(('127.0.0.1',"
                     f"{items[0][0]}),.2).close()"], capture_output=True).returncode == 0)
        before = len((root / "events.jsonl").read_text().splitlines())
        rounds = 2 if mode == "range" else 1
        started = None
        for round_number in range(rounds):
            assert process.poll() is None
            (root / "probes.json").write_text(json.dumps(items))
            print(command(enter + ["python3", str(SCRIPT), "probes", str(root), f"hy2-{mode}"],
                          timeout=5).decode().strip(), flush=True)
            if mode == "range" and round_number == 0:
                # 从真实首次回显后计时；只补一轮跨最小间隔的新请求。
                started = time.monotonic()
                time.sleep(5.1)
            elif started is None:
                started = time.monotonic()
        if mode == "range":
            for family in HOSTS:
                table = "iptables-save" if family == "ipv4" else "ip6tables-save"
                raw = command(enter + [table, "-c", "-t", "mangle"]).decode()
                counters[family] = {int(port): int(packets) for packets, port in re.findall(
                    r"^\[(\d+):\d+\] -A PADM_HY2_RANGE .*--dport (\d+) -j RETURN$", raw, re.M)}
                assert set(counters[family]) == {36461, 36462}, raw
                assert sum(counters[family].values()) > 0, counters
        events = [json.loads(line) for line in (root / "events.jsonl").read_text().splitlines()[before:]]
        assert {row["source"] for row in events} == {server_address}, events
        assert {transport: sum(row["transport"] == transport for row in events)
                for transport in ("tcp", "udp")} == dict(tcp=len(items) // 2 * rounds,
                                                        udp=len(items) // 2 * rounds), events
        assert process.poll() is None
        print("entry-hy2-range-proof=" + json.dumps(dict(
            mode=mode, counters=counters, rounds=rounds, client_pid=process.pid,
            same_client_alive=True, events=len(events), destination_family="ipv4",
            observed_both_ports={family: all(count > 0 for count in ports.values())
                                 for family, ports in counters.items()},
            elapsed=round(time.monotonic() - started, 3))), flush=True)
        if negative:
            before = len((root / "events.jsonl").read_text().splitlines())
            (root / "probes.json").write_text(json.dumps(negative))
            print(command(enter + ["python3", str(SCRIPT), "probes", str(root), "hy2-negative"],
                          timeout=5).decode().strip(), flush=True)
            assert len((root / "events.jsonl").read_text().splitlines()) == before
            diagnostic = log_path.read_text()
            rejections = []
            for family in HOSTS:
                for auth, expected in (("wrong", "auth"), ("wrong-sni", "x509"),
                                       ("untrusted", "unknown authority")):
                    matches = [line for line in diagnostic.splitlines()
                               if f"hy2-{family}-36461-{auth}" in line and expected in line.lower()]
                    assert matches, diagnostic
                    rejections.append(dict(family=family, case=auth, diagnostic=matches[0]))
            print("entry-hy2-rejections=" + json.dumps(rejections), flush=True)
        stop(process)
    hy2_dnat_probe(root, cert, enter, off_enter, processes, server_address)


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
            port_range_capabilities(root, inputs["sing-box"]["image_id"])
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
                assert not current["networks"]["default"].get("enable_ipv6", False)
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
                                 f"socket.create_connection(('{host}',{port}),.2).close()"
                                 for host in HOSTS.values() for port in published)],
                    capture_output=True).returncode == 0)
                phase_clients = []
                for core, filename in (("xray", "client-xray.json"), ("sing-box", "client.json")):
                    with (root / f"client-{core}-{phase}.log").open("wb") as log:
                        client = subprocess.Popen(enter + [str(root / core), "run", "-c",
                                                           str(root / filename)],
                                                  stdout=log, stderr=log)
                    processes.append(client)
                    phase_clients.append(client)
                local_ports = [json.loads((root / filename).read_text())["inbounds"][0].get(
                    "port" if core == "xray" else "listen_port")
                    for core, filename in (("xray", "client-xray.json"), ("sing-box", "client.json"))]
                wait_ready(lambda: subprocess.run(
                    enter + ["python3", "-c",
                             "import socket; " + "; ".join(
                                 f"socket.create_connection(('127.0.0.1',{port}),.1).close()"
                                 for port in local_ports)],
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
                            dict(tcp=8, udp=4) if phase != "off" else dict(tcp=4, udp=2)), events
                assert all(client.poll() is None for client in phase_clients) and origin.poll() is None
                for client in phase_clients:
                    stop(client)
                print(f"entry-port-alias-{phase}: IPv4+IPv6 production ports/NAT/auth/UID10001/cap0/ro passed",
                      flush=True)
            off_enter = ["nsenter", "--target", str(clients[1].pid), "--net", "--"]
            hy2_range_probe(root, node, docker, inputs["sing-box"]["image_id"],
                            enter, off_enter, processes)
            print("entry-port-alias-real-environment=" + json.dumps(dict(
                hosts=HOSTS, destination_family="ipv4", image_ids=inputs,
                elapsed=round(time.monotonic() - started, 3))),
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
