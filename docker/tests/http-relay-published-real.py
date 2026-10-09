#!/usr/bin/env python3
import base64
import json
import os
from pathlib import Path
import runpy
import shutil
import signal
import socket
import socketserver
import subprocess
import sys
import tempfile
import threading
import time


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(__file__).resolve()
helpers = runpy.run_path(str(SCRIPT.with_name("control-two-deployment-real.py")))
command, stop = (helpers[name] for name in ("command", "stop"))
PORT, ORIGIN_PORT = 38180, 18080
HOST, ALLOWED, DENIED = "198.18.1.1", "198.18.1.2", "198.18.1.3"
USER, PASSWORD = "relay-user", "relay:password"
BODY = b"http-published-origin-ok"


def exact(stream, size):
    result = b""
    while len(result) < size:
        part = stream.recv(size - len(result))
        if not part:
            raise EOFError
        result += part
    return result


def headers(stream):
    result = b""
    while not result.endswith(b"\r\n\r\n"):
        result += exact(stream, 1)
        assert len(result) <= 16384, "HTTP 头超限"
    return result


class Origin(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(2)
        with self.server.lock, (self.server.root / "events.jsonl").open("a") as output:
            output.write(json.dumps(dict(source=self.client_address[0])) + "\n")
        request = headers(self.request)
        assert request.startswith(b"GET /published-check "), request
        self.request.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: " +
                             str(len(BODY)).encode() + b"\r\nConnection: close\r\n\r\n" + BODY)


def fixture(root):
    stopping = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stopping.set())
    with socketserver.ThreadingTCPServer(("0.0.0.0", ORIGIN_PORT), Origin) as server:
        server.daemon_threads = True
        server.root, server.lock = root, threading.Lock()
        thread = threading.Thread(target=server.serve_forever,
                                  kwargs=dict(poll_interval=0.02), daemon=True)
        thread.start()
        (root / "ready").touch()
        stopping.wait()
        server.shutdown()
        thread.join(1)


def request(origin, method, auth):
    credentials = b""
    if auth != "none":
        password = PASSWORD if auth == "valid" else "wrong-password"
        credentials = b"Proxy-Authorization: Basic " + base64.b64encode(
            f"{USER}:{password}".encode()) + b"\r\n"
    destination = f"{origin}:{ORIGIN_PORT}".encode()
    target = destination if method == "CONNECT" else b"http://" + destination + b"/published-check"
    with socket.create_connection((HOST, PORT), timeout=1.5) as stream:
        # 代理头故意伪造为允许来源，来源判定必须使用真实 Linux TCP 来源。
        stream.sendall(method.encode() + b" " + target + b" HTTP/1.1\r\nHost: " + destination +
                       b"\r\n" + credentials + b"X-Forwarded-For: " + ALLOWED.encode() +
                       b"\r\nForwarded: for=" + ALLOWED.encode() +
                       b"\r\nConnection: close\r\n\r\n")
        try:
            response = headers(stream)
            status = int(response.split(b" ", 2)[1])
            if status != 200:
                return status
            if method == "CONNECT":
                stream.sendall(b"GET /published-check HTTP/1.1\r\nHost: fixture\r\n"
                               b"Connection: close\r\n\r\n")
                response = headers(stream)
                assert response.startswith(b"HTTP/1.1 200 "), response
            values = dict(line.lower().split(b":", 1) for line in
                          response.split(b"\r\n")[1:] if b":" in line)
            assert int(values[b"content-length"]) == len(BODY)
            assert exact(stream, len(BODY)) == BODY
            return status
        except (EOFError, ConnectionResetError):
            return 0
        except socket.timeout as error:
            raise AssertionError("超时不能充当 HTTP 拒绝证据") from error


def wait_ready(probe, limit=10):
    deadline = time.monotonic() + limit
    while True:
        try:
            if probe():
                return
        except (OSError, AssertionError):
            pass
        assert time.monotonic() < deadline, "HTTP 发布夹具就绪超时"
        time.sleep(0.05)


def inspect(client, identity):
    return json.loads(command(client + ["inspect", identity]))[0]


def rows(root):
    return [json.loads(line) for line in (root / "events.jsonl").read_text().splitlines()]


def permissions(value, ports):
    host = value["HostConfig"]
    assert host["ReadonlyRootfs"] and not host["Privileged"]
    assert host["CapDrop"] == ["ALL"] and not host["CapAdd"] and not host["Devices"]
    assert value["Config"]["User"] == "10001:10001"
    assert "no-new-privileges:true" in host["SecurityOpt"]
    if ports:
        assert host["PortBindings"][f"{PORT}/tcp"] == [
            dict(HostIp="0.0.0.0", HostPort=str(PORT))]
    else:
        assert not host["PortBindings"]


