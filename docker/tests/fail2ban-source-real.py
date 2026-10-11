#!/usr/bin/env python3
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import runpy
import selectors
import shutil
import socket
import sqlite3
import ssl
import subprocess
import sys
import tempfile
import time


SCRIPT = Path(__file__).resolve()
ROOT = SCRIPT.parents[2]
helpers = runpy.run_path(str(SCRIPT.with_name("control-two-deployment-real.py")))
command, stop = (helpers[name] for name in ("command", "stop"))
PORT = 24444
HOST = {"ipv4": "198.18.2.1", "ipv6": "fd42:7061:646d:2::1"}
SOURCES = {
    "ipv4": ("198.18.2.2", "198.18.2.3"),
    "ipv6": ("fd42:7061:646d:2::2", "fd42:7061:646d:2::3"),
}

# 离线镜像只适配身份与固定配置审计，启用、见证和内核清理仍执行生产函数。
FIXTURE_RUNTIME = r'''
source "$1"
dockerFail2banConfigurationCheck() {
    dockerConfigureSpecValidate "$PADM_DOCKER_INSTALL_DIR/config/spec.json" &&
        printf '%s\n' "$PADM_TEST_CONFIG_HASHES" | sha256sum --check --status --strict
}
dockerComposeExecute() {
    jq -cn --args '$ARGS.positional' -- "$@" >>"$PADM_TEST_COMPOSE_CALLS" || return 1
    docker compose --project-name padm-docker --project-directory "$PADM_DOCKER_INSTALL_DIR" \
      --file "$PADM_DOCKER_INSTALL_DIR/compose.json" --profile '*' "$@" </dev/null
}
dockerFail2banSourceContainer() {
    local entry identity
    entry=$(jq -ce --arg listener "$1" --arg family "$2" '
      [.core.protocols[] | select(.listener_id == $listener and
        (.address_families | index($family)) != null)] |
      select(length == 1) | .[0] |
      {public_port,internal_port:.websocket.tls_port}
    ' "$PADM_DOCKER_INSTALL_DIR/config/spec.json") || return 1
    identity=$(docker ps -aq --filter label=com.docker.compose.project=padm-docker \
      --filter label=com.docker.compose.service=nginx \
      --filter label=com.docker.compose.oneoff=False) || return 1
    [[ "$identity" =~ ^[a-f0-9]{12,64}$ ]] || return 1
    docker inspect "$identity" | jq -ce \
      --argjson entry "$entry" --arg image "$PADM_TEST_NGINX_IMAGE" \
      --argjson hosts "$PADM_TEST_SOURCE_HOSTS" '
      select(length == 1) | .[0] |
      select(.Image == $image and .State.Running == true and .State.Restarting == false and
        .Config.User == "10001:10001" and .HostConfig.ReadonlyRootfs == true and
        .HostConfig.Privileged == false and .HostConfig.CapDrop == ["ALL"] and
        (.HostConfig.CapAdd // []) == []) |
      {id:.Id,started_at:.State.StartedAt,restart_count:.RestartCount,
       public_port:$entry.public_port,internal_port:$entry.internal_port,domain:"source.padm.test",
       networks:(.NetworkSettings.Networks | to_entries |
         map({name:.key,id:.value.NetworkID}) | sort_by(.name)),
       addresses:($hosts + [.NetworkSettings.Networks[] |
         .IPAddress,.Gateway,.GlobalIPv6Address,.IPv6Gateway] | map(select(. != "")) | unique)}
    '
}
dockerFail2banContainer() {
    local identity
    dockerFail2banConfigurationCheck || return 1
    identity=$(docker ps -aq --filter label=com.docker.compose.project=padm-docker \
      --filter label=com.docker.compose.service=net-fail2ban \
      --filter label=com.docker.compose.oneoff=False) || return 1
    [[ "$identity" =~ ^[a-f0-9]{12,64}$ ]] || return 1
    docker inspect "$identity" | jq -e --arg image "$PADM_TEST_NET_IMAGE" '
      length == 1 and (.[0] | .Image == $image and .State.Running == true and
        .State.Restarting == false and .HostConfig.NetworkMode == "host" and
        .HostConfig.ReadonlyRootfs == true and .HostConfig.Privileged == false and
        .Config.User == "0:10001" and
        (.HostConfig.CapAdd | map(ltrimstr("CAP_"))) == ["NET_ADMIN"] and
        .HostConfig.CapDrop == ["ALL"])
    ' >/dev/null &&
        dockerFail2banRuntimeAudit "$identity" &&
        docker exec "$identity" sh /usr/local/bin/padm-entrypoint fail2ban-health || return 1
    printf '%s\n' "$identity"
}
'''


def wait_ready(probe, message, limit=15):
    deadline = time.monotonic() + limit
    while True:
        try:
            if probe():
                return
        except (OSError, AssertionError):
            pass
        assert time.monotonic() < deadline, message
        time.sleep(0.05)


def request(family, path, forged, port=PORT):
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    try:
        with socket.create_connection((HOST[family], int(port)), timeout=1) as stream:
            with context.wrap_socket(stream, server_hostname="source.padm.test") as tls:
                tls.sendall(
                    f"GET {path} HTTP/1.1\r\nHost: source.padm.test\r\n"
                    f"X-Forwarded-For: {forged}\r\nForwarded: for=\"{forged}\"\r\n"
                    "Connection: close\r\n\r\n".encode()
                )
                response = b""
                while b"\r\n" not in response:
                    part = tls.recv(1024)
                    assert part, "服务端在 HTTP 状态前关闭连接"
                    response += part
                    assert len(response) < 16384, "HTTP 响应头超限"
                return {"status": int(response.split(b" ", 2)[1])}
    except socket.timeout:
        return {"timeout": True}


