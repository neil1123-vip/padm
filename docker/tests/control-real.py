#!/usr/bin/env python3
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
API = ROOT / "docker/images/ops/control_api.py"
ADDRESS = "10.231.0.1"
PORT = 39778


def runtime_user():
    os.setgroups([])
    os.setgid(10001)
    os.setuid(10001)


def health(path, expected):
    checked = subprocess.run(
        [sys.executable, str(API), "--state", str(path), "--health"],
        preexec_fn=runtime_user, capture_output=True, timeout=6,
    )
    assert checked.returncode == expected and not checked.stdout
    assert checked.stderr == (b"" if expected == 0 else "控制服务健康检查失败\n".encode())


assert os.getuid() == 0, "仅在隔离 NET_ADMIN 网络空间内运行"
assert subprocess.run(["ip", "link", "show", "wg-padm"], capture_output=True).returncode != 0, \
    "不能覆盖已有 WireGuard 接口"
server = None
subprocess.run(["ip", "link", "set", "lo", "up"], check=True)
subprocess.run(["ip", "link", "add", "wg-padm", "type", "wireguard"], check=True)
try:
    subprocess.run(["ip", "address", "add", f"{ADDRESS}/30", "dev", "wg-padm"], check=True)
    subprocess.run(["ip", "link", "set", "wg-padm", "up"], check=True)
    with tempfile.TemporaryDirectory(prefix=".tmp-control-real-", dir="/var/lib") as directory:
        path = Path(directory) / "state.json"
        state = {
            "schema_version": 1, "role": "main",
            "node_id": "11111111-1111-4111-8111-111111111111", "revision": 0,
            "listen": {"interface": "wg-padm", "address": ADDRESS, "port": PORT},
            "peer": {"id": "22222222-2222-4222-8222-222222222222", "address": "10.231.0.2",
                     "enabled": False, "expires_at": 1, "token_sha256": "a" * 64},
            "accounts": [],
        }
        path.write_text(json.dumps(state))
        path.chmod(0o640)
        os.chown(path, 0, 10001)
        os.chown(directory, 0, 10001)
        Path(directory).chmod(0o750)
        server = subprocess.Popen(
            [sys.executable, str(API), "--state", str(path)],
            preexec_fn=runtime_user, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        )
        last_error = None
        for _ in range(100):
            assert server.poll() is None, "控制服务启动失败"
            try:
                with socket.create_connection((ADDRESS, PORT), timeout=0.1):
                    break
            except OSError as error:
                last_error = error
                time.sleep(0.02)
        else:
            subprocess.run(["ip", "address", "show"], check=True)
            subprocess.run(["ip", "route", "show", "table", "local"], check=True)
            print(Path("/proc/net/tcp").read_text(), flush=True)
            raise AssertionError(f"控制服务未开始监听；最后连接错误：{last_error}")
        status = Path(f"/proc/{server.pid}/status").read_text()
        assert "Uid:\t10001\t10001\t10001\t10001" in status
        assert "CapEff:\t0000000000000000" in status, "控制服务不能持有网络管理能力"
        health(path, 0)
        subprocess.run(["ip", "address", "del", f"{ADDRESS}/30", "dev", "wg-padm"], check=True)
        health(path, 1)
        subprocess.run(["ip", "address", "add", f"{ADDRESS}/30", "dev", "wg-padm"], check=True)
        health(path, 0)
        server.terminate()
        server.communicate(timeout=3)
        server = None
        health(path, 1)
finally:
    if server is not None:
        server.terminate()
        server.communicate(timeout=3)
    subprocess.run(["ip", "link", "delete", "wg-padm"], check=True)
print("docker-control-real-regression-ok")
