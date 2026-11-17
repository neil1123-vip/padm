#!/usr/bin/env python3
"""在隔离 daemon 中验证五个候选镜像的实际运行合同。"""

import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hashlib
import json
import os
from pathlib import Path
import socket
import socketserver
import struct
import subprocess
import threading
import time


ROOT = Path(__file__).resolve().parents[2]
INPUTS = json.loads(Path("/node-images.json").read_text(encoding="utf-8-sig"))
RUNNING = []


def command(arguments, timeout=30, env=None):
    result = subprocess.run(arguments, capture_output=True, text=True, timeout=timeout, env=env)
    assert result.returncode == 0, f"{arguments}: {result.stdout}\n{result.stderr}"
    return result.stdout


def docker(*arguments, timeout=30):
    return command(["docker", *arguments], timeout)


def inspect(identity):
    return json.loads(docker("inspect", identity))[0]


def wait_ready(check):
    for _ in range(100):
        if check():
            return
        time.sleep(0.1)
    raise AssertionError("候选镜像未就绪")


def options(name, network="none"):
    result = ["--init", "--network", network, "--read-only", "--cap-drop", "ALL",
              "--security-opt", "no-new-privileges:true", "--pids-limit", "256",
              "--tmpfs", "/tmp:rw,noexec,nosuid,nodev,size=32m,mode=1777"]
    writable = {
        "xray": "/var/lib/padm/xray", "sing-box": "/var/lib/padm/sing-box",
        "ops": "/var/lib/padm", "net": "/var/lib/padm/net",
    }
    if name in writable:
        owner = "0" if name == "net" else "10001"
        result += ["--tmpfs", writable[name] + f":rw,uid={owner},gid={owner}"]
    if name == "net":
        result += ["--tmpfs", "/run:rw"]
    return result


def image(name):
    return INPUTS[name]["image_id"]


def shell(name, script, extra=(), network="none"):
    return docker("run", "--rm", *options(name, network), *extra, "--entrypoint", "/bin/sh",
                  image(name), "-ec", script)


def start(name, mounts=(), arguments=()):
    # host 指回归容器自己的隔离网络空间，外层只有 lo 且没有宿主 Socket。
    identity = docker("run", "-d", *options(name, "host"), *mounts,
                      "--health-interval", "1s", "--health-start-period", "1s",
                      image(name), *arguments).strip()
    RUNNING.append(identity)
    wait_ready(lambda: inspect(identity)["State"].get("Health", {}).get("Status") == "healthy")
    value = inspect(identity)
    assert value["State"]["Running"] and value["HostConfig"]["ReadonlyRootfs"]
    assert value["HostConfig"]["CapDrop"] == ["ALL"]
    return identity


def mount(source, destination):
    return ["--mount", f"type=bind,source={source},target={destination},readonly"]


def receive(connection, length):
    result = b""
    while len(result) < length:
        block = connection.recv(length - len(result))
        assert block, "SOCKS 提前断开"
        result += block
    return result


def proxy(port):
    with socket.create_connection(("127.0.0.1", port), timeout=5) as connection:
        connection.sendall(b"\x05\x01\x00")
        assert receive(connection, 2) == b"\x05\x00"
        connection.sendall(b"\x05\x01\x00\x01\x7f\x00\x00\x01" + struct.pack("!H", 18080))
        response = receive(connection, 4)
        assert response[:2] == b"\x05\x00"
        if response[3] == 1:
            receive(connection, 6)
        elif response[3] == 4:
            receive(connection, 18)
        else:
            receive(connection, receive(connection, 1)[0] + 2)
        connection.sendall(b"GET / HTTP/1.0\r\nHost: runtime.padm.test\r\n\r\n")
        body = b""
        while block := connection.recv(4096):
            body += block
        assert b"200 OK" in body and body.endswith(b"distroless-runtime-ok\n"), body


class Origin(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"distroless-runtime-ok\n")

    def log_message(self, *_):
        pass


