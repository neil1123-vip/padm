#!/usr/bin/env bash
set -euo pipefail
umask 077

scope=${PADM_ACME_RECOVERY_REAL_SCOPE:-standalone}
case "${scope}" in standalone|webroot) ;; *) exit 2 ;; esac
[[ "$#" == 0 ]] || exit 2
scriptRoot=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
python3 - "${scriptRoot}" "${scope}" <<'PY'
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import threading

scripts = Path(sys.argv[1])
scope = sys.argv[2]
root = scripts.parents[1]
helpers = runpy.run_path(str(scripts / "http-relay-published-real.py"))
command, stop, wait_ready = (helpers[name] for name in ("command", "stop", "wait_ready"))
assert os.getuid() == 0 and sys.platform == "linux" and Path("/.dockerenv").is_file()
assert {item["ifname"] for item in json.loads(command(["ip", "-j", "link", "show"]))} == {"lo"}
assert not Path("/var/run/docker.sock").exists(), "不得使用宿主 Docker Socket"
inputs = json.loads(Path("/node-images.json").read_text())
assert set(inputs) == ({"ops", "acme", "pebble", "nginx", "xray", "sing-box"}
                       if scope == "webroot" else {"ops", "acme", "pebble"})
node = Path(tempfile.mkdtemp(prefix=".tmp-acme-recovery-", dir="/n"))
docker = ["docker", "--host", f"unix://{node}/docker.sock"]
daemon = None
cron = None
logs = []
network = "padm-acme-recovery"
domain, email = "restore.padm.test", "restore@padm.test"
http_port = 8088 if scope == "webroot" else 8080
api = "https://pebble:14000/dir"
client = "padm-acme-recovery-source"
restored = "padm-acme-recovery-restored"
server = "padm-acme-recovery-ca"
expected_acme = "c7d68b021cfd6380ea83a82962abde5b484779fee0b97d38681dfa1396bbc8d7"
phase = "daemon"


def terminate(*_):
    raise SystemExit(143)


def run(arguments, *, content=None, timeout=30):
    result = subprocess.run(arguments, input=content, capture_output=True, timeout=timeout)
    logs.append((phase, result.stdout + result.stderr))
    assert result.returncode == 0, f"ACME 实际恢复失败：stage={phase} exit={result.returncode}"
    return result.stdout


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def private_tree(directory):
    directory.chmod(0o700)
    for path in directory.rglob("*"):
        assert not path.is_symlink()
        path.chmod(0o700 if path.is_dir() else 0o600)


def volume(name):
    name = "padm-acme-recovery-" + name
    command(docker + ["volume", "create", "--label", "io.padm.test=acme-recovery", name])
    path = Path(json.loads(command(docker + ["volume", "inspect", name]))[0]["Mountpoint"])
    assert path.is_absolute() and path.is_relative_to(node)
    path.chmod(0o700)
    return name, path


def start_client(name, home, tls, ca):
    webroot = [] if scope == "standalone" else [
        "--volume", f"{webroot_volume}:/var/lib/padm/acme-webroot"]
    command(docker + [
        "run", "--pull=never", "--detach", "--name", name,
        "--label", "io.padm.test=acme-recovery", "--network", network,
        "--network-alias", domain, "--read-only", "--user", "10001:10001",
        "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
        "--tmpfs", "/tmp:rw,noexec,nosuid,nodev,size=16m",
        "--env", "CURL_CA_BUNDLE=/ca/pebble.crt",
        "--volume", f"{ca}:/ca:ro", "--volume", f"{home}:/var/lib/padm/acme",
        "--volume", f"{tls}:/var/lib/padm/tls-output",
        *webroot,
        "--entrypoint", "/bin/sh", inputs["acme"]["image_id"], "-c", "exec tail -f /dev/null"])
    observed = json.loads(command(docker + ["inspect", name]))[0]
    assert not observed["HostConfig"]["PortBindings"]
    assert observed["Config"]["User"] == "10001:10001"


def production_check(specification, candidate):
    environment = dict(os.environ, DOCKER_HOST=docker[-1], PADM_DOCKER_SKIP_CHOWN="0")
    result = subprocess.run(
        ["bash", "-c", 'source "$1"; dockerRecoveryAcmeValidate "$2" "$3"',
         "acme-recovery-check", str(root / "install-docker.sh"),
         str(specification), str(candidate)],
        env=environment, capture_output=True, timeout=60)
    logs.append((phase, result.stdout + result.stderr))
    assert result.returncode == 0, "生产 ACME 只读材料校验失败"