def namespaces():
    processes = []
    try:
        for number, address, gateway in ((2, ALLOWED, HOST), (3, DENIED, "198.18.1.4")):
            process = subprocess.Popen(["unshare", "--net", "--", "sleep", "120"])
            processes.append(process)
            wait_ready(lambda: Path(f"/proc/{process.pid}/ns/net").readlink() !=
                       Path("/proc/self/ns/net").readlink())
            enter = ["nsenter", "--target", str(process.pid), "--net", "--"]
            host, peer = f"prh{number}", f"prc{number}"
            command(["ip", "link", "add", host, "type", "veth", "peer", "name", peer])
            command(["ip", "link", "set", peer, "netns", str(process.pid)])
            command(["ip", "address", "add", f"{gateway}/32", "dev", host])
            command(["ip", "link", "set", host, "up"])
            command(["ip", "route", "add", f"{address}/32", "dev", host])
            command(enter + ["ip", "link", "set", "lo", "up"])
            command(enter + ["ip", "address", "add", f"{address}/32", "dev", peer])
            command(enter + ["ip", "link", "set", peer, "up"])
            command(enter + ["ip", "route", "add", f"{gateway}/32", "dev", peer])
            command(enter + ["ip", "route", "add", "default", "via", gateway, "dev", peer])
            for scope in ("all", "default", peer):
                command(enter + ["sysctl", "-q", "-w", f"net.ipv4.conf.{scope}.rp_filter=0"])
        for scope in ("all", "default", "prh2", "prh3"):
            command(["sysctl", "-q", "-w", f"net.ipv4.conf.{scope}.rp_filter=0"])
        command(["sysctl", "-q", "-w", "net.ipv4.ip_forward=1"])
        return processes
    except BaseException:
        for process in processes:
            stop(process)
        raise