def namespaces():
    processes = []
    try:
        for number in range(2):
            process = subprocess.Popen(["unshare", "--net", "--", "sleep", "infinity"])
            processes.append(process)
            wait_ready(lambda: Path(f"/proc/{process.pid}/ns/net").readlink() !=
                       Path("/proc/self/ns/net").readlink(), "客户端 netns 未隔离")
            enter = ["nsenter", "--target", str(process.pid), "--net", "--"]
            host, peer = f"fsh{number}", f"fsc{number}"
            command(["ip", "link", "add", host, "type", "veth", "peer", "name", peer])
            command(["ip", "link", "set", peer, "netns", str(process.pid)])
            command(["ip", "link", "set", host, "up"])
            command(enter + ["ip", "link", "set", "lo", "up"])
            command(enter + ["ip", "link", "set", peer, "up"])
            for family, prefix in (("ipv4", 32), ("ipv6", 128)):
                flags = [] if family == "ipv4" else ["-6"]
                gateway = HOST[family] if number == 0 else (
                    "198.18.2.4" if family == "ipv4" else "fd42:7061:646d:2::4")
                nodad = [] if family == "ipv4" else ["nodad"]
                command(["ip"] + flags + ["address", "add", f"{gateway}/{prefix}",
                                         "dev", host] + nodad)
                command(["ip"] + flags + ["route", "add", f"{SOURCES[family][number]}/{prefix}",
                                         "dev", host])
                command(enter + ["ip"] + flags + ["address", "add",
                        f"{SOURCES[family][number]}/{prefix}", "dev", peer] + nodad)
                command(enter + ["ip"] + flags + ["route", "add", f"{gateway}/{prefix}", "dev", peer])
                command(enter + ["ip"] + flags + ["route", "add", "default", "via", gateway,
                                                 "dev", peer])
            for scope in ("all", "default", peer):
                command(enter + ["sysctl", "-q", "-w", f"net.ipv4.conf.{scope}.rp_filter=0"])
        for scope in ("all", "default", "fsh0", "fsh1"):
            command(["sysctl", "-q", "-w", f"net.ipv4.conf.{scope}.rp_filter=0"])
        command(["sysctl", "-q", "-w", "net.ipv4.ip_forward=1"])
        command(["sysctl", "-q", "-w", "net.ipv6.conf.all.forwarding=1"])
        return processes
    except BaseException:
        for process in processes:
            stop(process)
        raise


def client(process, family, path="/", forged=None, port=PORT):
    return json.loads(command(
        ["nsenter", "--target", str(process.pid), "--net", "--", "python3", str(SCRIPT),
         "client", family, path, forged or SOURCES[family][1], str(port)], timeout=5))


def inspect(docker, identity):
    return json.loads(command(docker + ["inspect", identity]))[0]


def jail_absent(docker):
    identities = command(docker + [
        "ps", "-aq", "--filter", "label=com.docker.compose.project=padm-docker",
        "--filter", "label=com.docker.compose.service=net-fail2ban",
        "--filter", "label=com.docker.compose.oneoff=False"])
    assert not identities.strip(), "来源见证完成前 jail 已创建"


def verified_start(docker, compose, deployment, inputs, client_processes, mode, output_root):
    spec = json.loads((deployment / "config/spec.json").read_text())
    ports = set(spec["host_integrations"][0]["settings"]["ports"])
    expected = sorted(
        (entry["public_port"], family, entry["listener_id"], entry["websocket"]["tls_port"])
        for entry in spec["core"]["protocols"] if entry["public_port"] in ports
        for family in entry["address_families"])
    paths = [
        deployment / name for name in ("config/spec.json", "compose.json", "deployment.json",
                                      "images.env", "config/nginx/default.conf",
                                      "config/xray/config.json")
    ] + sorted((deployment / "config/net/fail2ban").iterdir())
    calls = deployment / "compose.calls.jsonl"
    environment = dict(
        os.environ, DOCKER_HOST=docker[-1], PADM_DOCKER_INSTALL_DIR=str(deployment),
        PADM_TEST_NGINX_IMAGE=inputs["nginx"]["image_id"],
        PADM_TEST_NET_IMAGE=inputs["net"]["image_id"], PADM_TEST_COMPOSE_CALLS=str(calls),
        PADM_TEST_CONFIG_HASHES="\n".join(
            hashlib.sha256(path.read_bytes()).hexdigest() + "  " + str(path) for path in paths),
        PADM_TEST_SOURCE_HOSTS=json.dumps(list(HOST.values()) +
                                         ["198.18.2.4", "fd42:7061:646d:2::4"]),
        DOCKER_FAIL2BAN_SOURCE_IPV4=SOURCES["ipv4"][0],
        DOCKER_FAIL2BAN_SOURCE_IPV6=SOURCES["ipv6"][0])
    jail_absent(docker)
    process = subprocess.Popen(
        ["bash", "-Eeuo", "pipefail", "-c", FIXTURE_RUNTIME + "\ndockerFail2banStartVerified",
         "test", str(ROOT / "install-docker.sh")], env=environment,
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, bufsize=0)
    transcript, pending, challenges, proofs = bytearray(), b"", [], []
    nginx_snapshot = None
    deadline = time.monotonic() + 120
    try:
        with selectors.DefaultSelector() as reader:
            reader.register(process.stderr, selectors.EVENT_READ)
            while reader.get_map():
                assert time.monotonic() < deadline, "生产启用事务未完成"
                if not reader.select(timeout=0.5):
                    continue
                block = os.read(process.stderr.fileno(), 65536)
                if not block:
                    reader.unregister(process.stderr)
                    break
                transcript.extend(block)
                pending += block
                while b"\n" in pending:
                    raw, pending = pending.split(b"\n", 1)
                    line = raw.decode()
                    if line.startswith("source-challenge="):
                        assert len(challenges) == len(proofs), "未完成见证就进入下一挑战"
                        challenge = json.loads(line.removeprefix("source-challenge="))
                        port, family, listener, internal = expected[len(challenges)]
                        assert challenge["public_port"] == port and challenge["family"] == family
                        assert challenge["domain"] == "source.padm.test"
                        uri = challenge["uri"]
                        assert uri.startswith("/.well-known/padm-source/")
                        assert len(uri.rsplit("/", 1)[1]) == 48
                        jail_absent(docker)
                        nginx_id = command(compose + ["ps", "-q", "nginx"]).decode().strip()
                        nginx = inspect(docker, nginx_id)
                        snapshot = dict(id=nginx["Id"], started_at=nginx["State"]["StartedAt"],
                                        restart_count=nginx["RestartCount"])
                        if nginx_snapshot is None:
                            nginx_snapshot = snapshot
                        assert snapshot == nginx_snapshot, "挑战过程中 Nginx 已重建"
                        assert uri.encode() not in command(docker + ["logs", nginx_id])
                        address = HOST[family] if family == "ipv4" else f"[{HOST[family]}]"
                        result = command([
                            "nsenter", "--target", str(client_processes[0].pid), "--net", "--",
                            "curl", "-4" if family == "ipv4" else "-6", "--fail", "--show-error",
                            "--silent", "--noproxy", "*", "--max-time", "3",
                            "--cacert", str(deployment / "secrets/tls/source.padm.test.crt"),
                            "--resolve", f"source.padm.test:{port}:{address}",
                            "--header", f"X-Forwarded-For: {SOURCES[family][1]}",
                            "--header", f"Forwarded: for=\"{SOURCES[family][1]}\"",
                            "--output", "/dev/null", "--write-out", "%{http_code}",
                            f"https://source.padm.test:{port}{uri}"], timeout=5)
                        assert result == b"204", (challenge, result)
                        challenges.append(challenge)
                    elif line.startswith("source-verified="):
                        assert len(challenges) == len(proofs) + 1, "无当前挑战的来源见证"
                        proof = json.loads(line.removeprefix("source-verified="))
                        port, family, listener, internal = expected[len(proofs)]
                        assert {key: value for key, value in proof.items() if key != "source"} == dict(
                            listener_id=listener, family=family, public_port=port,
                            internal_port=internal), proof
                        assert ipaddress.ip_address(proof["source"]) == ipaddress.ip_address(
                            SOURCES[family][0]), proof
                        proofs.append(proof)
        assert process.wait(timeout=5) == 0, transcript.decode(errors="replace")
        assert len(challenges) == len(proofs) == len(expected), transcript.decode(errors="replace")
        current = inspect(docker, nginx_snapshot["id"])
        assert current["Id"] == nginx_snapshot["id"]
        assert current["State"]["StartedAt"] == nginx_snapshot["started_at"]
        assert current["RestartCount"] == nginx_snapshot["restart_count"]
        records = [json.loads(line) for line in calls.read_text().splitlines()]
        starts = [row for row in records if row[0] == "up"]
        assert len(starts) == 2, records
        assert {"xray", "nginx", "--wait"} <= set(starts[0]), starts
        assert not {"net-fail2ban", "acme", "net-tun-check"} & set(starts[0]), starts
        assert {"net-fail2ban", "--no-deps", "--wait"} <= set(starts[1]), starts
        assert not {"xray", "nginx", "acme", "net-tun-check", "--force-recreate"} & set(starts[1])
        checks = [row for row in records if row[0] == "run"]
        assert len(checks) == 2 and all(row[-4:] == [
            "preflight", "fail2ban", "24444,24445", "unowned"] for row in checks), records
        assert [row[0] for row in records] == ["run", "up", "run", "up"], records
        print("fail2ban-production-start-verified=" + json.dumps(dict(
            mode=mode, proofs=proofs, nginx=nginx_snapshot, compose=records),
            sort_keys=True), flush=True)
        return challenges[-1]["uri"]
    finally:
        (output_root / f"{mode}.start.log").write_bytes(transcript)
        if process.poll() is None:
            stop(process)