def diagnostic(data):
    text = data.decode(errors="replace")
    text = re.sub(r"-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----",
                  "[已隐藏私钥]", text, flags=re.S)
    text = re.sub(r"https://pebble:[0-9]+/[^\s\"'<>]+", "https://pebble/[已隐藏]", text)
    text = re.sub(r"(/\.well-known/acme-challenge/)[A-Za-z0-9_-]+",
                  r"\1[已隐藏]", text)
    text = re.sub(r"\b(authz|challenge|Order) [A-Za-z0-9_-]{16,}", r"\1 [已隐藏]", text)
    return text.replace(email, "[已隐藏邮箱]")


def webroot_recovery_real():
    global phase, cron
    control = runpy.run_path(str(scripts / "control-two-deployment-real.py"))
    cli, services, traffic = (control[name] for name in ("cli", "services", "traffic"))
    path = node
    for relative in ("bin", "home", "tmp", "private", "secrets/tls", "secrets/net/wireguard"):
        (path / relative).mkdir(parents=True, mode=0o700, exist_ok=True)
    deployed = path / "deployment"
    environment = dict(os.environ, DOCKER_HOST=docker[-1], PADM_DOCKER_SKIP_CHOWN="0",
                       PADM_DOCKER_INSTALL_DIR=str(deployed), PADM_DOCKER_BIN_DIR=str(path / "bin"),
                       HOME=str(path / "home"), TMPDIR=str(path / "tmp"), PYTHONDONTWRITEBYTECODE="1")
    command(["crontab", "-"], content=(
        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n"
        f"PADM_DOCKER_BIN_DIR={path}/bin\nHOME={path}/home\nTMPDIR={path}/tmp\n"
        "PYTHONDONTWRITEBYTECODE=1\nMAILTO=\"\"\n"
    ).encode())
    with (path / "cron.log").open("wb") as output:
        cron = subprocess.Popen(["cron", "-f"], stdout=output, stderr=subprocess.STDOUT)
    wait_ready(lambda: cron.poll() is None and subprocess.run(
        ["pgrep", "-x", "cron"], capture_output=True).returncode == 0, 5)
    # 调度安装仍走生产路径，暂停真实进程以避免自动采集干扰手动恢复和续期断言。
    cron.send_signal(signal.SIGSTOP)
    member = {"path": path, "enter": [], "docker": docker, "env": environment}
    images = {name: inputs[name]["reference"] for name in ("ops", "nginx", "xray", "sing-box")}
    # 本场景不启动 net；保留唯一的已载入引用，满足发布夹具对五类镜像的精确校验。
    images["net"] = inputs["acme"]["reference"]
    identity = control["identity"]
    spec = {
        "schema_version": 3,
        "release": {"version": "3.15.0", "manifest_sha256": "1" * 64,
                    "signature_identity": "local-test-only-not-release-verified"},
        "core": {"type": "xray", "secondary_type": None, "protocols": [{
            "id": 21, "core": "xray", "listener_id": "entry-ws", "server": domain,
            "public_port": 35466, "address_families": ["ipv4"], "name": "webroot-recovery-ws",
            "uuid": identity(810), "websocket": {
                "domain": domain, "path": "recovery-webroot", "backend_port": 31297, "tls_port": 8443},
        }]},
        "tls": {"domain": domain, "http01": True},
        "subscription": {"enabled": False, "token": "0" * 16}, "images": images,
        "host_integrations": [], "accounts": [{
            "id": identity(820), "name": "preserved-local", "enabled": True,
            "uuid": identity(830), "password": "Webroot.-~@+=:Local",
            "shadowsocks_password": None, "listeners": ["entry-ws"],
        }],
    }
    for suffix in (".crt", ".key"):
        shutil.copyfile(source_tls / (domain + suffix), path / "secrets/tls" / (domain + suffix))
    control["save"](path / "spec.json", spec)
    phase = "webroot-seed"
    result = subprocess.run(["bash", str(scripts / "control-deployment-node.sh"), str(path)],
                            env=environment, capture_output=True, timeout=180)
    logs.append((phase, result.stdout + result.stderr))
    seed_log = path / "seed-private.log"
    assert result.returncode == 0, "webroot 初装夹具失败：" + (
        seed_log.read_text() if seed_log.is_file() else (result.stdout + result.stderr).decode())[-3000:]
    phase = "webroot-release"
    release = control["wireguard_recovery_release"]([member], images)
    environment = member["env"]
    acme = module("padm_real_webroot_acme", root / "docker/lib/acme_recovery.py")
    shutil.copytree(source_home, deployed / "data/acme", dirs_exist_ok=True)
    (deployed / "data/acme/account.conf").write_bytes(acme.encoded({
        "USER_PATH": acme.TRUSTED_PATH, "CA_BUNDLE": ""}))
    private_tree(deployed / "data/acme")
    cli(member, "acme", "schedule", "enable", "--domain", domain, "--email", email, "--webroot")
    # 客户端信任本地 CA；部署与后续证书仍来自真实签发。
    shutil.copyfile(source_tls / "root.crt", path / "secrets/tls" / (domain + ".crt"))
    client_path = path / "client"
    client_path.mkdir(mode=0o755)
    client_path.chmod(0o755)
    (client_path / "ca.crt").touch(mode=0o644)
    (client_path / "ca.crt").chmod(0o644)
    phase = "webroot-business-before"
    traffic(member, images["sing-box"])
    before = control["state"](member)
    before_home = deployed / "data/acme"
    before_key = (before_home / "ca/pebble/dir/account.key").read_bytes()
    before_ca = acme.assignments((before_home / "ca/pebble/dir/ca.conf").read_bytes(),
                                 {"CA_EMAIL", "ACCOUNT_URL", "CA_KEY_HASH"})
    before_domain_key = (before_home / f"{domain}_ecc/{domain}.key").read_bytes()
    ledger_path = deployed / "data/traffic/state.json"
    archive = path / "private/webroot.tar"
    phase = "webroot-export"
    cli(member, "backup", "export", str(archive))
    cli(member, "backup", "verify", str(archive))
    before_totals = json.loads(ledger_path.read_text())
    cli(member, "down")
    deployed.rename(path / "deployment-before-recovery")
    command(["bash", "-ec", r'''
source "$1"
dockerAcquireDeploymentLock
trap dockerReleaseDeploymentLock EXIT
dockerInitializeStateRoot
dockerInstallBundle "$2"
dockerInstallCli
''', "--", str(root / "install-docker.sh"), str(root)], env=environment, timeout=60)
    phase = "webroot-empty-target-restore"
    helper_stat = (deployed / "bundle/docker/lib/acme_recovery.py").stat()
    assert helper_stat.st_uid == 0 and stat.S_IMODE(helper_stat.st_mode) == 0o640, \
        "真实恢复必须覆盖 root 私有安装脚本的非特权容器调用"
    cli(member, "restore", "apply", str(archive), *release, "--confirm", "PADM-DOCKER-RESTORE")
    assert control["state"](member) == before, "webroot 恢复改变入口、账号或发布身份"
    restored_home = deployed / "data/acme"
    assert (restored_home / "ca/pebble/dir/account.key").read_bytes() == before_key
    assert acme.assignments((restored_home / "ca/pebble/dir/ca.conf").read_bytes(),
                            {"CA_EMAIL", "ACCOUNT_URL", "CA_KEY_HASH"}) == before_ca
    assert (restored_home / f"{domain}_ecc/{domain}.key").read_bytes() == before_domain_key
    assert json.loads(ledger_path.read_text()) == dict(
        before_totals, accounts={key: dict(value, baseline={})
                                for key, value in before_totals["accounts"].items()})
    challenge = deployed / "data/acme-webroot"
    assert challenge.is_dir() and not list(challenge.iterdir()), "恢复后挑战根未清空"
    phase = "webroot-business-restored"
    traffic(member, images["sing-box"])
    before_nginx = services(member, wireguard=False)["nginx"]
    # 本地 CA 直接访问 Nginx 的容器内 HTTP-01 端口，避免 internal 网桥的宿主端口回流。
    command(docker + ["network", "connect", "--alias", domain, network, before_nginx["id"]])
    before_renewal_totals = json.loads(ledger_path.read_text())["accounts"]
    before_registration = (deployed / "secrets/renewal" / domain / "request.json").read_bytes()
    certificate = deployed / "secrets/tls" / (domain + ".crt")
    serial = command(["openssl", "x509", "-in", str(certificate), "-noout", "-serial"])
    # 只给本地 CA 注入网络和信任；真实续期预检、挑战、证书提交及重载保持生产调用。
    wrapped_docker = Path(environment["PATH"].split(":")[0]) / "docker"
    previous_wrapper = wrapped_docker.with_name("docker-release-check")
    wrapped_docker.rename(previous_wrapper)
    wrapped_docker.write_text(r'''#!/usr/bin/env python3
import os, sys
arguments = sys.argv[1:]
if arguments and arguments[0] == "run" and any('os.execvpe("/opt/acme/acme.sh"' in item for item in arguments):
    # 仅让夹具的 NextRenewTime=1 保持到期，不被本地 CA 的未来 ARI 窗口覆盖。
    arguments[1:1] = ["--network", os.environ["PADM_REAL_ACME_NETWORK"],
                     "--env", "CURL_CA_BUNDLE=/ca/pebble.crt",
                     "--env", "SSL_CERT_FILE=/ca/pebble.crt",
                     "--env", "NO_ARI=1",
                     "--volume", os.environ["PADM_REAL_ACME_CA"] + ":/ca:ro",
                     "--volume", os.environ["PADM_REAL_ACME_CA_FILE"]
                     + ":/etc/ssl/certs/ca-certificates.crt:ro"]
release_check = os.path.join(os.path.dirname(sys.argv[0]), "docker-release-check")
os.execv(release_check, [release_check, *arguments])
''')
    wrapped_docker.chmod(0o755)
    environment.update(PADM_REAL_ACME_NETWORK=network, PADM_REAL_ACME_CA=ca_volume,
                       PADM_REAL_ACME_CA_FILE=str(ca_path / "pebble.crt"))
    # 先核实际 ops 的 curl 及 nonce 响应头，避免 HTTP 客户端缺陷拖到续期超时。
    ca_client = docker + [
        "run", "--rm", "--pull=never", "--network", network, "--read-only",
        "--user", "10001:10001", "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges", "--env", "CURL_CA_BUNDLE=/ca/pebble.crt",
        "--volume", f"{ca_volume}:/ca:ro",
        "--entrypoint", "curl", inputs["ops"]["image_id"],
        "--fail", "--silent", "--show-error", "--max-time", "3", "--noproxy", "*"]
    directory = json.loads(command(ca_client + [api], timeout=10))
    assert directory["newOrder"], "实际 ops 未读取到本地 CA 目录"
    nonce_headers = command(ca_client + [
        "--head", "--dump-header", "-", "--output", "/dev/null", directory["newNonce"]], timeout=10)
    assert re.search(rb"(?im)^Replay-Nonce:\s*\S+", nonce_headers), "实际 ops 未读取到 CA nonce"
    config = restored_home / f"{domain}_ecc/{domain}.conf"
    content = config.read_text()
    assert re.search(r"^Le_NextRenewTime='[0-9]+'$", content, re.M)
    config.write_text(re.sub(r"^Le_NextRenewTime='[0-9]+'$", "Le_NextRenewTime='1'", content, flags=re.M))
    polling, failures = threading.Event(), []
    observed_requests = []

    def probe():
        while not polling.is_set():
            try:
                result = subprocess.run(["curl", "--silent", "--show-error", "--max-time", "2",
                                         "--noproxy", "*", "--cacert", str(source_tls / "root.crt"),
                                         "--resolve", f"{domain}:35466:127.0.0.1", "--output", "/dev/null",
                                         f"https://{domain}:35466/"], capture_output=True, timeout=4)
                observed_requests.append(result.returncode)
                if result.returncode:
                    failures.append(result.stderr.decode(errors="replace"))
            except subprocess.TimeoutExpired:
                failures.append("HTTPS 业务观测超时")
            polling.wait(0.1)

    thread = threading.Thread(target=probe, daemon=True)
    phase = "webroot-production-renewal-run"
    thread.start()
    try:
        cli(member, "acme", "auto-renew")
    finally:
        polling.set()
        thread.join(timeout=5)
    assert observed_requests and not failures, "webroot 续期期间 HTTPS 入口中断：" + str(failures)
    assert services(member, wireguard=False)["nginx"] == before_nginx, "webroot 续期重启了 Nginx"
    after_serial = command(["openssl", "x509", "-in", str(certificate), "-noout", "-serial"])
    assert after_serial != serial and after_serial.strip(), "生产续期未更换真实证书"
    assert control["state"](member) == before
    actual = json.loads(ledger_path.read_text())["accounts"]
    assert all(actual[key][field] >= value[field] for key, value in before_renewal_totals.items()
               for field in ("upload", "download")), "生产续期回退累计流量"
    assert (deployed / "secrets/renewal" / domain / "request.json").read_bytes() == before_registration
    assert (restored_home / "ca/pebble/dir/account.key").read_bytes() == before_key
    assert acme.assignments((restored_home / "ca/pebble/dir/ca.conf").read_bytes(),
                            {"CA_EMAIL", "ACCOUNT_URL", "CA_KEY_HASH"}) == before_ca
    assert (restored_home / f"{domain}_ecc/{domain}.key").read_bytes() == before_domain_key
    assert not list(challenge.iterdir()), "生产续期结束后遗留挑战"
    command(["openssl", "verify", "-CAfile", str(source_tls / "root.crt"),
             "-untrusted", str(restored_home / f"{domain}_ecc/ca.cer"),
             str(restored_home / f"{domain}_ecc/{domain}.cer")])
    phase = "webroot-business-renewed"
    traffic(member, images["sing-box"])
    actual = json.loads(ledger_path.read_text())["accounts"]
    assert all(actual[key][field] >= value[field] for key, value in before_totals["accounts"].items()
               for field in ("upload", "download")), "webroot 恢复或续期回退累计流量"
    assert not (deployed / "locks/deployment.lock").exists()
    assert not (deployed / ".restore-pending").exists()
    assert not list(deployed.glob(".tls.*"))
    result = subprocess.run(docker + ["logs", server], capture_output=True, timeout=10)
    assert result.returncode == 0
    ca_log = result.stdout + result.stderr
    assert ca_log.count(b"set VALID by completed challenge") >= 2
    assert ca_log.count(f"http://{domain}:{http_port}/.well-known/acme-challenge/".encode()) >= 6
    print("docker-acme-webroot-recovery-real=" + json.dumps({
        "acme_version": "3.1.6", "release_trust": "fixture", "webroot": acme.WEBROOT,
        "empty_target_restore": True, "production_renewal_run": True,
        "forced_due": {"Le_NextRenewTime": 1, "NO_ARI": "1"},
        "serial_changed": True, "nginx_uninterrupted": True, "https_requests": len(observed_requests),
        "account_domain_key_identity_preserved": True, "traffic_preserved": True,
        "challenge_cleaned": True, "network": "internal",
    }), flush=True)


