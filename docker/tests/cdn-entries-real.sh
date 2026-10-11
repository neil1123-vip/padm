#!/usr/bin/env bash
set -Eeuo pipefail
status=0
trap 'status=$?; printf "cdn-entries-real-fail: line=%s rc=%s command=%s\n" "${LINENO}" "${status}" "${BASH_COMMAND}" >&2; exit "${status}"' ERR

[[ "$#" == 0 || "$#" == 4 ]] || {
    printf 'usage: cdn-entries-real.sh [<local-xray> <local-sing-box> <local-ops> <local-nginx>]\n' >&2
    exit 2
}
scriptRoot=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
if [[ "$#" == 0 ]]; then
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
assert set(inputs) == {"xray", "sing-box", "ops", "nginx"}
node = Path(tempfile.mkdtemp(prefix=".tmp-cdn-entry-", dir="/n"))
docker = ["docker", "--host", f"unix://{node}/docker.sock"]
daemon = child = None

def terminate(*_):
    raise SystemExit(143)

signal.signal(signal.SIGTERM, terminate)
with (node / "daemon.log").open("wb") as log:
    try:
        # 离线镜像只加载到本次独立 daemon，源码仍由当前工作区快照提供。
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
            "bash", str(scripts / "cdn-entries-real.sh"),
            *(inputs[name]["image_id"] for name in ("xray", "sing-box", "ops", "nginx"))],
            env=dict(os.environ, DOCKER_HOST=docker[-1]))
        child_status = child.wait(timeout=600)
        assert child_status == 0, f"CDN 实链路子脚本退出码 {child_status}"
        assert not command(docker + ["ps", "-aq"]).strip(), "测试容器未清理"
        print("docker-cdn-entries-real-images=" + json.dumps(inputs), flush=True)
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
        assert node.parent == Path("/n") and node.name.startswith(".tmp-cdn-entry-")
        shutil.rmtree(node)
PY
    exit 0
fi
# 事务由合同回归验证；实链路复用现有客户端，不再重复额度验收。
export PADM_TEST_CDN_ENTRIES=1
for protocol in 21 22 23; do
    printf 'docker-cdn-entries-real-start: protocol=%s core=xray\n' "${protocol}"
    bash "${scriptRoot}/vmess-real.sh" "$1" "$2" "$3" "$4" "${protocol}" xray
done
printf 'docker-cdn-entries-real-start: protocol=23 core=sing-box\n'
bash "${scriptRoot}/vmess-real.sh" "$1" "$2" "$3" "$4" 23 sing-box
printf 'docker-cdn-entries-real-all-ok\n'