class DNS(socketserver.BaseRequestHandler):
    def handle(self):
        data, connection = self.request
        question = b"\x07runtime\x04padm\x04test\x00\x00\x01\x00\x01"
        if data[12:12 + len(question)] != question:
            return
        answer = b"\xc0\x0c\x00\x01\x00\x01\x00\x00\x00\x3c\x00\x04\x7f\x00\x00\x01"
        connection.sendto(
            data[:2] + b"\x81\x80\x00\x01\x00\x01\x00\x00\x00\x00" + question + answer,
            self.client_address,
        )


def subscription_http(fixture):
    root = fixture / "subscription"
    root.mkdir(mode=0o750)
    root.chmod(0o750)
    os.chown(root, 0, 10001)
    token, content = "0123456789abcdef", b"distroless-subscription-ok\n"
    path = root / token
    path.write_bytes(content)
    path.chmod(0o640)
    os.chown(path, 0, 10001)
    identity = start("ops", [
        *mount(root, "/var/lib/padm/subscription"),
        "--health-cmd", "/usr/local/bin/padm-entrypoint subscription-health",
    ], ("subscription", "--bind", "127.0.0.1"))
    for path, status, body in ((f"/{token}", 200, content), ("/missing-token-1234", 404, None)):
        connection = http.client.HTTPConnection("127.0.0.1", 8081, timeout=5)
        try:
            connection.request("GET", path)
            response = connection.getresponse()
            received = response.read()
            assert response.status == status, (response.status, received)
            if body is not None:
                assert received == body and response.getheader("Cache-Control") == "no-store"
        finally:
            connection.close()
    docker("exec", identity, "/usr/local/bin/padm-entrypoint", "subscription-health")
    print("distroless-real:ops:subscription-http-health-ok", flush=True)


def control_http(fixture):
    root = fixture / "control"
    root.mkdir(mode=0o750)
    root.chmod(0o750)
    os.chown(root, 0, 10001)
    address, peer, port = "10.231.0.1", "10.231.0.2", 39778
    token = "a" * 48
    state = {
        "schema_version": 2, "role": "main",
        "node_id": "11111111-1111-4111-8111-111111111111", "revision": 7,
        "listen": {"interface": "wg-padm", "address": address, "port": port},
        "peers": [{"id": "22222222-2222-4222-8222-222222222222", "address": peer,
                   "enabled": True, "expires_at": int(time.time()) + 3600,
                   "token_sha256": hashlib.sha256(token.encode("ascii")).hexdigest()}],
        "accounts": [{"id": "33333333-3333-4333-8333-333333333333", "name": "runtime",
                      "enabled": True, "uuid": "44444444-4444-4444-8444-444444444444",
                      "password": "b" * 48, "shadowsocks_password": None}],
    }
    path = root / "state.json"
    path.write_text(json.dumps(state), encoding="ascii")
    path.chmod(0o640)
    os.chown(path, 0, 10001)
    links = json.loads(shell("net", "ip -j link show", network="host"))
    assert {link["ifname"] for link in links} == {"lo"}, "控制 HTTP 冒烟必须使用隔离网络空间"
    try:
        # 只验证 HTTP、真实接口地址和无权限运行，不证明 WireGuard 握手或传输。
        shell("net", f"""
            ip link set lo up
            ip link add wg-padm type wireguard
            ip address add {address}/30 dev wg-padm
            ip address add {peer}/32 dev wg-padm
            ip link set wg-padm up
        """, ["--cap-add", "NET_ADMIN"], network="host")
        identity = start("ops", [
            *mount(root, "/fixtures/control"),
            "--health-cmd", "/usr/local/bin/padm-entrypoint control-health --state /fixtures/control/state.json",
        ], ("control", "--state", "/fixtures/control/state.json"))

        def request(endpoint, bearer=None, version="1"):
            connection = http.client.HTTPConnection(address, port, timeout=5, source_address=(peer, 0))
            headers = {"X-Padm-Control-Version": version}
            if bearer is not None:
                headers["Authorization"] = "Bearer " + bearer
            try:
                connection.request("GET", endpoint, headers=headers)
                response = connection.getresponse()
                assert response.getheader("Cache-Control") == "no-store"
                return response.status, json.loads(response.read())
            finally:
                connection.close()

        assert request("/v1/health") == (401, {"ok": False, "error": "unauthorized"})
        status, health = request("/v1/health", token)
        assert status == 200 and health == {
            "ok": True, "api_version": 1, "controller_id": state["node_id"],
            "node_id": state["peers"][0]["id"], "revision": 7, "capabilities": ["health", "desired"],
        }
        status, desired = request("/v1/desired", token)
        assert status == 200 and desired == {
            "ok": True, "api_version": 1, "controller_id": state["node_id"],
            "node_id": state["peers"][0]["id"], "revision": 7, "accounts": state["accounts"],
        }
        assert request("/v1/health", "c" * 48) == (401, {"ok": False, "error": "unauthorized"})
        assert request("/v1/health", token, "2") == (
            409, {"ok": False, "error": "api_version_mismatch", "api_version": 1})
        docker("exec", identity, "/usr/local/bin/padm-entrypoint", "control-health",
               "--state", "/fixtures/control/state.json")
        print("distroless-real:ops:control-http-interface-auth-ok", flush=True)
    finally:
        shell("net", """
            [ ! -e /sys/class/net/wg-padm ] || ip link delete wg-padm
        """, ["--cap-add", "NET_ADMIN"], network="host")


