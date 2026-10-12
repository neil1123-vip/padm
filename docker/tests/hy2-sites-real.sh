#!/usr/bin/env bash
set -Eeuo pipefail
trap 'status=$?; printf "hy2-sites-real-fail: line=%s rc=%s command=%s\n" "${LINENO}" "${status}" "${BASH_COMMAND}" >&2; exit "${status}"' ERR

[[ "$#" == 0 ]] || exit 2
scriptRoot=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
python3 - "${scriptRoot}" <<'PY'
import json
import os
from pathlib import Path
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
assert set(inputs) == {"xray", "sing-box", "ops", "curl"}
node = Path(tempfile.mkdtemp(prefix=".tmp-hy2-sites-", dir="/n"))
docker = ["docker", "--host", f"unix://{node}/docker.sock"]
daemon = child = None

def terminate(*_):
    raise SystemExit(143)

signal.signal(signal.SIGTERM, terminate)
with (node / "daemon.log").open("wb") as log:
    try:
        # 固定离线镜像只进入本次独立 daemon，源码仍取本轮工作区快照。
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
        child = subprocess.Popen([
            "bash", str(scripts / "hysteria2-real.sh"),
            *(inputs[name]["image_id"] for name in ("xray", "sing-box", "ops"))],
            env=dict(os.environ, DOCKER_HOST=docker[-1], PADM_TEST_HY2_SITES="1",
                     PADM_TEST_HY2_CURL_REF=inputs["curl"]["image_id"]))
        assert child.wait(timeout=600) == 0, "Hy2 本地网页实链路子脚本失败"
        assert not command(docker + ["ps", "-aq"]).strip(), "测试容器未清理"
        assert not command(docker + ["volume", "ls", "-q"]).strip(), "测试卷未清理"
        print("docker-hy2-sites-real-images=" + json.dumps(inputs), flush=True)
    finally:
        active_error = sys.exc_info()[0] is not None
        if child is not None:
            stop(child)
        if daemon is not None:
            try:
                result = subprocess.run(docker + ["ps", "-aq"], capture_output=True, timeout=5)
                if not result.returncode and result.stdout.strip():
                    command(docker + ["rm", "-f"] + result.stdout.decode().split(), timeout=15)
            finally:
                stop(daemon)
        if active_error:
            print((node / "daemon.log").read_text()[-4000:], file=sys.stderr)
        assert node.parent == Path("/n") and node.name.startswith(".tmp-hy2-sites-")
        shutil.rmtree(node)
PY