signal.signal(signal.SIGTERM, terminate)
with (node / "daemon.log").open("wb") as daemon_log:
    try:
        daemon = subprocess.Popen([
            "dockerd", "--host", docker[-1], "--data-root", str(node / "docker"),
            "--exec-root", str(node / "run"), "--pidfile", str(node / "daemon.pid"),
            "--feature", "containerd-snapshotter=true", "--storage-driver", "overlayfs",
            "--bip", "172.31.0.1/24" if scope == "webroot" else "172.30.0.1/24"],
            stdout=daemon_log, stderr=daemon_log)
        wait_ready(lambda: subprocess.run(docker + ["info"], capture_output=True).returncode == 0, 30)
        command(docker + ["load", "--input", "/node-images.tar"], timeout=120)
        for item in inputs.values():
            assert re.fullmatch(r"sha256:[0-9a-f]{64}", item["image_id"])
            observed = json.loads(command(docker + ["image", "inspect", item["image_id"]]))[0]
            assert observed["Id"] == item["image_id"]
        for name in ("ops", "acme"):
            phase = "fixed-client"
            proof = run(docker + [
                "run", "--rm", "--pull=never", "--network", "none", "--read-only",
                "--entrypoint", "python3", inputs[name]["image_id"], "-c",
                'import hashlib, pathlib, subprocess; '
                'p=pathlib.Path("/opt/acme/acme.sh"); '
                f'assert hashlib.sha256(p.read_bytes()).hexdigest()=="{expected_acme}"; '
                'assert b"v3.1.6" in subprocess.check_output([str(p),"--version"]); '
                'print("acme.sh-3.1.6-fixed")'])
            assert proof.strip() == b"acme.sh-3.1.6-fixed"

        phase = "local-ca"
        command(docker + ["network", "create", "--internal", "--label",
                          "io.padm.test=acme-recovery", network])
        inspected_network = json.loads(command(docker + ["network", "inspect", network]))[0]
        assert inspected_network["Internal"]
        ca_volume, ca_path = volume("ca")
        source_volume, source_home = volume("source")
        output_volume, source_tls = volume("output")
        _, candidate = volume("candidate")
        if scope != "standalone":
            webroot_volume, webroot_path = volume("webroot")
            os.chown(webroot_path, 10001, 10001)
        for path in (ca_path, source_home, source_tls):
            os.chown(path, 10001, 10001)
        pebble_config = {"pebble": {
            "listenAddress": "0.0.0.0:14000", "managementListenAddress": "0.0.0.0:15000",
            "certificate": "/ca/pebble.crt", "privateKey": "/ca/pebble.key",
            "httpPort": http_port, "tlsPort": 8443,
            "externalAccountBindingRequired": False}}
        (ca_path / "pebble.json").write_text(json.dumps(pebble_config))
        os.chown(ca_path / "pebble.json", 10001, 10001)
        run(docker + [
            "run", "--rm", "--pull=never", "--network", "none", "--read-only",
            "--user", "10001:10001", "--cap-drop", "ALL",
            "--security-opt", "no-new-privileges", "--volume", f"{ca_volume}:/ca",
            "--entrypoint", "openssl", inputs["ops"]["image_id"], "req",
            "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "/ca/pebble.key",
            "-out", "/ca/pebble.crt", "-subj", "/CN=pebble",
            "-addext", "subjectAltName=DNS:pebble", "-days", "1"])
        command(docker + [
            "run", "--pull=never", "--detach", "--name", server,
            "--label", "io.padm.test=acme-recovery", "--network", network,
            "--network-alias", "pebble", "--read-only", "--user", "10001:10001",
            "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
            "--volume", f"{ca_volume}:/ca:ro", "--env", "PEBBLE_VA_NOSLEEP=1",
            "--env", "PEBBLE_WFE_NONCEREJECT=0", "--env", "PEBBLE_AUTHZREUSE=0",
            inputs["pebble"]["image_id"],
            "-config", "/ca/pebble.json", "-strict"])
        start_client(client, source_volume, output_volume, ca_volume)
        readiness = (
            'import ssl, urllib.request; '
            'context=ssl.create_default_context(cafile="/ca/pebble.crt"); '
            'assert urllib.request.urlopen("https://pebble:14000/dir",'
            'context=context,timeout=2).status==200')
        wait_ready(lambda: subprocess.run(
            docker + ["exec", client, "python3", "-c", readiness],
            capture_output=True, timeout=5).returncode == 0, 30)

        phase = "issue"
        if scope != "standalone":
            command(docker + ["exec", "--detach", client, "python3", "-m", "http.server",
                             str(http_port),
                             "--directory", "/var/lib/padm/acme-webroot"])
            wait_ready(lambda: subprocess.run(
                docker + ["exec", client, "curl", "--fail", "--silent", "--max-time", "2",
                          f"http://127.0.0.1:{http_port}/"], capture_output=True, timeout=4).returncode == 0, 10)
        validation = ["--standalone", "--httpport", "8080"] if scope == "standalone" else \
            ["--webroot", "/var/lib/padm/acme-webroot"]
        run(docker + [
            "exec", client, "/opt/acme/acme.sh", "--home", "/var/lib/padm/acme",
            "--issue", *validation, "--keylength", "ec-256",
            "-d", domain, "--accountemail", email, "--server", api,
            "--ca-bundle", "/ca/pebble.crt"], timeout=120)
        run(docker + [
            "exec", client, "/opt/acme/acme.sh", "--home", "/var/lib/padm/acme",
            "--install-cert", "-d", domain, "--ecc",
            "--fullchain-file", f"/var/lib/padm/tls-output/{domain}.crt",
            "--key-file", f"/var/lib/padm/tls-output/{domain}.key"], timeout=30)
        run(docker + [
            "exec", client, "python3", "-c",
            'import pathlib, ssl, urllib.request; '
            'context=ssl.create_default_context(cafile="/ca/pebble.crt"); '
            'data=urllib.request.urlopen("https://pebble:15000/roots/0",'
            'context=context,timeout=5).read(); '
            'pathlib.Path("/var/lib/padm/tls-output/root.crt").write_bytes(data)'])
        run(docker + [
            "exec", client, "openssl", "verify", "-CAfile", "/var/lib/padm/tls-output/root.crt",
            "-untrusted", f"/var/lib/padm/acme/{domain}_ecc/ca.cer",
            f"/var/lib/padm/acme/{domain}_ecc/{domain}.cer"])
        before_serial = run(docker + [
            "exec", client, "openssl", "x509", "-in", f"/var/lib/padm/tls-output/{domain}.crt",
            "-noout", "-serial"])
        command(docker + ["rm", "-f", client])
        if scope == "webroot":
            webroot_recovery_real()
            raise SystemExit(0)

        phase = "archive-and-normalize"
        acme = module("padm_real_acme", root / "docker/lib/acme_recovery.py")
        recovery = module("padm_real_recovery", root / "docker/lib/recovery.py")
        source = node / "source"
        source.mkdir(mode=0o700)
        for name in recovery.REQUIRED:
            path = source / name
            path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            path.write_bytes(b"docker\n" if name == "mode" else b"{}\n")
        specification = source / "config/spec.json"
        specification.write_text(json.dumps({
            "tls": {"domain": domain}, "images": {"ops": inputs["ops"]["image_id"]}}))
        source_acme = source / "data/acme"
        source_acme.parent.mkdir(mode=0o700)
        shutil.copytree(source_home, source_acme)
        raw_files = {path.relative_to(source_acme).as_posix(): path.read_bytes()
                     for path in source_acme.rglob("*") if path.is_file()}
        try:
            acme.normalize_acme_home(raw_files, domain, email)
        except ValueError:
            pass
        else:
            raise AssertionError("不应导入测试 CA_BUNDLE 路径")
        account = acme.assignments(raw_files["account.conf"], {"USER_PATH", "CA_BUNDLE"})
        assert account["CA_BUNDLE"] == "/ca/pebble.crt"
        # 仅清理夹具专用信任路径；真实归档依然拒绝非空 CA_BUNDLE。
        (source_acme / "account.conf").write_bytes(acme.encoded({
            "USER_PATH": acme.TRUSTED_PATH, "CA_BUNDLE": ""}))
        tls = source / "secrets/tls"
        tls.mkdir(mode=0o700, parents=True)
        for suffix in (".key", ".crt"):
            shutil.copyfile(source_tls / (domain + suffix), tls / (domain + suffix))
        request_path = source / "secrets/renewal" / domain / "request.json"
        request_path.parent.mkdir(mode=0o700, parents=True)
        request_path.write_text(json.dumps({
            "schema_version": 2, "domain": domain, "email": email,
            "provider": "standalone", "enabled": True}))
        private_tree(source)
        archive, stage = node / "backup.tar", node / "stage"
        recovery.export_archive(str(source), str(archive))
        stage.mkdir(mode=0o700)
        recovery.extract_archive(str(archive), str(stage))
        for name in ("data/acme", "secrets/tls"):
            (candidate / name).mkdir(mode=0o700, parents=True)
        summary = recovery.acme_inputs(str(stage), str(candidate))
        assert summary["acme_files"] == 9 and summary["acme_summary"]["acme_version"] == "3.1.6"
        assert recovery.renewal_inputs(str(stage), str(candidate)) == {"renewal_registrations": 1}
        candidate_tls = candidate / "secrets/tls"
        for suffix in (".key", ".crt"):
            path = candidate_tls / (domain + suffix)
            shutil.copyfile(tls / (domain + suffix), path)
            os.chown(path, 10001, 10001)
            path.chmod(0o600)
        os.chown(candidate_tls, 0, 10001)
        candidate_tls.chmod(0o750)
        restored_home = candidate / "data/acme"
        ca_config_path = restored_home / "ca/pebble/dir/ca.conf"
        account_key_path = restored_home / "ca/pebble/dir/account.key"
        before_key = account_key_path.read_bytes()
        before_ca = acme.assignments(ca_config_path.read_bytes(),
                                     {"CA_EMAIL", "ACCOUNT_URL", "CA_KEY_HASH"})
        assert before_ca["CA_KEY_HASH"] == base64.b64encode(
            hashlib.sha256(before_key).digest()).decode()

        phase = "production-material-check"
        production_check(specification, candidate)
        assert all(path.stat().st_uid == 10001 for path in restored_home.rglob("*"))
        assert stat.S_IMODE(candidate_tls.stat().st_mode) == 0o750
        assert (candidate_tls.stat().st_uid, candidate_tls.stat().st_gid) == (0, 10001)
        assert stat.S_IMODE((candidate_tls / (domain + ".key")).stat().st_mode) == 0o600
        assert acme.assignments((restored_home / "account.conf").read_bytes(),
                                {"USER_PATH", "CA_BUNDLE"})["CA_BUNDLE"] == ""

        phase = "forced-renew"
        start_client(restored, restored_home, candidate_tls, ca_volume)
        run(docker + [
            "exec", restored, "curl", "--fail", "--silent", "--show-error",
            "--connect-timeout", "2", "--max-time", "5", api], timeout=10)
        run(docker + [
            "exec", restored, "/opt/acme/acme.sh", "--home", "/var/lib/padm/acme",
            "--renew", "--force", "--ecc", "-d", domain, "--server", api,
            "--ca-bundle", "/ca/pebble.crt"], timeout=120)
        after_serial = run(docker + [
            "exec", restored, "openssl", "x509", "-in", f"/var/lib/padm/tls-output/{domain}.crt",
            "-noout", "-serial"])
        assert before_serial.strip() and after_serial.strip() and before_serial != after_serial
        run(docker + [
            "exec", restored, "/usr/local/bin/padm-entrypoint", "tls-check",
            f"/var/lib/padm/tls-output/{domain}.crt",
            f"/var/lib/padm/tls-output/{domain}.key", domain])
        command(docker + ["rm", "-f", restored])
        run(docker + [
            "run", "--rm", "--pull=never", "--network", "none", "--read-only",
            "--user", "10001:10001", "--cap-drop", "ALL",
            "--security-opt", "no-new-privileges",
            "--volume", f"{source_tls}:/source:ro",
            "--volume", f"{restored_home}:/home:ro",
            "--entrypoint", "openssl", inputs["ops"]["image_id"], "verify",
            "-CAfile", "/source/root.crt", "-untrusted", f"/home/{domain}_ecc/ca.cer",
            f"/home/{domain}_ecc/{domain}.cer"])
        assert account_key_path.read_bytes() == before_key
        after_ca = acme.assignments(ca_config_path.read_bytes(),
                                    {"CA_EMAIL", "ACCOUNT_URL", "CA_KEY_HASH"})
        assert after_ca == before_ca
        assert json.loads((candidate / "secrets/renewal" / domain / "request.json").read_bytes())[
            "enabled"] is True
        account = acme.assignments((restored_home / "account.conf").read_bytes(),
                                   {"USER_PATH", "CA_BUNDLE"})
        assert account.get("CA_BUNDLE", "") in ("", "/ca/pebble.crt")
        (restored_home / "account.conf").write_bytes(acme.encoded({
            "USER_PATH": acme.TRUSTED_PATH, "CA_BUNDLE": ""}))
        phase = "renewed-production-material-check"
        production_check(specification, candidate)
        server_result = subprocess.run(docker + ["logs", server], capture_output=True, timeout=10)
        assert server_result.returncode == 0
        server_log = server_result.stdout + server_result.stderr
        assert server_log.count(b"set VALID by completed challenge") >= 2, "未观察到两次实际授权"
        assert server_log.count(b"Attempting to validate w/ HTTP:") >= 6, "未观察到两次 HTTP-01 验证"
        print("docker-acme-recovery-real=" + json.dumps({
            "acme_version": "3.1.6", "acme_files": 9,
            "production_material_check": True, "forced_renew": True, "serial_changed": True,
            "account_key_hash_url_preserved": True, "renewal_enabled": True,
            "fixture_ca_bundle_cleared": True, "network": "internal"}), flush=True)
    finally:
        active_error = sys.exc_info()[0] is not None and not (
            isinstance(sys.exc_info()[1], SystemExit) and sys.exc_info()[1].code == 0)
        try:
            if daemon is not None:
                if active_error:
                    result = subprocess.run(docker + ["logs", server], capture_output=True, timeout=5)
                    logs.append(("pebble", result.stdout + result.stderr))
                    for label, output in logs:
                        if output:
                            print(f"acme-recovery-diagnostic: stage={label}\n"
                                  + diagnostic(output)[-3000:], file=sys.stderr, flush=True)
                    print(diagnostic((node / "daemon.log").read_bytes())[-2000:],
                          file=sys.stderr, flush=True)
                # 此 daemon 只属于本次测试，同时回收超时命令可能留下的临时容器。
                running = command(docker + ["ps", "-aq"]).decode().split()
                if running:
                    command(docker + ["rm", "-f", *running], timeout=30)
                owned_volumes = command(docker + ["volume", "ls", "-q"]).decode().split()
                if owned_volumes:
                    command(docker + ["volume", "rm", *owned_volumes], timeout=30)
                networks = command(docker + ["network", "ls", "--format", "{{.Name}}"]).splitlines()
                if network.encode() in networks:
                    command(docker + ["network", "rm", network], timeout=15)
                assert not command(docker + ["ps", "-aq"]).strip()
                assert not command(docker + ["volume", "ls", "-q"]).strip()
        finally:
            if cron is not None:
                cron.send_signal(signal.SIGCONT)
                stop(cron)
            if daemon is not None:
                stop(daemon)
            # daemon 退出后回收本节点的命名空间挂载，再删除私有运行目录。
            mounts = json.loads(command(["findmnt", "--json", "--list", "--output", "TARGET"]))
            owned_mounts = [Path(row["target"]) for row in mounts["filesystems"]
                            if Path(row["target"]).is_relative_to(node)]
            for mounted in sorted(owned_mounts, key=lambda path: len(path.parts), reverse=True):
                command(["umount", "--lazy", str(mounted)])
            release_fixture = node.parent / "recovery-release"
            if scope == "webroot" and release_fixture.exists():
                shutil.rmtree(release_fixture)
            assert node.parent == Path("/n") and node.name.startswith(".tmp-acme-recovery-")
            shutil.rmtree(node)
PY