def witness(docker, identity, client_processes, family, listener, port, internal_port,
            reject=None, history_uri=None):
    # 离线编排改写了镜像身份，只替换容器审计；挑战、真实日志与来源匹配仍执行生产函数。
    script = r'''
source "$1"
dockerFail2banSourceContainer() {
    [[ "$1" == "$PADM_TEST_SOURCE_LISTENER" && "$2" == "$PADM_TEST_SOURCE_FAMILY" ]] || return 1
    docker inspect "$PADM_TEST_SOURCE_CONTAINER" | jq -ce \
      --argjson public "$PADM_TEST_SOURCE_PORT" --argjson internal "$PADM_TEST_SOURCE_INTERNAL" \
      --argjson hosts "$PADM_TEST_SOURCE_HOSTS" '
      select(length == 1) | .[0] |
      select(.State.Running == true and .State.Restarting == false) |
      {id:.Id,started_at:.State.StartedAt,restart_count:.RestartCount,
       public_port:$public,internal_port:$internal,domain:"source.padm.test",
       networks:(.NetworkSettings.Networks | to_entries |
         map({name:.key,id:.value.NetworkID}) | sort_by(.name)),
       addresses:($hosts + [.NetworkSettings.Networks[] |
         .IPAddress,.Gateway,.GlobalIPv6Address,.IPv6Gateway] | map(select(. != "")) | unique)}
    '
}
dockerFail2banSourceWitness "$2" "$3"
'''
    environment = dict(os.environ, DOCKER_HOST=docker[-1],
                       PADM_TEST_SOURCE_CONTAINER=identity, PADM_TEST_SOURCE_LISTENER=listener,
                       PADM_TEST_SOURCE_FAMILY=family, PADM_TEST_SOURCE_PORT=str(port),
                       PADM_TEST_SOURCE_INTERNAL=str(internal_port),
                       PADM_TEST_SOURCE_HOSTS=json.dumps(list(HOST.values()) +
                           ["198.18.2.4", "fd42:7061:646d:2::4"]))
    if history_uri is None:
        history_uri = "/.well-known/padm-source/" + "f" * 48
    assert client(client_processes[0], family, history_uri, port=port) == {"status": 204}
    process = subprocess.Popen(
        ["bash", "-u", "-c", script, "test", str(ROOT / "install-docker.sh"), listener,
         SOURCES[family][0]], env=environment, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE)
    try:
        with selectors.DefaultSelector() as reader:
            reader.register(process.stdout, selectors.EVENT_READ)
            assert reader.select(timeout=5), "生产来源见证未输出挑战"
            first = process.stdout.readline().strip()
        assert first.startswith("source-challenge="), first
        challenge = json.loads(first.removeprefix("source-challenge="))
        assert challenge["public_port"] == port and challenge["family"] == family
        assert challenge["domain"] == "source.padm.test"
        uri = challenge["uri"]
        assert uri.startswith("/.well-known/padm-source/") and len(uri.rsplit("/", 1)[1]) == 48
        log = docker + ["logs", identity]
        assert uri.encode() not in command(log), "fresh challenge 已存在于历史日志"
        if reject == "port":
            wrong_port = PORT + 1 if port == PORT else PORT
            assert client(client_processes[0], family, uri, port=wrong_port) == {"status": 204}
        elif reject == "source":
            assert client(client_processes[1], family, uri,
                          forged=SOURCES[family][0], port=port) == {"status": 204}
        else:
            # 历史 URI 和重放的旧挑战不能满足新 nonce，正确请求仍使用伪造头验证真实首字段。
            assert client(client_processes[0], family, history_uri, port=port) == {"status": 204}
            time.sleep(0.2)
            assert process.poll() is None, "历史或重放日志提前满足了生产见证"
            assert client(client_processes[0], family, uri, port=port) == {"status": 204}
        output, error = process.communicate(timeout=8)
        if reject is not None:
            assert process.returncode != 0 and "source-verified=" not in output, (reject, output, error)
            print(f"fail2ban-production-source-reject-{reject}=passed", flush=True)
            return uri
        assert process.returncode == 0, (first, output, error)
        assert "source-verified=" in output, (first, output, error)
        proof = next(json.loads(line.removeprefix("source-verified="))
                     for line in output.splitlines() if line.startswith("source-verified="))
        assert {key: value for key, value in proof.items() if key != "source"} == dict(
            listener_id=listener, family=family, public_port=port, internal_port=internal_port), proof
        assert ipaddress.ip_address(proof["source"]) == ipaddress.ip_address(SOURCES[family][0]), proof
        print("fail2ban-production-source-witness=" + json.dumps(
            dict(listener_id=listener, family=family, public_port=port, proof=proof),
            sort_keys=True), flush=True)
        return uri
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()