def main():
    assert os.getuid() == 0 and Path("/.dockerenv").is_file()
    assert os.environ["DOCKER_HOST"].startswith("unix:///n/")
    fixture = Path(os.environ["DOCKER_HOST"][7:]).parent / "runtime"
    fixture.mkdir(mode=0o755)
    for name in ("xray", "sing-box", "nginx", "ops", "net"):
        value = json.loads(docker("image", "inspect", INPUTS[name]["reference"]))[0]
        assert value["Id"] == image(name)
        assert value["Config"]["User"] == ("0:0" if name == "net" else "10001:10001")
        assert value["Config"]["StopSignal"] == ("SIGQUIT" if name == "nginx" else "SIGTERM")
        shell(name, """
            test -s /usr/share/padm/runtime-files.txt
            test -s /usr/share/padm/runtime-packages.txt
            test -s /usr/share/doc/busybox-static/copyright
            test -s /usr/share/common-licenses/GPL-2
            test -f /etc/ssl/certs/ca-certificates.crt
            test -z "$(/bin/busybox find /usr -name __pycache__ -o -name '*.pyc')"
            ! command -v apt-get
            ! command -v apk
            ! command -v dpkg
            ! command -v rpm
            ! command -v pip
            ! command -v pip3
            awk '/^Uid:/{if ($2 != """ + ("0" if name == "net" else "10001") + """) exit 1}' /proc/self/status
        """)

    resolv = fixture / "resolv.conf"
    resolv.write_text("nameserver 127.0.0.1\noptions timeout:1 attempts:1\n")
    for name in ("ops", "net"):
        shell(name, """
            python3 -c 'import ctypes, grp, locale, os, pathlib, pwd, socket, sys, time
assert pwd.getpwnam("padm").pw_uid == pwd.getpwuid(10001).pw_uid == 10001
assert grp.getgrnam("padm").gr_gid == grp.getgrgid(10001).gr_gid == 10001
assert locale.setlocale(locale.LC_ALL, "C") == "C"
assert sys.getfilesystemencoding() == "utf-8"
assert "\\u4e2d\\u6587".encode("gb18030").decode("gb18030") == "\\u4e2d\\u6587"
assert socket.gethostbyname("localhost") == "127.0.0.1"
assert socket.gethostbyname("runtime.padm.test") == "127.0.0.1"
os.environ["TZ"] = "Asia/Shanghai"
time.tzset()
assert time.localtime(0).tm_hour == 8
assert not any(path.name.startswith(("_test", "_xxtest", "_ctypes_test", "xx")) for directory in pathlib.Path("/usr").rglob("lib-dynload") for path in directory.glob("*.so"))'
        """ + ("""
            curl --noproxy '*' --ipv4 --fail --silent --show-error --max-time 5 \
                http://runtime.padm.test:18080/ | grep -q distroless-runtime-ok
        """ if name == "ops" else ""), mount(resolv, "/etc/resolv.conf"), network="host")
        print(f"distroless-real:{name}:nss-dns-locale-stdlib-ok", flush=True)

    shell("sing-box", """
        /bin/busybox sha256sum -c /usr/share/doc/sing-box/CRONET_RUNTIME_SHA256
    """)

    for name, port in (("xray", 18081), ("sing-box", 18082)):
        path = fixture / name
        path.mkdir(mode=0o755)
        if name == "xray":
            config = {"log": {"loglevel": "warning"}, "inbounds": [
                {"listen": "127.0.0.1", "port": port, "protocol": "socks",
                 "settings": {"auth": "noauth"}}],
                "routing": {"rules": [
                    {"type": "field", "domain": ["geosite:cn"], "outboundTag": "direct"},
                    {"type": "field", "ip": ["geoip:private"], "outboundTag": "direct"},
                ]}, "outbounds": [{"protocol": "freedom", "tag": "direct"}]}
        else:
            config = {"inbounds": [{"type": "socks", "listen": "127.0.0.1", "listen_port": port}],
                      "outbounds": [{"type": "direct"}]}
        (path / "config.json").write_text(json.dumps(config))
        start(name, mount(path, f"/etc/padm/{name}"))
        if name == "xray":
            print("distroless-real:xray:nonroot-geo-data-loaded", flush=True)
        proxy(port)
        print(f"distroless-real:{name}:proxy-health-user-ok", flush=True)

    server = fixture / "naive-server"
    client = fixture / "naive-client"
    server.mkdir(mode=0o755)
    client.mkdir(mode=0o755)
    command(["openssl", "req", "-x509", "-nodes", "-newkey", "rsa:2048", "-days", "1",
             "-subj", "/CN=runtime.padm.test", "-addext", "subjectAltName=DNS:runtime.padm.test",
             "-addext", "basicConstraints=critical,CA:TRUE",
             "-keyout", str(server / "key.pem"), "-out", str(server / "cert.pem")])
    os.chown(server / "key.pem", 0, 10001)
    (server / "key.pem").chmod(0o640)
    (client / "ca.crt").write_bytes((server / "cert.pem").read_bytes())
    (server / "config.json").write_text(json.dumps({
        "log": {"level": "warn"},
        "inbounds": [{"type": "naive", "listen": "127.0.0.1", "listen_port": 18443,
                      "network": "tcp", "users": [{"username": "padm", "password": "runtime-test"}],
                      "tls": {"enabled": True, "server_name": "runtime.padm.test",
                              "certificate_path": "/etc/padm/sing-box/cert.pem",
                              "key_path": "/etc/padm/sing-box/key.pem"}}],
        "outbounds": [{"type": "direct"}],
    }))
    (client / "config.json").write_text(json.dumps({
        "log": {"level": "warn"},
        "inbounds": [{"type": "socks", "listen": "127.0.0.1", "listen_port": 18084}],
        "outbounds": [{"type": "naive", "server": "127.0.0.1", "server_port": 18443,
                       "username": "padm", "password": "runtime-test",
                       "tls": {"enabled": True, "server_name": "runtime.padm.test",
                               "certificate_path": "/etc/padm/sing-box/ca.crt"}}],
    }))
    start("sing-box", mount(server, "/etc/padm/sing-box"))
    start("sing-box", mount(client, "/etc/padm/sing-box"))
    proxy(18084)
    print("distroless-real:sing-box:naive-cronet-tls-ok", flush=True)

    stream = fixture / "stream.conf"
    stream.write_text("stream { server { listen 18083; proxy_pass 127.0.0.1:18080; } }\n")
    stream_spec = fixture / "stream-spec.json"
    stream_spec.write_text(json.dumps({"reality_stream": {"host_website": {"network_mode": "host"}}}))
    stream_main = fixture / "host-main"
    command(["bash", "-ec",
             'source "$1/install-docker.sh"; dockerGenerateRealityStreamMain "$2" "$3"',
             "distroless-stream", str(ROOT), str(stream_spec), str(stream_main)])
    shell("nginx", "nginx -t -c /etc/nginx/stream.d/host-main", [
        *mount(stream_main, "/etc/nginx/stream.d/host-main"),
        *mount(stream, "/etc/nginx/stream.d/reality.conf"),
    ])
    print("distroless-real:nginx:generated-host-stream-config-ok", flush=True)
    start("nginx", mount(stream, "/etc/nginx/stream.d/probe.conf"))
    for port, expected in ((8080, b"ok\n"), (18083, b"distroless-runtime-ok\n")):
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
        try:
            connection.request("GET", "/healthz")
            response = connection.getresponse()
            assert response.status == 200 and response.read() == expected
        finally:
            connection.close()
    print("distroless-real:nginx:http-stream-health-ok", flush=True)

    start("ops")
    shell("ops", """
        date --version | grep -q 'GNU coreutils'
        test "$(date -u -d '2026-01-02 03:04:05' +%s)" = 1767323045
        python3 -c 'import ssl, sqlite3, urllib.request, http.server; assert ssl.create_default_context().get_ca_certs()'
        test -r /opt/acme/acme.sh
        touch /var/lib/padm/writable
        /usr/local/bin/padm-entrypoint acme --version
        openssl req -x509 -nodes -newkey rsa:2048 -days 1 -subj /CN=runtime.padm.test \
            -addext subjectAltName=DNS:runtime.padm.test -keyout /tmp/key.pem -out /tmp/cert.pem
        /usr/local/bin/padm-entrypoint tls-check /tmp/cert.pem /tmp/key.pem runtime.padm.test
    """)
    print("distroless-real:ops:python-acme-tls-permissions-ok", flush=True)
    subscription_http(fixture)
    control_http(fixture)

    start("net")
    shell("net", """
        python3 -c 'import ssl, sqlite3, fail2ban, systemd, pyinotify; assert ssl.create_default_context().get_ca_certs()'
        /usr/local/bin/padm-entrypoint health
        fail2ban-client --version
        iptables --version
        ip6tables --version
        nft --version
        wg --version
        ip link add dev wg-probe type wireguard
        wg show wg-probe
        ip link delete dev wg-probe
        nft add table inet padm_probe
        nft delete table inet padm_probe
        iptables -N PADM_PROBE
        iptables -X PADM_PROBE
    """, ["--cap-add", "NET_ADMIN"])
    print("distroless-real:net:python-firewall-wireguard-ok", flush=True)

    # 复用测试会挂载源码入口，先证明候选镜像内的入口与其逐字节一致。
    installed_entrypoint = shell("net", "sha256sum /usr/local/bin/padm-entrypoint").split()[0]
    assert installed_entrypoint == hashlib.sha256(
        (ROOT / "docker/images/net/entrypoint.sh").read_bytes()).hexdigest(), \
        "候选 net 入口与当前源码不一致，拒绝用源码覆盖后冒充候选验收"
    environment = dict(os.environ, PADM_TEST_NET_IMAGE=image("net"))
    command(["bash", str(ROOT / "docker/tests/fail2ban-real.sh")], timeout=240, env=environment)
    print("distroless-real:net:fail2ban-ownership-signal-ok", flush=True)
    for identity in RUNNING:
        docker("stop", "--time", "5", identity)
        value = inspect(identity)
        idle = value["Image"] in (image("ops"), image("net"))
        assert value["State"]["ExitCode"] in ({0, 143} if idle else {0}), docker("logs", identity)
    print("distroless-real:five-images-stop-ok", flush=True)


origin = ThreadingHTTPServer(("127.0.0.1", 18080), Origin)
threading.Thread(target=origin.serve_forever, daemon=True).start()
dns = socketserver.UDPServer(("127.0.0.1", 53), DNS)
threading.Thread(target=dns.serve_forever, daemon=True).start()
try:
    main()
except BaseException:
    for identity in RUNNING:
        print(docker("logs", identity), flush=True)
        state = inspect(identity)["State"]
        if "Health" in state:
            state["Health"]["Log"] = state["Health"].get("Log", [])[-1:]
        print(json.dumps(state), flush=True)
    raise
finally:
    for identity in RUNNING:
        subprocess.run(["docker", "rm", "-f", identity], capture_output=True, timeout=20)
    origin.shutdown()
    dns.shutdown()
    dns.server_close()
