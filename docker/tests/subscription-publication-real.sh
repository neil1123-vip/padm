#!/usr/bin/env bash
set -euo pipefail
umask 077

[[ "$#" == 0 ]] || exit 2
scriptRoot=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
python3 - "${scriptRoot}" <<'PY'
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import signal
import subprocess
import sys
import tempfile

scripts = Path(sys.argv[1])
helpers = runpy.run_path(str(scripts / "http-relay-published-real.py"))
command, stop, wait_ready = (helpers[name] for name in ("command", "stop", "wait_ready"))
assert os.getuid() == 0 and sys.platform == "linux" and Path("/.dockerenv").is_file()
assert {item["ifname"] for item in json.loads(command(["ip", "-j", "link", "show"]))} == {"lo"}
assert not Path("/var/run/docker.sock").exists(), "不得使用宿主 Docker Socket"
inputs = json.loads(Path("/node-images.json").read_text())
assert set(inputs) == {"xray", "sing-box", "ops", "nginx", "curl"}
template = os.environ.get("PADM_TEST_SUBSCRIPTION_SITE_TEMPLATE", "")
assert template in ("", "photos")
node = Path(tempfile.mkdtemp(prefix=".tmp-subscription-publication-", dir="/n"))
docker = ["docker", "--host", f"unix://{node}/docker.sock"]
daemon = child = None

def terminate(*_):
    raise SystemExit(143)

signal.signal(signal.SIGTERM, terminate)
with (node / "daemon.log").open("wb") as log, (node / "child.log").open("wb") as child_log:
    try:
        # 离线镜像只进入本次独立 daemon，源码取本轮工作区快照。
        daemon = subprocess.Popen([
            "dockerd", "--host", docker[-1], "--data-root", str(node / "docker"),
            "--exec-root", str(node / "run"), "--pidfile", str(node / "daemon.pid"),
            "--feature", "containerd-snapshotter=true", "--storage-driver", "overlayfs",
            "--bip", "172.30.0.1/24"], stdout=log, stderr=log)
        wait_ready(lambda: subprocess.run(docker + ["info"], capture_output=True).returncode == 0, 30)
        command(docker + ["load", "--input", "/node-images.tar"], timeout=120)
        for item in inputs.values():
            assert re.fullmatch(r"sha256:[0-9a-f]{64}", item["image_id"])
            image = json.loads(command(docker + ["image", "inspect", item["reference"]]))[0]
            assert image["Id"] == item["image_id"]
        environment = dict(os.environ, DOCKER_HOST=docker[-1], PADM_TEST_SUBSCRIPTION_PUBLICATION="1",
                           PADM_TEST_HTTP2_CURL_REF=inputs["curl"]["image_id"])
        combinations = ((23, "sing-box"),) if template else (
            (22, "xray"), (23, "sing-box"), (24, "xray"), (25, "xray"),
            (27, "xray"), (29, "xray"))
        for protocol, core in combinations:
            print(f"docker-subscription-publication-real-start: protocol={protocol} core={core}", flush=True)
            child = subprocess.Popen([
                "bash", str(scripts / "vmess-real.sh"),
                *(inputs[name]["image_id"] for name in ("xray", "sing-box", "ops", "nginx")),
                str(protocol), core], env=environment, stdout=child_log, stderr=child_log)
            assert child.wait(timeout=300) == 0, f"订阅发布实链路失败：protocol={protocol} core={core}"
        assert not command(docker + ["ps", "-aq"]).strip(), "测试容器未清理"
        assert not command(docker + ["volume", "ls", "-q"]).strip(), "测试卷未清理"
        print("docker-subscription-publication-real-images=" + json.dumps(inputs), flush=True)
    finally:
        active_error = sys.exc_info()[0] is not None
        try:
            if child is not None:
                stop(child)
            if daemon is not None:
                try:
                    result = subprocess.run(docker + ["ps", "-aq"], capture_output=True, timeout=5)
                    if not result.returncode and result.stdout.strip():
                        command(docker + ["rm", "-f"] + result.stdout.decode().split(), timeout=15)
                finally:
                    stop(daemon)
        finally:
            try:
                for name in (("child.log", "daemon.log") if active_error else ("child.log",)):
                    output = (node / name).read_text(errors="replace")
                    output = re.sub(r"/subscriptions/[A-Za-z0-9_-]{16,128}", "/subscriptions/[已隐藏]", output)
                    output = re.sub(r"(?:vmess|vless|trojan)://[^\s\"']+", "[已隐藏 URI]", output)
                    print(output[-4000:] if name == "daemon.log" else output,
                          file=sys.stderr if active_error else sys.stdout, flush=True)
            finally:
                assert node.parent == Path("/n") and node.name.startswith(".tmp-subscription-publication-")
                shutil.rmtree(node)
PY