def installed_port_transaction(docker, node, inputs, clients, output_root):
    fixture = node / "ws-port"
    fixture.mkdir(mode=0o700)
    for relative in ("bin", "home", "tmp", "secrets/tls", "net-image"):
        (fixture / relative).mkdir(parents=True, mode=0o700)
    # 只烘入当前源码，避免额外 bind mount 绕过生产容器归属审计。
    context = fixture / "net-image"
    shutil.copyfile(ROOT / "docker/images/net/entrypoint.sh", context / "entrypoint.sh")
    (context / "entrypoint.sh").chmod(0o755)
    test_tag = "padm-local/padm-net:ws-port-source"
    overlay = command(docker + ["create", "--network", "none", inputs["net"]["reference"]]).decode().strip()
    try:
        command(docker + ["cp", str(context / "entrypoint.sh"), overlay + ":/usr/local/bin/padm-entrypoint"])
        command(docker + ["commit", overlay, test_tag], timeout=60)
    finally:
        command(docker + ["rm", overlay])
    current = json.loads(command(docker + ["image", "inspect", test_tag]))[0]
    digest = current["Descriptor"]["digest"]
    assert digest.startswith("sha256:") and len(digest) == 71, current
    actual = dict(inputs, net=dict(reference=test_tag + "@" + digest, image_id=current["Id"]))
    (fixture / "images.json").write_text(json.dumps(actual))
    spec = json.loads((output_root / "dual/config/spec.json").read_text())
    spec["core"]["protocols"] = spec["core"]["protocols"][:1]
    spec["host_integrations"] = []
    (fixture / "spec.json").write_text(json.dumps(spec))
    for suffix in ("crt", "key"):
        shutil.copyfile(output_root / f"dual/secrets/tls/source.padm.test.{suffix}",
                        fixture / f"secrets/tls/source.padm.test.{suffix}")
    environment = dict(
        os.environ, DOCKER_HOST=docker[-1], HOME=str(fixture / "home"),
        TMPDIR=str(fixture / "tmp"), PADM_DOCKER_INSTALL_DIR=str(fixture / "deployment"),
        PADM_DOCKER_BIN_DIR=str(fixture / "bin"), PADM_DOCKER_HEALTH_TIMEOUT="8",
        PADM_DOCKER_FAIL2BAN_SOURCE_IPV4=SOURCES["ipv4"][1],
        PADM_DOCKER_FAIL2BAN_SOURCE_IPV6=SOURCES["ipv6"][1])
    result = subprocess.run(
        ["bash", str(SCRIPT.with_suffix(".sh")), "--seed", str(fixture)],
        env=environment, capture_output=True, timeout=120)
    (output_root / "ws-port.seed.log").write_bytes(result.stdout + result.stderr)
    assert result.returncode == 0, (result.stdout + result.stderr).decode(errors="replace")
    deployment = fixture / "deployment"
    for family in SOURCES:
        assert client(clients[0], family) == {"status": 200}
    cli = fixture / "bin/padm-docker"
    assert cli.is_symlink() and cli.resolve().is_relative_to(deployment)
    real_docker = shutil.which("docker")
    assert real_docker and not Path(real_docker).is_relative_to(fixture)
    # 发布信任适配只允许已载入的五个精确摘要；Compose、exec 和所有防护审计均透传。
    wrapper = fixture / "bin/docker"
    wrapper.write_text(r'''#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$#" == 2 && "$1" == pull ]]; then
    expected=$(jq -er --arg ref "$2" '
      [.[] | select(.reference == $ref)] | select(length == 1) | .[0].image_id
    ' "$PADM_TEST_WS_IMAGES") || exit 1
    "$PADM_TEST_REAL_DOCKER" image inspect "$2" |
        jq -e --arg ref "$2" --arg id "$expected" '
          length == 1 and .[0].Id == $id and
          .[0].Descriptor.digest == ($ref | split("@")[1])
        ' >/dev/null
    printf 'local-test-only-offline-pull=%s\n' "$2"
    exit 0
fi
exec "$PADM_TEST_REAL_DOCKER" "$@"
''')
    wrapper.chmod(0o755)
    environment.update(PATH=str(fixture / "bin") + ":" + os.environ["PATH"],
                       PADM_TEST_REAL_DOCKER=real_docker,
                       PADM_TEST_WS_IMAGES=str(fixture / "images.json"))
    release = ["--manifest", str(fixture / "configure-release-manifest.json"),
               "--bundle", str(fixture / "configure-release-manifest.sigstore.json"),
               "--control-bundle", str(fixture / "configure-control.tar.gz")]
    used_nonces = set()
    transactions = []

    def service(name):
        return command(docker + ["ps", "-aq", "--filter",
                       "label=com.docker.compose.project=padm-docker", "--filter",
                       f"label=com.docker.compose.service={name}", "--filter",
                       "label=com.docker.compose.oneoff=False"]).decode().strip()

    def state():
        return json.loads((deployment / "config/spec.json").read_text())

    def run_cli(label, arguments, failure=None):
        previous_nginx = service("nginx")
        release_inputs = release if arguments[0] == "edit" else []
        process = subprocess.Popen(["bash", str(cli), *arguments, *release_inputs], env=environment,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, bufsize=0)
        transcript, pending, challenges, proofs = bytearray(), b"", [], []
        rejected, paused = False, None
        deadline = time.monotonic() + 150
        try:
            with selectors.DefaultSelector() as reader:
                reader.register(process.stderr, selectors.EVENT_READ)
                while reader.get_map():
                    assert time.monotonic() < deadline, f"{label} 真实 CLI 超时"
                    try:
                        monitored_port = state()["core"]["protocols"][0]["public_port"] if failure == "health" else None
                    except FileNotFoundError:
                        # 安装和恢复会短暂移走 spec，最终断言仍要求完整原配置。
                        monitored_port = None
                    if failure == "health" and paused is None and monitored_port == 25444:
                        candidates = []
                        for identity in service("nginx").split():
                            if identity == previous_nginx:
                                continue
                            result = subprocess.run(docker + ["inspect", identity], capture_output=True)
                            if result.returncode:
                                # Compose 重建会同时列出旧、新容器，旧 ID 随即消失。
                                assert result.returncode == 1 and (
                                    b"no such object:" in result.stderr.lower() or
                                    b"no such container:" in result.stderr.lower()), result.stderr
                                continue
                            current_nginx = json.loads(result.stdout)[0]
                            if current_nginx["State"]["Running"] and (
                                current_nginx["HostConfig"]["PortBindings"].get("8443/tcp") == [
                                    dict(HostIp="0.0.0.0", HostPort="25444"),
                                    dict(HostIp="::", HostPort="25444")]):
                                candidates.append(identity)
                        assert len(candidates) <= 1, candidates
                        if candidates:
                            paused = candidates[0]
                            command(docker + ["pause", paused])
                            print(f"ws-port-health-real-paused={paused}", flush=True)
                    if paused and monitored_port == PORT:
                        existing = subprocess.run(docker + ["inspect", paused], capture_output=True)
                        if existing.returncode == 0 and json.loads(existing.stdout)[0]["State"]["Paused"]:
                            command(docker + ["unpause", paused])
                    if not reader.select(timeout=0.05):
                        continue
                    block = os.read(process.stderr.fileno(), 65536)
                    if not block:
                        reader.unregister(process.stderr)
                        break
                    transcript.extend(block)
                    pending += block
                    while b"\n" in pending:
                        raw, pending = pending.split(b"\n", 1)
                        line = raw.decode(errors="replace")
                        if paused and "正在恢复旧配置" in line:
                            # 真实健康失败已发生；释放注入故障，让生产恢复能正常停止候选。
                            existing = subprocess.run(docker + ["inspect", paused], capture_output=True)
                            if existing.returncode == 0 and json.loads(existing.stdout)[0]["State"]["Paused"]:
                                command(docker + ["unpause", paused])
                        if line.startswith("source-challenge="):
                            challenge = json.loads(line.removeprefix("source-challenge="))
                            port, family, uri = (challenge[name] for name in ("public_port", "family", "uri"))
                            assert port in (PORT, 25444) and family in SOURCES, challenge
                            assert challenge["domain"] == "source.padm.test"
                            assert uri.startswith("/.well-known/padm-source/") and len(uri.rsplit("/", 1)[1]) == 48
                            assert uri not in used_nonces, "事务复用了旧来源 nonce"
                            used_nonces.add(uri)
                            jail_absent(docker)
                            identity = service("nginx")
                            assert uri.encode() not in command(docker + ["logs", identity])
                            client_number = 1
                            if failure == "source" and port == 25444 and not rejected:
                                client_number, rejected = 0, True
                            address = HOST[family] if family == "ipv4" else f"[{HOST[family]}]"
                            response = command([
                                "nsenter", "--target", str(clients[client_number].pid), "--net", "--",
                                "curl", "-4" if family == "ipv4" else "-6", "--fail", "--show-error",
                                "--silent", "--noproxy", "*", "--max-time", "3", "--cacert",
                                str(deployment / "secrets/tls/source.padm.test.crt"), "--resolve",
                                f"source.padm.test:{port}:{address}", "--header",
                                f"X-Forwarded-For: {SOURCES[family][1-client_number]}", "--header",
                                f"Forwarded: for=\"{SOURCES[family][1-client_number]}\"",
                                "--output", "/dev/null", "--write-out", "%{http_code}",
                                f"https://source.padm.test:{port}{uri}"], timeout=5)
                            assert response == b"204", (challenge, response)
                            challenges.append(challenge)
                        elif line.startswith("source-verified="):
                            proof = json.loads(line.removeprefix("source-verified="))
                            assert proof["listener_id"] == "entry-source-ws" and proof["internal_port"] == 8443
                            assert ipaddress.ip_address(proof["source"]) == ipaddress.ip_address(
                                SOURCES[proof["family"]][1]), proof
                            proofs.append(proof)
            status = process.wait(timeout=5)
            assert status == (14 if failure else 0), (label, status, transcript.decode(errors="replace"))
            if failure:
                assert state()["core"]["protocols"][0]["public_port"] == PORT
                assert {row["family"] for row in proofs if row["public_port"] == PORT} == set(SOURCES)
                if failure == "source":
                    assert rejected and not any(row["public_port"] == 25444 for row in proofs)
                    assert "来源" in transcript.decode(errors="replace")
                else:
                    assert paused and not any(row["public_port"] == 25444 for row in challenges)
                    assert any(word in transcript for word in (
                        b"paused", b"unhealthy", b"not healthy", b"timeout")), transcript
            else:
                assert len(challenges) == len(proofs) == 2
                assert {row["family"] for row in proofs} == set(SOURCES)
            assert not (deployment / "locks/deployment.lock").exists()
            assert not list(deployment.glob(".candidate.*"))
            transactions.append(dict(case=label, status=status, challenges=challenges,
                                     proofs=proofs, real_health_failure=paused is not None))
            print(f"ws-port-transaction-passed={label}:rc={status}:proofs={len(proofs)}", flush=True)
        finally:
            (output_root / f"ws-port.{label}.log").write_bytes(transcript)
            if process.poll() is None:
                stop(process)

    def bans():
        response = json.loads(command(docker + [
            "exec", service("net-fail2ban"), "python3", "-c",
            "import json; from fail2ban.client.csocket import CSocket; "
            "s=CSocket('/run/fail2ban/fail2ban.sock'); "
            "r=s.send(['get','padm-nginx','banip']); s.close(); print(json.dumps(r))"]))
        assert response[0] == 0, response
        return {str(ipaddress.ip_address(address)) for address in response[1]}

    database = deployment / "data/net/fail2ban/fail2ban.sqlite3"

    def database_bans():
        with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as connection:
            return {str(ipaddress.ip_address(row[0])) for row in connection.execute(
                "SELECT DISTINCT ip FROM bans WHERE jail='padm-nginx'")}

    expected_bans = {str(ipaddress.ip_address(SOURCES[family][0])) for family in SOURCES}

    def enforce(port):
        wait_ready(lambda: bans() == expected_bans, "旧 SQLite 双栈封禁没有恢复")
        assert database_bans() >= expected_bans
        assert database.stat().st_ino == database_inode, "端口事务替换了 SQLite"
        for family, table in (("ipv4", "iptables"), ("ipv6", "ip6tables")):
            net = service("net-fail2ban")
            rules = command(docker + ["exec", net, table + "-save", "-c"]).decode()
            hook = next(line for line in rules.splitlines() if "-A DOCKER-USER " in line and "padm-f2b" in line)
            assert f"--ctorigdstport {port}" in hook, hook
            assert f"--ctorigdstport {PORT if port == 25444 else 25444}" not in rules, rules
            address = str(ipaddress.ip_address(SOURCES[family][0]))
            line = next(row for row in rules.splitlines() if f"-s {address}/" in row and "-j DROP" in row)
            count = int(line.split(":", 1)[0].lstrip("["))
            access = deployment / "logs/nginx/access.log"
            before = access.read_bytes()
            assert client(clients[0], family, port=port) == {"timeout": True}
            after = command(docker + ["exec", net, table + "-save", "-c"]).decode()
            line = next(row for row in after.splitlines() if f"-s {address}/" in row and "-j DROP" in row)
            assert int(line.split(":", 1)[0].lstrip("[")) > count
            assert access.read_bytes() == before
            assert client(clients[1], family, port=port) == {"status": 200}
        environment_check = subprocess.run(
            ["bash", str(cli), "fail2ban", "status"], env=environment, capture_output=True, timeout=30)
        assert environment_check.returncode == 0, environment_check.stderr.decode()

    run_cli("enable", ["edit", "--fail2ban-enable", str(PORT), "3", "600", "3600",
                       "--confirm", "PADM-DOCKER-EDIT"])
    dns_probe = json.loads(command(docker + [
        "exec", service("net-fail2ban"), "python3", "-c",
        "import json,socket,time; from pathlib import Path; "
        "from fail2ban.server.ipdns import DNSUtils; "
        "started=time.monotonic(); addresses=DNSUtils.getSelfIPs(); "
        "print(json.dumps(dict(hostname=socket.gethostname(),fqdn=socket.getfqdn(),"
        "hosts=Path('/etc/hosts').read_text(),addresses=sorted(map(str,addresses)),"
        "elapsed=round(time.monotonic()-started,3))))"], timeout=5))
    assert dns_probe["elapsed"] < 3 and not expected_bans & set(dns_probe["addresses"]), dns_probe
    (output_root / "ws-port.dns.json").write_text(json.dumps(dns_probe, indent=2))
    print("ws-port-native-self-dns=" + json.dumps(dns_probe, sort_keys=True), flush=True)
    for family in SOURCES:
        for attempt in range(3):
            assert client(clients[0], family, f"/.env?port={attempt}") == {"status": 404}
        access = deployment / "logs/nginx/access.log"
        print(f"ws-port-baseline-{family}-access=" + access.read_text(), flush=True)
        print(command(docker + ["exec", service("net-fail2ban"), "fail2ban-regex",
                               "--print-all-matched", "/var/log/padm/nginx/access.log",
                               "/etc/fail2ban/filter.d/padm-nginx.conf"]).decode(), flush=True)
        wait_ready(lambda: str(ipaddress.ip_address(SOURCES[family][0])) in bans(),
                   f"{family} 初始日志封禁失败")
    wait_ready(lambda: database_bans() >= expected_bans, "真实日志封禁没有写入 SQLite")
    database_inode = database.stat().st_ino
    enforce(PORT)
    frozen = {name: (deployment / name).read_bytes() for name in (
        "config/spec.json", "compose.json", "deployment.json", "images.env",
        "config/nginx/default.conf", "config/xray/config.json")}
    for failure in ("source", "health"):
        run_cli(f"{failure}-rollback", ["edit", "--fail2ban-port", "entry-source-ws", "25444",
                                      "--confirm", "PADM-DOCKER-EDIT"], failure)
        assert all((deployment / name).read_bytes() == value for name, value in frozen.items())
        enforce(PORT)
    before = state()
    run_cli("migrate", ["edit", "--fail2ban-port", "entry-source-ws", "25444",
                       "--confirm", "PADM-DOCKER-EDIT"])
    after = state()
    expected = json.loads(json.dumps(before))
    expected["core"]["protocols"][0]["public_port"] = 25444
    expected["host_integrations"][0]["settings"]["ports"] = [25444]
    assert after == expected, "端口事务修改了无关规格"
    enforce(25444)
    nginx = inspect(docker, service("nginx"))
    assert nginx["HostConfig"]["PortBindings"]["8443/tcp"] == [
        dict(HostIp="0.0.0.0", HostPort="25444"), dict(HostIp="::", HostPort="25444")]
    for family in SOURCES:
        refused = subprocess.run(
            ["nsenter", "--target", str(clients[1].pid), "--net", "--", "python3", str(SCRIPT),
             "client", family, "/", SOURCES[family][0], str(PORT)], capture_output=True, timeout=5)
        assert refused.returncode != 0 and b"ConnectionRefusedError" in refused.stderr, refused.stderr
    result = subprocess.run(["bash", str(cli), "down"], env=environment, capture_output=True, timeout=35)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert database_bans() >= expected_bans and database.stat().st_ino == database_inode
    for table in ("iptables-save", "ip6tables-save"):
        assert b"padm-f2b" not in command(docker + [
            "run", "--rm", "--network", "host", "--cap-drop", "ALL", "--cap-add", "NET_ADMIN",
            "--entrypoint", table, actual["net"]["reference"]])
    evidence = dict(scope="local-test-only-not-release-verified", images=actual,
                    net_entrypoint_sha256=hashlib.sha256((context / "entrypoint.sh").read_bytes()).hexdigest(),
                    sqlite_bans=sorted(database_bans()), transactions=transactions,
                    old_port_closed=True, old_rules_removed=True)
    (output_root / "ws-port.evidence.json").write_text(json.dumps(evidence, indent=2))
    print("fail2ban-ws-port-transaction-evidence=" + json.dumps(evidence, sort_keys=True), flush=True)


