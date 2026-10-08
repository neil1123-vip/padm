#!/usr/bin/env python3
"""用真实 Nginx 验证生产站点 location，核心上游只返回可识别夹具内容。"""

import http.client
import http.server
import os
import re
import signal
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path


DOMAIN = "ws.example.com"
TOKEN = "0123456789abcdef0123456789abcdef"
REDIRECT = "https://example.com/path?a=1&b=2#part"
INDEX = b"<h1>real-static-site</h1>\n"
CSS = b"body { color: green; }\n"
CHALLENGE = "Padm_token-123"
KEY_AUTHORIZATION = b"Padm_token-123.thumbprint_456\n"


class Backend(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        prefix = b"proxy:" if self.path == "/abcdefghws" else b"subscription:"
        body = prefix + self.path.encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


def port():
    with socket.socket() as connection:
        connection.bind(("127.0.0.1", 0))
        return connection.getsockname()[1]


def request(destination, path, tls=None, proxy=False, host=DOMAIN):
    connection = socket.create_connection(("127.0.0.1", destination), timeout=3)
    try:
        if tls is not None:
            connection = tls.wrap_socket(connection, server_hostname=DOMAIN)
        if proxy:
            connection.sendall(
                f"PROXY TCP4 203.0.113.9 127.0.0.1 41234 {destination}\r\n".encode()
            )
        connection.sendall(
            f"GET {path} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n".encode()
        )
        response = http.client.HTTPResponse(connection)
        with response:
            response.begin()
            return response.status, response.getheader("Location"), response.read()
    finally:
        connection.close()


def h2_request(destination, path, fixture):
    body, headers = fixture / "h2-body", fixture / "h2-headers"
    response = subprocess.run(
        ["curl", "--silent", "--show-error", "--noproxy", "*", "--connect-timeout", "1",
         "--max-time", "3", "--http2-prior-knowledge", "--haproxy-protocol",
         "--header", f"Host: {DOMAIN}", "--output", str(body), "--dump-header", str(headers),
         "--write-out", "%{http_version}\t%{http_code}", f"http://127.0.0.1:{destination}{path}"],
        check=True, capture_output=True, text=True, timeout=5,
    )
    version, status = response.stdout.split("\t")
    assert version == "2", (destination, path, response.stdout)
    location = next(
        (line.split(":", 1)[1].strip() for line in headers.read_text().splitlines()
         if line.lower().startswith("location:")), None,
    )
    return int(status), location, body.read_bytes()


def main(test_root):
    version = subprocess.run(["curl", "--version"], capture_output=True, text=True, check=True)
    assert re.search(r"^Features:.*\bHTTP2\b", version.stdout, re.MULTILINE), "curl 缺少 HTTP2"
    backend = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Backend)
    backend.daemon_threads = True
    thread = threading.Thread(target=backend.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory(prefix="nginx-real.", dir=test_root) as directory:
            fixture = Path(directory)
            site = fixture / "static"
            (site / "assets").mkdir(parents=True)
            (site / "index.html").write_bytes(INDEX)
            (site / "assets/site.css").write_bytes(CSS)
            (site / ".env").write_text("hidden-secret")
            (site / "assets/.secret").write_text("hidden-secret")
            webroot = fixture / "acme-webroot"
            challenge = webroot / "active/.well-known/acme-challenge"
            challenge.mkdir(parents=True)
            (challenge / CHALLENGE).write_bytes(KEY_AUTHORIZATION)
            (challenge / ".hidden").write_text("hidden-secret")
            (webroot / "active/private.key").write_text("private-secret")
            (challenge / "Link_token").symlink_to(webroot / "active/private.key")
            cert, key = fixture / "test.crt", fixture / "test.key"
            subprocess.run(
                ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                 "-subj", f"/CN={DOMAIN}", "-addext", f"subjectAltName=DNS:{DOMAIN}",
                 "-keyout", str(key), "-out", str(cert)],
                check=True, capture_output=True, timeout=15,
            )
            tls = ssl.create_default_context(cafile=str(cert))
            # 保留私有夹具权限，只开放生产 UID 的父目录穿越和实际读取。
            os.chown(test_root, 0, 10001)
            test_root.chmod(0o710)
            for path in (fixture, *fixture.rglob("*")):
                if path.is_symlink():
                    continue
                os.chown(path, 10001, 10001)
                path.chmod(0o750 if path.is_dir() else 0o640)
            key.chmod(0o600)
            assert (challenge.stat().st_mode & 0o777, challenge.stat().st_uid,
                    challenge.stat().st_gid) == (0o750, 10001, 10001)
            token = challenge / CHALLENGE
            assert (token.stat().st_mode & 0o777, token.stat().st_uid,
                    token.stat().st_gid) == (0o640, 10001, 10001)
            for output in sorted(test_root.glob("nginx-*-*.conf")):
                parts = output.stem.split("-")
                http01 = len(parts) == 4 and parts[1] == "http01"
                _, protocol, mode = parts[-3:]
                ports = {}
                for old in ("8080", "8088", "8443", "31300", "31302"):
                    destination = port()
                    while destination in ports.values():
                        destination = port()
                    ports[old] = destination
                text = output.read_text()
                # 仅隔离测试路径、监听和上游；生产 location、PROXY/h2 指令原样校验。
                text = re.sub(
                    r"(?m)^(\s*listen )(\[::\]:)?(8080|8088|8443|31300|31302)([^;]*);",
                    lambda match: (
                        f"{match[1]}{'[::1]' if match[2] else '127.0.0.1'}:"
                        f"{ports[match[3]]}{match[4]};"
                    ),
                    text,
                )
                text = text.replace("/srv/padm-acme", str(webroot)).replace("/srv/padm", str(site))
                text = text.replace(f"/etc/padm/secrets/tls/{DOMAIN}.crt", str(cert))
                text = text.replace(f"/etc/padm/secrets/tls/{DOMAIN}.key", str(key))
                text = text.replace("/var/log/nginx/access.log", str(fixture / "access.log"))
                upstream = f"127.0.0.1:{backend.server_port}"
                text = text.replace("xray:31297", upstream).replace("subscription:8081", upstream)
                generated = fixture / "generated.conf"
                generated.write_text(text)
                config = fixture / "nginx.conf"
                config.write_text(
                    "worker_processes 1;\n"
                    f"pid {fixture}/nginx.pid;\nerror_log {fixture}/error.log notice;\n"
                    "events { worker_connections 64; }\n"
                    "http {\ninclude /etc/nginx/mime.types;\n"
                    f"access_log {fixture}/access.log;\n"
                    f"client_body_temp_path {fixture}/client-body;\n"
                    f"proxy_temp_path {fixture}/proxy;\n"
                    f"fastcgi_temp_path {fixture}/fastcgi;\n"
                    f"uwsgi_temp_path {fixture}/uwsgi;\n"
                    f"scgi_temp_path {fixture}/scgi;\n"
                    f"include {generated};\n}}\n"
                )
                for path in (generated, config):
                    os.chown(path, 0, 10001)
                    path.chmod(0o640)
                command = ["nginx", "-p", str(fixture), "-c", str(config)]
                parsed = subprocess.run(command + ["-t"], capture_output=True, text=True, timeout=5,
                                        user=10001, group=10001, extra_groups=[])
                assert parsed.returncode == 0, (output.name, parsed.stderr)
                if not http01 or protocol not in ("21", "27", "29"):
                    continue
                process = subprocess.Popen(
                    command + ["-g", "daemon off; master_process off;"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    user=10001, group=10001, extra_groups=[],
                )
                try:
                    deadline = time.monotonic() + 3
                    while True:
                        assert process.poll() is None, (output.name, (fixture / "error.log").read_text())
                        try:
                            response = request(ports["8080"], "/healthz")
                        except (OSError, http.client.HTTPException):
                            assert time.monotonic() < deadline, f"{output.name}: Nginx 未就绪"
                            time.sleep(0.01)
                            continue
                        assert response == (200, None, b"ok\n"), (output.name, response)
                        break
                    if http01:
                        assert request(ports["8088"], f"/.well-known/acme-challenge/{CHALLENGE}") == (
                            200, None, KEY_AUTHORIZATION,
                        ), output.name
                        for path in (
                            "/", "/index.html", "/assets/site.css", "/healthz", "/private.key",
                            "/abcdefghws", f"/subscriptions/{TOKEN}",
                            "/.well-known/acme-challenge", "/.well-known/acme-challenge/",
                            "/.well-known/acme-challenge/.hidden",
                            "/.well-known/acme-challenge/%2ehidden",
                            "/.well-known/acme-challenge/../private.key",
                            "/.well-known/acme-challenge/%2e%2e/private.key",
                            f"/.well-known/acme-challenge/{CHALLENGE}/",
                            f"/.well-known/acme-challenge/{CHALLENGE}?unexpected=1",
                            "/.well-known/acme-challenge/%50adm_token-123",
                            "/.well-known/acme-challenge/Link_token",
                            "/.well-known/acme-challenge/" + "a" * 129,
                            "/.well-known/acme-challenge/a.b",
                        ):
                            status, location, body = request(ports["8088"], path)
                            assert status == 404 and location is None, (output.name, path, status, location)
                            assert b"hidden-secret" not in body and b"private-secret" not in body, (
                                output.name, path,
                            )
                        assert request(ports["8088"], f"/.well-known/acme-challenge/{CHALLENGE}",
                                       host="other.example.com")[0] == 404, output.name
                    destination = ports["8443"] if protocol == "21" else ports["31300"]
                    kwargs = {"tls": tls} if protocol == "21" else {"proxy": True}
                    response = request(destination, "/", **kwargs)
                    if mode == "static":
                        assert response == (200, None, INDEX), (output.name, response)
                        assert request(destination, "/assets/site.css", **kwargs) == (200, None, CSS)
                        for path in ("/missing", "/.env", "/%2eenv", "/assets/.secret"):
                            status, _, body = request(destination, path, **kwargs)
                            assert status == 404 and b"hidden-secret" not in body, (output.name, path)
                    elif mode == "default":
                        assert response[0] == 200 and b"<h1>Welcome</h1>" in response[2], output.name
                        assert INDEX not in response[2], output.name
                    else:
                        assert response[:2] == (302, REDIRECT), (output.name, response)
                    if protocol in ("27", "29"):
                        # HTTP/2 与 PROXY v1 使用已安装 curl，不手写协议解析或隐藏回落。
                        assert h2_request(ports["31302"], "/", fixture) == response, output.name
                        if mode == "static":
                            assert h2_request(ports["31302"], "/assets/site.css", fixture) == (200, None, CSS)
                    if protocol == "21":
                        for path, body in (
                            ("/abcdefghws", b"proxy:/abcdefghws"),
                            (f"/subscriptions/{TOKEN}", b"subscription:/" + TOKEN.encode()),
                        ):
                            assert request(destination, path, **kwargs) == (200, None, body), (
                                output.name, path,
                            )
                finally:
                    if process.poll() is None:
                        process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=3)
    finally:
        backend.shutdown()
        backend.server_close()
        thread.join(timeout=3)
    print("docker-sites-nginx-real-ok")


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    main(Path(sys.argv[1]))