def run(root):
    assert os.getuid() == 0 and sys.platform == "linux" and Path("/.dockerenv").is_file()
    assert {item["ifname"] for item in json.loads(command(["ip", "-j", "link", "show"]))} == {
        "lo"}, "不得借用宿主接口或已有网络"
    inputs = json.loads(Path("/node-images.json").read_text())
    node = Path(tempfile.mkdtemp(prefix=".tmp-http-published-", dir="/n"))
    node.chmod(0o755)
    proof = node / "proof"
    proof.mkdir(mode=0o755)
    os.chown(proof, 10001, 10001)
    (proof / "events.jsonl").touch(mode=0o644)
    os.chown(proof / "events.jsonl", 10001, 10001)
    daemon, clients = None, []
    docker = ["docker", "--host", f"unix://{node}/docker.sock"]
    started = time.monotonic()
    with (node / "daemon.log").open("wb") as log:
        try:
            daemon = subprocess.Popen([
                "dockerd", "--host", docker[-1], "--data-root", str(node / "docker"),
                "--exec-root", str(node / "run"), "--pidfile", str(node / "daemon.pid"),
                "--feature", "containerd-snapshotter=true", "--storage-driver", "overlayfs",
                "--bip", "172.30.0.1/24"], stdout=log, stderr=log)
            wait_ready(lambda: subprocess.run(docker + ["info"], capture_output=True).returncode == 0, 30)
            command(docker + ["load", "--input", "/node-images.tar"], timeout=120)
            for item in inputs.values():
                image = json.loads(command(docker + ["image", "inspect", item["reference"]]))[0]
                assert image["Id"] == item["image_id"]
            clients = namespaces()
            fixture_compose = json.loads((root / "xray.compose.json").read_text())
            fixture_compose["services"] = dict(origin=dict(
                image=inputs["ops"]["image_id"], user="10001:10001", read_only=True,
                cap_drop=["ALL"], security_opt=["no-new-privileges:true"],
                entrypoint=["python3", "/work/docker/tests/http-relay-published-real.py", "fixture", "/proof"],
                volumes=[dict(type="bind", source=str(SCRIPT.parent), target="/work/docker/tests",
                              read_only=True),
                         dict(type="bind", source=str(proof), target="/proof")]))
            fixture_path = node / "origin.compose.json"
            fixture_path.write_text(json.dumps(fixture_compose))
            compose = docker + ["compose", "--project-name", "padm-docker", "--file", str(fixture_path)]
            command(compose + ["up", "-d", "--pull", "never"], timeout=30)
            identity = command(compose + ["ps", "-q", "origin"]).decode().strip()
            origin = inspect(docker, identity)
            permissions(origin, False)
            origin_ip = origin["NetworkSettings"]["Networks"]["padm-docker"]["IPAddress"]
            wait_ready(lambda: (proof / "ready").is_file())
            for core in ("xray",):
                config = json.loads((root / f"{core}.json").read_text())
                inbound = next(item for item in config["inbounds"] if item["tag"] == "padm-relay-http")
                if core == "xray":
                    assert inbound["port"] == PORT and inbound["settings"]["accounts"] == [
                        dict(user=USER, **{"pass": PASSWORD})]
                    config["log"].update(loglevel="debug", access="/dev/stdout", error="/dev/stderr")
                else:
                    assert inbound["listen_port"] == PORT and inbound["users"] == [
                        dict(username=USER, password=PASSWORD)]
                    config["log"] = dict(level="debug", timestamp=False)
                config_path = node / f"{core}.json"
                config_path.write_text(json.dumps(config))
                config_path.chmod(0o644)
                current = json.loads((root / f"{core}.compose.json").read_text())
                service = current["services"][core]
                ports = list(service["ports"])
                assert f"0.0.0.0:{PORT}:{PORT}/tcp" in ports
                # 保留生产 ports 和安全限制；仅换离线镜像、当前配置与测试日志入口。
                service.update(image=inputs[core]["image_id"],
                               volumes=[dict(type="bind", source=str(config_path),
                                             target="/config.json", read_only=True)],
                               entrypoint=[f"/usr/local/bin/{core}"],
                               command=["run", "-c", "/config.json"],
                               healthcheck=dict(disable=True), restart="no")
                assert service["ports"] == ports
                current["services"] = {core: service}
                compose_path = node / f"{core}.compose.json"
                compose_path.write_text(json.dumps(current))
                core_compose = docker + ["compose", "--project-name", "padm-docker",
                                         "--file", str(compose_path), "--profile", f"core-{core}"]
                command(core_compose + ["up", "-d", "--pull", "never"], timeout=30)
                identity = command(core_compose + ["ps", "-q", core]).decode().strip()
                value = inspect(docker, identity)
                permissions(value, True)
                status = Path(f"/proc/{value['State']['Pid']}/status").read_text()
                fields = dict(line.split(":", 1) for line in status.splitlines() if ":" in line)
                assert fields["Uid"].split() == ["10001"] * 4
                assert int(fields["CapEff"], 16) == 0 and int(fields["CapBnd"], 16) == 0
                core_ip = value["NetworkSettings"]["Networks"]["padm-docker"]["IPAddress"]
                wait_ready(lambda: published_listener(clients[0]))
                for method in ("GET", "CONNECT"):
                    for client, auth, accepted in ((clients[0], "valid", True),
                                                  (clients[1], "valid", False),
                                                  (clients[0], "wrong", False),
                                                  (clients[0], "none", False)):
                        before = len(rows(proof))
                        output = command(["nsenter", "--target", str(client.pid), "--net", "--",
                                          "python3", str(SCRIPT), "client", origin_ip, method, auth],
                                         timeout=5)
                        result = json.loads(output)
                        assert result["accepted"] == accepted, (core, method, auth, result)
                        delta = rows(proof)[before:]
                        assert len(delta) == int(accepted), (core, method, auth, delta)
                        if delta:
                            assert delta[0]["source"] == core_ip, delta
                # Xray 错误日志走 stderr，必须一并读取来源证据。
                result = subprocess.run(docker + ["logs", identity], capture_output=True, check=True)
                logs = (result.stdout + result.stderr).decode(errors="replace")
                assert ALLOWED in logs and DENIED in logs, f"{core}: 未记录真实 veth 客户端来源"
                (root / f"{core}.published.log").write_text(logs)
                for address in (ALLOWED, DENIED):
                    line = next(line for line in logs.splitlines() if address in line)
                    print(f"http-relay-published-source-{core}:" +
                          line.replace(PASSWORD, "[hidden]").replace("wrong-password", "[hidden]"),
                          flush=True)
                assert inspect(docker, identity)["State"]["Running"]
                command(core_compose + ["rm", "-s", "-f"], timeout=10)
                print(f"http-relay-published-{core}: production ports/HTTP/CONNECT/auth/"
                      f"source-CIDR/forged-proxy-header/UID10001/cap0 passed", flush=True)
            command(compose + ["rm", "-s", "-f"], timeout=10)
            print("http-relay-published-environment=" + json.dumps(dict(
                host=HOST, clients=[ALLOWED, DENIED], origin=origin_ip, image_ids=inputs,
                elapsed=round(time.monotonic() - started, 3)), sort_keys=True), flush=True)
        except BaseException:
            result = subprocess.run(docker + ["ps", "-aq"], capture_output=True, timeout=10)
            for identity in result.stdout.decode().split() if not result.returncode else []:
                diagnostic = subprocess.run(docker + ["logs", identity], capture_output=True, timeout=10)
                print((diagnostic.stdout + diagnostic.stderr).decode(errors="replace"), file=sys.stderr)
            raise
        finally:
            active_error = sys.exc_info()[0] is not None
            cleanup_error = None
            for client in clients:
                stop(client)
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
            assert node.parent == Path("/n") and node.name.startswith(".tmp-http-published-")
            try:
                shutil.rmtree(node)
            except OSError as error:
                print(f"http-relay-published-cleanup: {error}", file=sys.stderr)
                if not active_error:
                    raise
            if cleanup_error:
                print(f"http-relay-published-cleanup: {cleanup_error}", file=sys.stderr)
                if not active_error:
                    raise cleanup_error


def published_listener(client):
    result = subprocess.run(["nsenter", "--target", str(client.pid), "--net", "--", "python3", "-c",
                             f"import socket; socket.create_connection(('{HOST}', {PORT}), .15).close()"],
                            capture_output=True, timeout=2)
    return result.returncode == 0


if __name__ == "__main__":
    if sys.argv[1] == "fixture":
        fixture(Path(sys.argv[2]))
    elif sys.argv[1] == "client":
        print(json.dumps(dict(accepted=request(*sys.argv[2:5]) == 200)))
    else:
        run(Path(sys.argv[1]))