def run(root):
    assert os.getuid() == 0 and sys.platform == "linux" and Path("/.dockerenv").is_file()
    assert {item["ifname"] for item in json.loads(command(["ip", "-j", "link", "show"]))} == {
        "lo"}, "不得借用宿主接口或已有网络"
    # 隔离宿主只解析自己的机名，避免离线 DNS 阻塞原生 ignoreSelf 检查。
    hostname = socket.gethostname()
    assert hostname and not any(character.isspace() for character in hostname)
    with Path("/etc/hosts").open("a") as hosts:
        hosts.write(f"\n127.0.0.1\t{hostname}\n")
    assert all(ipaddress.ip_address(row[4][0]).is_loopback
               for row in socket.getaddrinfo(hostname, None))
    host_dns = dict(hostname=hostname, fqdn=socket.getfqdn(), hosts=Path("/etc/hosts").read_text())
    (root / "isolated-host.dns.json").write_text(json.dumps(host_dns, indent=2))
    print("fail2ban-isolated-host-dns=" + json.dumps(host_dns, sort_keys=True), flush=True)
    inputs = json.loads(Path("/node-images.json").read_text())
    assert {"xray", "sing-box", "nginx", "ops", "net"} <= inputs.keys()
    node = Path(tempfile.mkdtemp(prefix=".tmp-fail2ban-source-", dir="/n"))
    node.chmod(0o755)
    daemon, cron, clients = None, None, []
    docker = ["docker", "--host", f"unix://{node}/docker.sock"]
    started = time.monotonic()
    with (node / "daemon.log").open("wb") as log:
        try:
            daemon = subprocess.Popen([
                "dockerd", "--host", docker[-1], "--data-root", str(node / "docker"),
                "--exec-root", str(node / "run"), "--pidfile", str(node / "daemon.pid"),
                "--feature", "containerd-snapshotter=true", "--storage-driver", "overlayfs",
                "--bip", "172.30.0.1/24", "--ipv6", "--fixed-cidr-v6", "fd42:7061:646d:30::/64"],
                stdout=log, stderr=log)
            wait_ready(lambda: subprocess.run(docker + ["info"], capture_output=True).returncode == 0,
                       "隔离 daemon 未就绪", 30)
            command(docker + ["load", "--input", "/node-images.tar"], timeout=120)
            for item in inputs.values():
                image = json.loads(command(docker + ["image", "inspect", item["reference"]]))[0]
                assert image["Id"] == item["image_id"]
            cron = subprocess.Popen(["cron", "-f"], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            wait_ready(lambda: cron.poll() is None and subprocess.run(
                ["pgrep", "-x", "cron"], capture_output=True).returncode == 0, "隔离 cron 未就绪")
            clients = namespaces()
            entrypoint = node / "entrypoint.sh"
            shutil.copyfile(ROOT / "docker/images/net/entrypoint.sh", entrypoint)
            entrypoint.chmod(0o755)
            evidence = {"ipv4": "unverified", "dual_ipv4": "unverified",
                        "ipv6": "unverified", "start_ipv4": "unverified",
                        "start_dual": "unverified", "image_ids": inputs}
            for mode in ("ipv4", "dual"):
                deployment = node / mode
                command(["cp", "-a", str(root / mode), str(deployment)])
                source = json.loads((deployment / "compose.json").read_text())
                source["services"] = {name: source["services"][name]
                                      for name in ("xray", "nginx", "net-fail2ban")}
                for name, service in source["services"].items():
                    service["image"] = inputs["net" if name == "net-fail2ban" else name]["image_id"]
                    service["pull_policy"] = "never"
                    for volume in service["volumes"]:
                        volume["source"] = volume["source"].replace(
                            "${PADM_DOCKER_ROOT}", str(deployment)).replace(
                            "${PADM_NET_ROOT}", str(deployment))
                    service["restart"] = "no"
                service = source["services"]["net-fail2ban"]
                # 离线夹具解析自己的固定机名，保留 Fail2ban ignoreself 检查。
                service["hostname"] = "source-fixture.padm.test"
                service["extra_hosts"] = ["source-fixture.padm.test:127.0.0.1"]
                service["volumes"].append(dict(
                    type="bind", source=str(entrypoint),
                    target="/usr/local/bin/padm-entrypoint", read_only=True))
                service["entrypoint"] = ["sh", "/usr/local/bin/padm-entrypoint"]
                compose_path = deployment / "compose.json"
                compose_path.write_text(json.dumps(source))
                compose = docker + ["compose", "--project-name", "padm-docker", "--file",
                                    str(compose_path), "--profile", "*"]
                history_uri = verified_start(docker, compose, deployment, inputs, clients, mode, root)
                evidence[f"start_{mode}"] = "passed"
                identities = {name: command(compose + ["ps", "-q", name]).decode().strip()
                              for name in source["services"]}
                nginx = inspect(docker, identities["nginx"])
                host = nginx["HostConfig"]
                assert host["ReadonlyRootfs"] and not host["Privileged"]
                assert host["CapDrop"] == ["ALL"] and not host["CapAdd"]
                assert nginx["Config"]["User"] == "10001:10001"
                for public_port, internal_port in ((PORT, 8443), (PORT + 1, 8444)):
                    assert host["PortBindings"][f"{internal_port}/tcp"] == [
                        dict(HostIp="0.0.0.0", HostPort=str(public_port))] + (
                        [dict(HostIp="::", HostPort=str(public_port))] if mode == "dual" else [])
                networks = nginx["NetworkSettings"]["Networks"]
                assert set(networks) == {"padm-docker"} | (
                    {"padm-docker-ipv6"} if mode == "dual" else set()), networks
                if mode == "dual":
                    ipv6_network = json.loads(command(docker + [
                        "network", "inspect", "padm-docker-ipv6"]))[0]
                    assert ipv6_network["EnableIPv6"] and ipv6_network["Driver"] == "bridge"
                    assert all(ipv6_network["Labels"].get(name) == value for name, value in {
                        "io.padm.mode": "docker", "io.padm.project": "padm-docker",
                        "io.padm.component": "routing-ipv6"}.items())
                    assert networks["padm-docker-ipv6"]["GlobalIPv6Address"], networks
                net = inspect(docker, identities["net-fail2ban"])
                print("fail2ban-source-inspect-caps=" + json.dumps(dict(
                    cap_add=net["HostConfig"]["CapAdd"], cap_drop=net["HostConfig"]["CapDrop"])),
                    flush=True)
                assert net["HostConfig"]["NetworkMode"] == "host"
                assert [name.removeprefix("CAP_") for name in net["HostConfig"]["CapAdd"]] == [
                    "NET_ADMIN"], net["HostConfig"]["CapAdd"]
                assert net["HostConfig"]["CapDrop"] == ["ALL"] and not net["HostConfig"]["Privileged"]
                wait_ready(lambda: subprocess.run(
                    docker + ["exec", identities["net-fail2ban"], "fail2ban-client", "status", "padm-nginx"],
                    capture_output=True).returncode == 0, "Fail2ban 未就绪")
                families = ("ipv4",) if mode == "ipv4" else ("ipv4", "ipv6")
                for family in families:
                    wait_ready(lambda: client(clients[0], family).get("status") == 200,
                               f"{family} 发布连接未就绪")
                    if mode == "ipv4":
                        history_uri = witness(docker, identities["nginx"], clients, family,
                                              "entry-source-ws", PORT, 8443, history_uri=history_uri)
                        for reason in ("port", "source"):
                            witness(docker, identities["nginx"], clients, family,
                                    "entry-source-ws", PORT, 8443, reject=reason)
                    assert client(clients[0], family) == {"status": 200}
                    access = deployment / "logs/nginx/access.log"
                    wait_ready(lambda: access.stat().st_size > 0, f"{family} 请求没有真实日志")
                    source_address, forged = SOURCES[family]
                    line = access.read_text().splitlines()[-1]
                    assert line.startswith(source_address + " "), f"{family} 真实来源丢失：{line}"
                    exec_net = docker + ["exec", identities["net-fail2ban"], "fail2ban-client"]
                    def query_bans():
                        response = json.loads(command(docker + [
                            "exec", identities["net-fail2ban"], "python3", "-c",
                            "import json; from fail2ban.client.csocket import CSocket; "
                            "s=CSocket('/run/fail2ban/fail2ban.sock'); "
                            "r=s.send(['get','padm-nginx','banip']); s.close(); print(json.dumps(r))"]))
                        assert response[0] == 0, response
                        return set(response[1])
                    assert not query_bans()
                    for attempt in range(3):
                        assert client(clients[0], family, f"/.env?attempt={attempt}", forged) == {
                            "status": 404}
                    print(f"fail2ban-source-real-{family}-access:\n" + access.read_text(), flush=True)
                    print(command(docker + ["exec", identities["net-fail2ban"], "fail2ban-regex",
                          "--print-all-matched", "/var/log/padm/nginx/access.log",
                          "/etc/fail2ban/filter.d/padm-nginx.conf"]).decode(), flush=True)
                    wait_ready(lambda: source_address in query_bans(), f"{family} 日志未触发封禁")
                    assert query_bans() == {source_address}, "伪造头污染封禁地址"
                    table = "iptables" if family == "ipv4" else "ip6tables"
                    # 同时证明真实 DNAT/DOCKER-USER DROP，不接受只有超时的间接结论。
                    save_rules = docker + ["exec", identities["net-fail2ban"], table + "-save", "-c"]
                    rules = command(save_rules).decode()
                    drop_line = next(line for line in rules.splitlines()
                                     if f"-s {source_address}/" in line and "-j DROP" in line)
                    count = int(drop_line.split(":", 1)[0].lstrip("["))
                    before = access.read_text()
                    assert client(clients[0], family) == {"timeout": True}
                    after_rules = command(save_rules).decode()
                    after_line = next(line for line in after_rules.splitlines()
                                      if f"-s {source_address}/" in line and "-j DROP" in line)
                    assert int(after_line.split(":", 1)[0].lstrip("[")) > count
                    assert access.read_text() == before, "被封连接仍进入 Nginx"
                    assert client(clients[1], family) == {"status": 200}, "封禁误伤第二客户端"
                    if mode == "dual":
                        other = "ipv6" if family == "ipv4" else "ipv4"
                        assert client(clients[0], other) == {"status": 200}, "封禁误伤另一地址族"
                    command(exec_net + ["set", "padm-nginx", "unbanip", source_address])
                    wait_ready(lambda: source_address not in query_bans(), f"{family} 解封未完成")
                    wait_ready(lambda: client(clients[0], family) == {"status": 200},
                               "解封未恢复真实连接")
                    evidence["dual_ipv4" if mode == "dual" and family == "ipv4" else family] = "passed"
                    print(f"fail2ban-source-real-{mode}-{family}: source/forged-header/filter/"
                          "DNAT/DROP-counter/second-client/unban passed", flush=True)
                command(docker + ["exec", identities["net-fail2ban"],
                                   "/usr/local/bin/padm-entrypoint", "fail2ban-health"])
                for name, identity in identities.items():
                    result = subprocess.run(docker + ["logs", identity], capture_output=True, check=True)
                    (root / f"{mode}.{name}.log").write_bytes(result.stdout + result.stderr)
                command(compose + ["down", "--timeout", "10"], timeout=25)
                assert not (deployment / "data/net/fail2ban/fail2ban.state").exists()
                for table in ("iptables-save", "ip6tables-save"):
                    remaining = command(docker + [
                        "run", "--rm", "--network", "host", "--cap-drop", "ALL",
                        "--cap-add", "NET_ADMIN", "--read-only", "--security-opt",
                        "no-new-privileges:true", "--entrypoint", table, inputs["net"]["image_id"]])
                    assert b"padm-f2b" not in remaining, f"停止后残留 {table} Fail2ban 资源"
            installed_port_transaction(docker, node, inputs, clients, root)
            evidence["ws_port_transaction"] = "passed"
            evidence["elapsed"] = round(time.monotonic() - started, 3)
            print("fail2ban-source-real-evidence=" + json.dumps(evidence, sort_keys=True), flush=True)
            assert all(evidence[family] == "passed" for family in (
                "ipv4", "dual_ipv4", "ipv6", "start_ipv4", "start_dual"))
        except BaseException:
            result = subprocess.run(docker + ["ps", "-aq"], capture_output=True, timeout=10)
            for identity in result.stdout.decode().split() if not result.returncode else []:
                diagnostic = subprocess.run(docker + ["logs", identity], capture_output=True, timeout=10)
                metadata = inspect(docker, identity)
                name = metadata["Config"]["Labels"].get("com.docker.compose.service")
                if name in ("nginx", "net-fail2ban"):
                    (root / f"ws-port.{name}.log").write_bytes(diagnostic.stdout + diagnostic.stderr)
                print((diagnostic.stdout + diagnostic.stderr).decode(errors="replace"), file=sys.stderr)
                if name == "net-fail2ban":
                    diagnostic = subprocess.run(docker + ["exec", identity, "python3", "-c", r'''
import json, os, sqlite3
from pathlib import Path
from fail2ban.client.csocket import CSocket
queries={}
for field in ("banip","logpath","maxretry","findtime","bantime","ignoreip","failregex","idle"):
    client=CSocket("/run/fail2ban/fail2ban.sock")
    queries[field]=client.send(["get","padm-nginx",field])
    client.close()
files={}
for name in ("/var/log/padm/nginx/access.log","/etc/fail2ban/jail.d/padm.local",
             "/etc/fail2ban/filter.d/padm-nginx.conf","/etc/fail2ban/fail2ban.local"):
    path=Path(name)
    files[name]={"stat":list(path.stat()),"text":path.read_text()}
with sqlite3.connect("file:/var/lib/padm/net/fail2ban.sqlite3?mode=ro",uri=True) as database:
    schema=list(database.execute("SELECT name,sql FROM sqlite_master WHERE type='table'"))
    rows=list(database.execute("SELECT * FROM bans"))
processes={}
for process in Path("/proc").iterdir():
    if not process.name.isdigit():
        continue
    try:
        command=(process/"cmdline").read_bytes().replace(b"\0",b" ").decode()
        if "fail2ban-server" in command:
            processes[process.name]={"command":command,"status":(process/"status").read_text()}
    except FileNotFoundError:
        pass
print(json.dumps({"uid":os.getuid(),"gid":os.getgid(),"queries":queries,"files":files,
                  "sqlite_schema":schema,"sqlite_bans":rows,"processes":processes}))
'''], capture_output=True, timeout=10)
                    runtime = diagnostic.stdout + diagnostic.stderr
                    (root / "ws-port.runtime.log").write_bytes(runtime)
                    print(runtime.decode(errors="replace"), file=sys.stderr)
            managed = node / "ws-port/deployment"
            access = managed / "logs/nginx/access.log"
            if access.is_file():
                (root / "ws-port.access.log").write_bytes(access.read_bytes())
                print("ws-port-host-access=" + access.read_text(), file=sys.stderr)
            raise
        finally:
            active_error = sys.exc_info()[0] is not None
            cleanup_error = None
            for client_process in clients:
                stop(client_process)
            if cron is not None:
                stop(cron)
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
            assert node.parent == Path("/n") and node.name.startswith(".tmp-fail2ban-source-")
            try:
                # daemon 退出可能留下 netns 绑定挂载，只卸载本次隔离目录的子挂载。
                mounts = [line.split()[4] for line in Path("/proc/self/mountinfo").read_text().splitlines()
                          if line.split()[4].startswith(str(node) + "/")]
                for mount in sorted(mounts, key=lambda value: value.count("/"), reverse=True):
                    command(["umount", "--lazy", "--", mount], timeout=5)
                shutil.rmtree(node)
            except (OSError, AssertionError, subprocess.TimeoutExpired) as error:
                print(f"fail2ban-source-cleanup: {error}", file=sys.stderr)
                if not active_error:
                    raise
            if cleanup_error:
                raise cleanup_error


if __name__ == "__main__":
    if sys.argv[1] == "client":
        print(json.dumps(request(*sys.argv[2:6])))
    else:
        run(Path(sys.argv[1]))
