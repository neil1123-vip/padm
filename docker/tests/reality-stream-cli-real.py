#!/usr/bin/env python3
import argparse
import ast
import copy
import hashlib
import importlib.util
import json
import os
import signal
import stat
import subprocess
import sys
import tempfile
import time
import urllib.parse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOMAIN = "site.padm.test"
HOST_DOMAIN = "host.site.padm.test"
TARGET = "reality.target.test"
GATEWAY = "172.31.0.1"
PRIVATE_KEY = "dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo"
PUBLIC_KEY = "hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo"
ACCOUNT = "00000020-1111-4111-8111-000000000020"
ACCOUNT_UUID = "00000030-1111-4111-8111-000000000030"

# 复用已有隔离节点工具；发布信任仍明确使用本地夹具，不声称正式验签。
module_spec = importlib.util.spec_from_file_location(
    "padm_control_deployment_test", ROOT / "docker/tests/control-two-deployment-real.py")
shared = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(shared)
command, save, enter, stop = shared.command, shared.save, shared.enter, shared.stop


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def current(node):
    return json.loads((node["path"] / "deployment/config/spec.json").read_text())


def cli(node, *arguments, accepted=True):
    started = time.monotonic()
    result = subprocess.run(
        node["enter"] + ["bash", str(node["path"] / "bin/padm-docker"), *arguments],
        env=node["env"], capture_output=True, timeout=180)
    with (node["path"] / "cli.log").open("ab") as output:
        output.write(result.stdout + result.stderr)
    if (result.returncode == 0) != accepted:
        text = shared.diagnostic(node, (result.stdout + result.stderr).decode(errors="replace"))
        raise AssertionError(text.replace(PRIVATE_KEY, "[已隐藏]")[-8000:])
    print(f"reality-cli:{':'.join(arguments[:2])}:rc={result.returncode}:"
          f"elapsed={time.monotonic()-started:.3f}s", flush=True)
    return result


def deployed_services(node):
    ids = command(node["docker"] + [
        "ps", "-aq", "--filter", "label=com.docker.compose.project=padm-docker"]).decode().split()
    result = {}
    for identifier in ids:
        item = json.loads(command(node["docker"] + ["inspect", identifier]))[0]
        name = item["Config"]["Labels"]["com.docker.compose.service"]
        assert name not in result, "发现重复受管服务"
        assert item["State"]["Running"], f"{name} 未运行"
        assert item["State"].get("Health", {}).get("Status") == "healthy", f"{name} 未健康"
        assert item["HostConfig"]["ReadonlyRootfs"] and not item["HostConfig"]["Privileged"]
        assert item["HostConfig"]["CapDrop"] == ["ALL"]
        assert name != "net-transparent", "透明代理不得启用"
        result[name] = item
    expected = set(json.loads((node["path"] / "deployment/compose.json").read_text())["services"]) - {"acme"}
    assert set(result) == expected, f"服务与受管记录不同：{set(result)} / {expected}"
    return result


def snapshot(node):
    root = node["path"] / "deployment"
    result = {}
    for relative in ("config", "deployment.json", "compose.json", "images.env", "secrets/tls", "data/acme"):
        path = root / relative
        paths = [path, *sorted(path.rglob("*"))] if path.is_dir() else [path]
        for item in paths:
            info = item.lstat()
            assert not item.is_symlink()
            result[str(item.relative_to(root))] = (
                digest(item) if item.is_file() else None, stat.S_IMODE(info.st_mode),
                info.st_uid, info.st_gid, info.st_nlink if item.is_file() else None)
    result["crontab"] = command(node["enter"] + ["crontab", "-l"])
    for item in sorted((node["path"] / "cron.d").rglob("*")):
        info = item.lstat()
        assert not item.is_symlink()
        result["cron.d/" + str(item.relative_to(node["path"] / "cron.d"))] = (
            digest(item) if item.is_file() else None, stat.S_IMODE(info.st_mode),
            info.st_uid, info.st_gid)
    return result


def totals(node):
    ledger = json.loads((node["path"] / "deployment/data/traffic/state.json").read_text())
    account = ledger.get("accounts", {}).get(ACCOUNT, {})
    return {key: account.get(key, 0) for key in ("upload", "download")}


def owner_ids(node):
    deployment = json.loads((node["path"] / "deployment/deployment.json").read_text())
    names = {entry["service"] for entry in deployment["listeners"]
             if entry["public_port"] == 443 and entry["transport"] == "tcp"}
    services = deployed_services(node)
    result = [services[name]["Id"] for name in names]
    assert result, "缺少旧 443 拥有者"
    return result


def clean(node):
    root = node["path"] / "deployment"
    assert not (root / "locks/deployment.lock").exists(), "部署锁未释放"
    for pattern in (".candidate.*", ".edit.*", ".protocol.*", ".tls.*"):
        assert not list(root.glob(pattern)), f"临时事务残留：{pattern}"
    independent = json.loads(command(node["docker"] + ["inspect", node["website"]]))[0]
    assert independent["State"]["Running"]
    assert (independent["Id"], independent["State"]["StartedAt"]) == node["website_identity"], \
        "独立网站被重建或停止"
    assert current(node)["host_integrations"] == []
    deployed_services(node)


WRAPPER = r'''#!/usr/bin/env python3
import hashlib
import json
import os
import signal
import subprocess
import sys
from pathlib import Path

args = sys.argv[1:]
real = os.environ["PADM_TEST_REAL_DOCKER"]
root = Path(os.environ["PADM_TEST_REALITY_NODE"])
deployment = root / "deployment"
private = root / "private"
def execute(values, **kwargs):
    return subprocess.run([real, *values], **kwargs)
def inspect(identifier):
    result = execute(["inspect", identifier], capture_output=True, check=True)
    return json.loads(result.stdout)[0]
def record(path, value):
    path.write_text(json.dumps(value))
    path.chmod(0o600)
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def candidate_owner(candidate):
    owners = {entry["service"] for entry in candidate["listeners"]
              if entry["public_port"] == 443 and entry["transport"] == "tcp"}
    assert len(owners) == 1, "候选必须有唯一 443/TCP 服务"
    return next(iter(owners))

if len(args) == 2 and args[0] == "pull":
    images = json.loads(Path(os.environ["PADM_TEST_RECOVERY_IMAGES"]).read_text())
    matches = [value for value in images.values() if value["reference"] == args[1]]
    assert len(matches) == 1
    image = json.loads(execute(["image", "inspect", args[1]], capture_output=True, check=True).stdout)[0]
    assert image["Id"] == matches[0]["image_id"]
    assert image["Descriptor"]["digest"] == args[1].split("@")[1]
    raise SystemExit(0)

# 仅限定本地目标的 DNS/ASN/质量元数据，生产算法与真实协议连接不替换。
if args and args[0] == "run":
    if "-c" in args:
        code = args[args.index("-c") + 1]
        if "https://api.bgpview.io/ip/" in code:
            assert args[-1] == "reality.target.test"
            print("172.31.0.1\tAS64500\tlocal-test-only")
            raise SystemExit(0)
        if "canonical name =" in code:
            assert args[-1] == "reality.target.test"
            raise SystemExit(0)
        if "mode, address, port, domains, families" in code:
            assert args[-5] in ("backend", "ports")
            args[1:1] = ["--env", "SSL_CERT_FILE=/padm-test-ca.crt",
                         "--mount", f"type=bind,src={root}/certs/ca.crt,dst=/padm-test-ca.crt,readonly"]
    if "tls" in args and "ping" in args:
        index = args.index("tls")
        assert args[index:index+4] == ["tls", "ping", "-ip", "172.31.0.1"]
        assert args[-1] in ("reality.target.test:8446", "cloudflare.com:8446")
        print("Pinging with SNI")
        if args[-1] == "cloudflare.com:8446":
            print("Handshake failure")
        else:
            print("Handshake succeeded\nTLS version: TLSv1.3\nCertificate chain length: 4096")
        raise SystemExit(0)

armed = private / "fault.json"
if args and args[0] == "stop" and armed.is_file():
    fault = json.loads(armed.read_text())
    result = execute(args)
    if result.returncode:
        raise SystemExit(result.returncode)
    if all(not inspect(identifier)["State"]["Running"] for identifier in fault["owners"]):
        assert sha(deployment / "config/spec.json") == fault["before"]
        record(private / "stopped.json", {"owners": fault["owners"], "old_spec": fault["before"]})
        if fault["kind"] == "term-stop":
            armed.rename(private / "consumed.json")
            # 精确命中生产 CLI 持锁进程；旧 owner 已停，新规格尚未发布。
            pid = int((deployment / "locks/deployment.lock/pid").read_text())
            record(private / "failure-proof.json", {"stage": "post-stop-pre-install", "pid": pid})
            os.kill(pid, signal.SIGTERM)
    raise SystemExit(0)

if args and args[0] == "compose" and "up" in args and "--wait" in args and armed.is_file():
    fault = json.loads(armed.read_text())
    assert fault["kind"] in ("health", "term-up") and (private / "stopped.json").is_file()
    assert sha(deployment / "config/spec.json") != fault["before"], "候选尚未提交"
    assert all(not inspect(identifier)["State"]["Running"] for identifier in fault["owners"])
    service = candidate_owner(json.loads((deployment / "deployment.json").read_text()))
    if fault["kind"] == "term-up":
        armed.rename(private / "consumed.json")
        result = execute(args)
        assert result.returncode == 0
        selected = execute(["ps", "-aq", "--filter", "label=com.docker.compose.project=padm-docker",
                            "--filter", "label=com.docker.compose.service=" + service],
                           capture_output=True, check=True).stdout.decode().split()
        assert len(selected) == 1
        item = inspect(selected[0])
        assert item["State"]["Running"] and item["State"]["Health"]["Status"] == "healthy"
        record(private / "failure-proof.json", {
            "stage": "candidate-up", "candidate_spec": sha(deployment / "config/spec.json"),
            "old_spec": fault["before"], "container_id": item["Id"], "healthy": True})
        # 候选已真实健康，仍在生产 CLI 的事务提交点之前中断。
        pid = int((deployment / "locks/deployment.lock/pid").read_text())
        os.kill(pid, signal.SIGTERM)
        raise SystemExit(0)
    override = private / "health-override.json"
    record(override, {"services": {service: {"healthcheck": {
        "test": ["CMD", "/bin/sh", "-c", "exit 17"], "interval": "1s",
        "timeout": "1s", "start_period": "0s", "retries": 1}}}})
    armed.rename(private / "consumed.json")
    proof = {"stage": "candidate-installed", "candidate_spec": sha(deployment / "config/spec.json"),
             "old_spec": fault["before"], "service": service, "old_owners_stopped": True}
    index = args.index("up")
    result = execute([*args[:index], "--file", str(override), *args[index:]])
    selected = execute(["ps", "-aq", "--filter", "label=com.docker.compose.project=padm-docker",
                        "--filter", "label=com.docker.compose.service=" + service],
                       capture_output=True, check=True).stdout.decode().split()
    assert len(selected) == 1
    item = inspect(selected[0])
    proof.update(container_id=item["Id"], running=item["State"]["Running"],
                 health=item["State"]["Health"]["Status"], compose_rc=result.returncode,
                 health_exit_codes=[entry["ExitCode"] for entry in item["State"]["Health"]["Log"]])
    record(private / "failure-proof.json", proof)
    assert result.returncode != 0 and proof["running"] and proof["health"] == "unhealthy"
    assert 17 in proof["health_exit_codes"], "真实容器健康检查未命中故障"
    raise SystemExit(result.returncode)

os.execv(real, [real, *args])
'''


SITE = r'''
import http.server
import ssl
import threading
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = (b"padm-reality-cli-proof\n" * 2048 if self.server.server_port == 38999
                else b"padm-independent-site:" + self.connection.padm_sni.encode() + b"\n")
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
def sni(sock, name, context):
    if name not in ("site.padm.test", "host.site.padm.test", "reality.target.test"):
        return ssl.ALERT_DESCRIPTION_UNRECOGNIZED_NAME
    sock.padm_sni = name
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.minimum_version = ssl.TLSVersion.TLSv1_3
context.set_alpn_protocols(["h2", "http/1.1"])
context.load_cert_chain("/fixture/site.crt", "/fixture/site.key")
context.set_servername_callback(sni)
origin = http.server.ThreadingHTTPServer(("0.0.0.0", 38999), Handler)
threading.Thread(target=origin.serve_forever, daemon=True).start()
site = http.server.ThreadingHTTPServer(("0.0.0.0", 8446), Handler)
site.socket = context.wrap_socket(site.socket, server_side=True)
site.serve_forever()
'''

DNS = r'''
import socket
import struct
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
# 回包源地址必须与查询目标一致，不能由跨桥路由选择另一个网关地址。
sock.bind(("172.31.0.1", 53))
while True:
    data, peer = sock.recvfrom(4096)
    index, labels = 12, []
    while data[index]:
        length = data[index]
        labels.append(data[index+1:index+1+length].decode("ascii").lower())
        index += length + 1
    index += 1
    kind, category = struct.unpack("!HH", data[index:index+4])
    question = data[12:index+4]
    name = ".".join(labels)
    answer = (b"\xc0\x0c" + struct.pack("!HHIH", 1, 1, 60, 4) + socket.inet_aton("172.31.0.1")
              if name == "reality.target.test" and kind == 1 and category == 1 else b"")
    header = data[:2] + struct.pack("!HHHHH", 0x8180, 1, int(bool(answer)), 0, 0)
    sock.sendto(header + question + answer, peer)
'''


def certificates(node):
    root = node["path"]
    certs = root / "certs"
    certs.mkdir(mode=0o700)
    command(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2",
             "-subj", "/CN=padm-local-reality-cli-ca", "-addext", "basicConstraints=critical,CA:TRUE",
             "-addext", "keyUsage=critical,keyCertSign,cRLSign", "-keyout", str(certs / "ca.key"),
             "-out", str(certs / "ca.crt")])
    command(["openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes", "-subj", f"/CN={DOMAIN}",
             "-keyout", str(certs / "site.key"), "-out", str(certs / "site.csr")])
    (certs / "extensions").write_text(
        f"subjectAltName=DNS:{DOMAIN},DNS:{HOST_DOMAIN},DNS:{TARGET}\nextendedKeyUsage=serverAuth\n")
    command(["openssl", "x509", "-req", "-in", str(certs / "site.csr"), "-days", "1",
             "-set_serial", "1", "-CA", str(certs / "ca.crt"), "-CAkey", str(certs / "ca.key"),
             "-extfile", str(certs / "extensions"), "-out", str(certs / "site.crt")])
    for extension in ("key", "crt"):
        path = root / f"secrets/tls/{DOMAIN}.{extension}"
        path.write_bytes((certs / f"site.{extension}").read_bytes())
        path.chmod(0o600)
    (certs / "server.py").write_text(SITE)
    for path in certs.iterdir():
        path.chmod(0o600)


def release_fixture(node, images):
    root = node["path"]
    fixture = root / "release-fixture"
    (fixture / "bin").mkdir(parents=True, mode=0o700)
    command(["bash", "-ec", r'''
set -Eeuo pipefail
PROJECT_ROOT=$1 TEST_ROOT=$2 MOCK_BIN=$2/bin OPS_IMAGE=$3
IMAGE_DIGEST=$(printf '%064d' 0)
source "${PROJECT_ROOT}/docker/tests/configure-fixture.sh"
dockerConfigureTestFixture
''', "--", str(ROOT), str(fixture), images["ops"]], timeout=60)
    manifest = fixture / "configure-release-manifest.json"
    value = json.loads(manifest.read_text())
    actual = {}
    for name, reference in images.items():
        image = json.loads(command(node["docker"] + ["image", "inspect", reference]))[0]
        image_digest = reference.split("@")[1]
        assert image["Descriptor"]["digest"] == image_digest
        actual[name] = {"reference": reference, "image_id": image["Id"]}
        value["images"][name] = {"reference": reference, "index_digest": image_digest,
                                 "platforms": {"linux/amd64": image_digest, "linux/arm64": image_digest}}
    save(fixture / "images.json", actual)
    save(manifest, value)
    signature = fixture / "configure-release-manifest.sigstore.json"
    signed = json.loads(signature.read_text())
    signed["manifest_sha256"] = digest(manifest)
    save(signature, signed)
    wrapper = fixture / "bin/docker"
    wrapper.write_text(WRAPPER)
    wrapper.chmod(0o755)
    node["env"].update(PATH=str(fixture / "bin") + ":" + os.environ["PATH"],
                       PADM_TEST_REAL_DOCKER=shared.shutil.which("docker"),
                       PADM_TEST_REALITY_NODE=str(root),
                       PADM_TEST_RECOVERY_IMAGES=str(fixture / "images.json"))
    node["release"] = ("--manifest", str(manifest), "--bundle", str(signature),
                       "--control-bundle", str(fixture / "configure-control.tar.gz"))
    spec = current(node)
    spec["release"] = {"version": value["release"]["version"], "manifest_sha256": digest(manifest),
                       "signature_identity": signed["identity"]}
    path = root / "private/release-spec.json"
    save(path, spec)
    cli(node, "configure", "--spec", str(path), *node["release"])
    assert current(node) == spec


def links(node):
    result = cli(node, "protocol", "links")
    values = result.stdout.decode().splitlines()
    assert len(values) == 6 and all(value.startswith("vless://") for value in values)
    assert sum(urllib.parse.urlsplit(value).username == ACCOUNT_UUID for value in values) == 3
    return values


def client_configuration(spec, values):
    config = {"log": {"loglevel": "info"}, "inbounds": [], "outbounds": [],
              "routing": {"rules": []}}
    selected = (spec.get("reality_stream") or {}).get("listener_id")
    entries = {entry["listener_id"]: entry for entry in spec["core"]["protocols"]}
    for value in values:
        uri = urllib.parse.urlsplit(value)
        if uri.username != ACCOUNT_UUID:
            continue
        pairs = urllib.parse.parse_qs(uri.query, keep_blank_values=True, strict_parsing=True)
        assert all(len(item) == 1 and item[0] for item in pairs.values()), pairs
        query = {key: item[0] for key, item in pairs.items()}
        if query.get("security") != "reality":
            continue
        assert query["type"] in ("tcp", "xhttp")
        listener = "entry-vision" if query["type"] == "tcp" else "entry-xhttp"
        expected = 443 if selected == listener else entries[listener]["public_port"]
        assert uri.port == expected and query["pbk"] == PUBLIC_KEY and query["sni"] == TARGET
        settings = {"network": query["type"], "security": "reality", "realitySettings": {
            "serverName": query["sni"], "fingerprint": query["fp"],
            "publicKey": query["pbk"], "shortId": query["sid"]}}
        assert query["encryption"] == "none"
        user = {"id": ACCOUNT_UUID, "encryption": query["encryption"]}
        if listener == "entry-vision":
            assert query["flow"] == "xtls-rprx-vision"
            user["flow"] = query["flow"]
        else:
            assert "flow" not in query
            settings["xhttpSettings"] = {key: query[key] for key in ("path", "host", "mode")}
            if "extra" in query:
                extra = json.loads(query["extra"])
                assert isinstance(extra, dict)
                settings["xhttpSettings"]["extra"] = extra
        for invalid in (False, True):
            tag = listener + ("-invalid" if invalid else "")
            port = (2081 if listener == "entry-vision" else 2082) + (2 if invalid else 0)
            client = copy.deepcopy(user)
            if invalid:
                client["id"] = "00000099-1111-4111-8111-000000000099"
            config["inbounds"].append({"tag": tag, "listen": "127.0.0.1", "port": port,
                                      "protocol": "socks", "settings": {"auth": "noauth", "udp": False}})
            config["outbounds"].append({"tag": tag, "protocol": "vless", "settings": {
                "vnext": [{"address": "127.0.0.1", "port": uri.port, "users": [client]}]},
                "streamSettings": settings})
            config["routing"]["rules"].append({"type": "field", "inboundTag": [tag], "outboundTag": tag})
    assert len(config["outbounds"]) == 4 and {item["tag"] for item in config["outbounds"]} == {
        "entry-vision", "entry-vision-invalid", "entry-xhttp", "entry-xhttp-invalid"}
    return config


def selfcheck():
    extra = {"noSSEHeader": False, "headers": {"X-Test": "value & next"},
             "downloadSettings": {"address": "download.padm.test", "port": 2445}}

    def uri(network, port, options):
        query = {"encryption": "none", "security": "reality", "sni": TARGET,
                 "fp": "chrome", "pbk": PUBLIC_KEY, "sid": "6ba85179e30d4fc2", "type": network}
        if network == "tcp":
            query["flow"] = "xtls-rprx-vision"
        else:
            query.update(path="/test xhttp/", host=TARGET, mode="auto")
            if options is not None:
                query["extra"] = json.dumps(options)
        return f"vless://{ACCOUNT_UUID}@{DOMAIN}:{port}?" + urllib.parse.urlencode(query)

    rejected = 0
    for selected, options in ((None, None), ("entry-vision", extra), ("entry-xhttp", extra)):
        spec = {"core": {"protocols": [{"listener_id": "entry-vision", "public_port": 2443},
                                     {"listener_id": "entry-xhttp", "public_port": 2444}]},
                "reality_stream": {"listener_id": selected} if selected else None}
        ports = {"entry-vision": 443 if selected == "entry-vision" else 2443,
                 "entry-xhttp": 443 if selected == "entry-xhttp" else 2444}
        values = [uri("tcp", ports["entry-vision"], None), uri("xhttp", ports["entry-xhttp"], options)]
        config = client_configuration(spec, values)
        outbounds = {item["tag"]: item for item in config["outbounds"]}
        assert {item["port"] for item in config["inbounds"]} == {2081, 2082, 2083, 2084}
        for listener, port in ports.items():
            good, bad = outbounds[listener], outbounds[listener + "-invalid"]
            assert good["settings"]["vnext"][0]["port"] == port
            assert good["settings"]["vnext"][0]["users"][0]["id"] == ACCOUNT_UUID
            assert bad["settings"]["vnext"][0]["users"][0]["id"] != ACCOUNT_UUID
            assert good["streamSettings"] == bad["streamSettings"]
        assert outbounds["entry-vision"]["settings"]["vnext"][0]["users"][0]["flow"] == "xtls-rprx-vision"
        assert "flow" not in outbounds["entry-xhttp"]["settings"]["vnext"][0]["users"][0]
        assert outbounds["entry-xhttp"]["streamSettings"]["xhttpSettings"].get("extra") == options
        for invalid in ([values[0], uri("xhttp", ports["entry-xhttp"] + 1, options)],
                        [values[0], values[1] + "&mode=packet-up"], values + values[:1],
                        [values[0], values[1] + "&flow=xtls-rprx-vision"]):
            try:
                client_configuration(spec, invalid)
            except AssertionError:
                rejected += 1
            else:
                raise AssertionError("非法 URI 集合未拒绝")

    # 直接校验故障注入器实际使用的选择函数，不另写一套 owner 逻辑。
    helper = next(node for node in ast.parse(WRAPPER).body
                  if isinstance(node, ast.FunctionDef) and node.name == "candidate_owner")
    namespace = {}
    exec(compile(ast.Module(body=[helper], type_ignores=[]), "WRAPPER", "exec"), namespace)
    for services in (["xray"], ["nginx"], ["nginx-stream"], [], ["xray", "nginx"]):
        candidate = {"listeners": [{"public_port": 443, "transport": "tcp", "service": service}
                                   for service in services]}
        candidate["listeners"].append({"public_port": 443, "transport": "udp", "service": "ignored"})
        try:
            owner = namespace["candidate_owner"](candidate)
        except AssertionError:
            assert len(services) != 1
            rejected += 1
        else:
            assert len(services) == 1 and owner == services[0]
    print(f"reality-cli-selfcheck-ok: uri-configurations=3 owner-services=3 rejected={rejected}")


def traffic(node, images):
    config = client_configuration(current(node), links(node))
    folder = node["path"] / "client"
    folder.mkdir(mode=0o755, exist_ok=True)
    save(folder / "config.json", config)
    (folder / "config.json").chmod(0o644)
    client = command(node["docker"] + [
        "run", "-d", "--network", "host", "--read-only", "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges:true", "--tmpfs", "/tmp",
        "--mount", f"type=bind,src={folder},dst=/input,readonly", images["xray"],
        "run", "-c", "/input/config.json"]).decode().strip()
    before = totals(node)
    try:
        for port in (2081, 2082):
            deadline = time.monotonic() + 12
            while True:
                result = subprocess.run(node["enter"] + [
                    "curl", "-fsS", "--max-time", "3", "--noproxy", "",
                    "--socks5-hostname", f"127.0.0.1:{port}", f"http://{GATEWAY}:38999/proof"],
                    capture_output=True, timeout=5)
                if result.returncode == 0:
                    assert result.stdout == b"padm-reality-cli-proof\n" * 2048
                    break
                if time.monotonic() >= deadline:
                    identifiers = command(node["docker"] + ["ps", "-aq"]).decode().split()
                    output = result.stderr.decode()
                    for identifier in identifiers:
                        output += command(node["docker"] + ["logs", "--tail", "40", identifier]).decode()
                    raise AssertionError(shared.diagnostic(node, output)[-8000:])
                time.sleep(0.1)
        for port in (2083, 2084):
            rejected = subprocess.run(node["enter"] + [
                "curl", "-fsS", "--max-time", "2", "--noproxy", "", "--socks5-hostname",
                f"127.0.0.1:{port}", f"http://{GATEWAY}:38999/proof"], capture_output=True, timeout=4)
            assert rejected.returncode != 0 and not rejected.stdout, f"未授权账号流量未拒绝: {port}"
        cli(node, "traffic", "collect")
        after = totals(node)
        assert after["upload"] > before["upload"]
        assert after["download"] >= before["download"] + len(b"padm-reality-cli-proof\n" * 2048) * 2
    finally:
        command(node["docker"] + ["rm", "-f", client])
    stream = current(node).get("reality_stream") or {}
    host = HOST_DOMAIN if stream.get("host_website") else DOMAIN
    port = 443 if stream else 35443
    command(node["enter"] + ["python3", "-c", r'''
import socket
import ssl
import sys
context = ssl.create_default_context(cafile=sys.argv[1])
with socket.create_connection(("127.0.0.1", int(sys.argv[3])), timeout=5) as connection:
    with context.wrap_socket(connection, server_hostname=sys.argv[2]) as secure:
        secure.sendall(b"GET / HTTP/1.1\r\nHost: " + sys.argv[2].encode() + b"\r\nConnection: close\r\n\r\n")
        response = b""
        while True:
            data = secure.recv(65536)
            if not data:
                break
            response += data
assert response.split(b"\r\n", 1)[0].split()[1] == b"200", response[:256]
if sys.argv[2].startswith("host."):
    assert response.endswith(b"padm-independent-site:" + sys.argv[2].encode() + b"\n")
else:
    assert response.endswith(b"<h1>Welcome</h1>"), response[-256:]
try:
    with socket.create_connection(("127.0.0.1", int(sys.argv[3])), timeout=5) as connection:
        with context.wrap_socket(connection, server_hostname="wrong.padm.test"):
            pass
except (ssl.SSLError, OSError):
    pass
else:
    raise AssertionError("错误 SNI 未拒绝")
''', str(node["path"] / "certs/ca.crt"), host, str(port)])
    clean(node)
    print("reality-cli-traffic-ok:vision+xhttp+both-account-reject+strict-tls-sni", flush=True)


def edit(node, arguments, *, accepted=True):
    return cli(node, "edit", *arguments, "--confirm", "PADM-DOCKER-EDIT",
               *node["release"], accepted=accepted)


def failed_transaction(node, images, label, arguments, *, fault="health"):
    root = node["path"]
    private = root / "private"
    before = snapshot(node)
    uris = links(node)
    cumulative = totals(node)
    for name in ("fault.json", "consumed.json", "stopped.json", "failure-proof.json", "health-override.json"):
        (private / name).unlink(missing_ok=True)
    save(private / "fault.json", {"kind": fault,
                                  "before": digest(root / "deployment/config/spec.json"),
                                  "owners": owner_ids(node)})
    result = edit(node, arguments, accepted=False)
    assert not (private / "fault.json").exists() and (private / "consumed.json").is_file(), \
        "故障未命中真实事务"
    proof = json.loads((private / "failure-proof.json").read_text())
    assert (private / "stopped.json").is_file(), "未证明旧 443 拥有者停止"
    if fault != "health":
        assert result.returncode == 143
        assert proof["stage"] == ("post-stop-pre-install" if fault == "term-stop" else "candidate-up")
        if fault == "term-up":
            assert proof["healthy"] and proof["candidate_spec"] != proof["old_spec"]
    else:
        assert proof["stage"] == "candidate-installed" and proof["old_owners_stopped"]
        assert proof["compose_rc"] != 0 and proof["running"] and proof["health"] == "unhealthy"
        assert 17 in proof["health_exit_codes"]
        assert proof["candidate_spec"] != proof["old_spec"]
    after = snapshot(node)
    changed = {key: (before.get(key), after.get(key)) for key in before.keys() | after.keys()
               if before.get(key) != after.get(key)}
    assert not changed, f"{label} 未恢复原配置、TLS/ACME 字节、权限或调度：{changed}"
    assert links(node) == uris, f"{label} 原账号 URI 改变"
    assert all(totals(node)[key] >= cumulative[key] for key in cumulative), "回滚降低流量累计"
    traffic(node, images)
    print(f"reality-cli-recovery-ok:{label}:{proof['stage']}", flush=True)


def matrix(node, images, selected):
    listener = "entry-" + selected
    modes = {
        "bridge": ("--reality-stream", listener, "entry-website"),
        "host": ("--reality-stream-host", listener, HOST_DOMAIN, GATEWAY, "8446"),
        "loopback": ("--reality-stream-loopback", listener, HOST_DOMAIN, "127.0.0.1", "8446"),
    }
    disable = ("--reality-stream", "off")
    command(node["enter"] + ["python3", "-c", r'''
import socket
for port in (443, 35442, 35443, 8446, 38999):
    with socket.create_connection(("127.0.0.1", port), timeout=2):
        print("reality-cli-listener-ok:" + str(port))
'''])
    services = deployed_services(node)
    core = services["xray"]
    network = next(iter(core["NetworkSettings"]["Networks"]))
    probe = subprocess.run(node["docker"] + [
        "run", "--rm", "--network", network, "--user", "0:0",
        "--mount", f"type=bind,src={node['path']}/certs,dst=/certs,readonly",
        "--entrypoint", "python3", images["ops"], "-c", r'''
import socket
import ssl
from pathlib import Path
print("reality-cli-resolv=" + Path("/etc/resolv.conf").read_text(), flush=True)
context = ssl.create_default_context(cafile="/certs/ca.crt")
with socket.create_connection(("172.31.0.1", 8446), timeout=3) as connection:
    with context.wrap_socket(connection, server_hostname="reality.target.test") as secure:
        print("reality-cli-target-literal-tls=" + secure.version(), flush=True)
print("reality-cli-target-dns=" + repr(socket.getaddrinfo("reality.target.test", 8446)), flush=True)
with socket.create_connection(("reality.target.test", 8446), timeout=3) as connection:
    with context.wrap_socket(connection, server_hostname="reality.target.test") as secure:
        print("reality-cli-target-tls=" + secure.version(), flush=True)
'''], capture_output=True, timeout=15)
    if probe.returncode:
        raise AssertionError((probe.stdout + probe.stderr).decode() +
                             (node["path"] / "dns.log").read_text() +
                             command(node["enter"] + ["ip", "-j", "address"]).decode())
    print("reality-cli-preflight-ok:tcp+target-dns+strict-tls", flush=True)
    traffic(node, images)
    for mode, arguments in modes.items():
        failed_transaction(node, images, mode + "-enable-health", arguments)
        for fault in ("term-stop", "term-up"):
            failed_transaction(node, images, mode + "-enable-" + fault, arguments, fault=fault)
        edit(node, arguments)
        traffic(node, images)
        failed_transaction(node, images, mode + "-disable-health", disable)
        for fault in ("term-stop", "term-up"):
            failed_transaction(node, images, mode + "-disable-" + fault, disable, fault=fault)
        for other, destination in modes.items():
            if mode != other:
                failed_transaction(node, images, mode + "-to-" + other + "-health", destination)
        edit(node, disable)
        traffic(node, images)
    print(f"reality-cli-matrix-ok:selected={selected}:"
          "3-enable+3-disable+6-topology-health+12-term", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--selected", choices=("vision", "xhttp"), default="vision")
    parser.add_argument("--selfcheck", action="store_true")
    arguments = parser.parse_args()
    if arguments.selfcheck:
        selfcheck()
        return
    assert sys.platform == "linux" and os.geteuid() == 0 and Path("/.dockerenv").is_file()
    assert os.uname().machine == "x86_64", "本验收仅覆盖原生 Linux amd64，不使用跨架构模拟"
    inputs = json.loads(Path("/node-images.json").read_text(encoding="utf-8-sig"))
    images = {name: value["reference"] for name, value in inputs.items()}
    assert set(images) == {"xray", "sing-box", "nginx", "ops", "net"}
    archive = Path("/node-images.tar")
    assert archive.is_file()
    holder = daemon = dns = cron = None
    node = None
    with tempfile.TemporaryDirectory(prefix=".tmp-reality-cli-", dir="/n") as directory:
        root = Path(directory)
        root.chmod(0o700)
        try:
            for relative in ("run", "cron", "cron.d", "bin", "home", "tmp", "private",
                             "secrets/tls", "secrets/net/wireguard"):
                (root / relative).mkdir(parents=True, mode=0o700)
            holder = subprocess.Popen(
                ["unshare", "--net", "--mount", "--propagation", "private", "--pid", "--fork",
                 "--kill-child", "--mount-proc", "--", "sleep", "infinity"],
                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            deadline = time.monotonic() + 5
            while True:
                assert holder.poll() is None, "隔离节点创建失败"
                children = Path(f"/proc/{holder.pid}/task/{holder.pid}/children").read_text().split()
                if children:
                    pid = int(children[0])
                    if os.readlink(f"/proc/{pid}/ns/net") != os.readlink("/proc/self/ns/net"):
                        break
                assert time.monotonic() < deadline
                time.sleep(0.02)
            ns = enter(pid)
            for source, target in (("run", "/run"), ("cron", "/var/spool/cron/crontabs"),
                                   ("cron.d", "/etc/cron.d")):
                command(ns + ["mount", "--bind", str(root / source), target])
            command(ns + ["ip", "link", "set", "lo", "up"])
            command(ns + ["crontab", "-"], content=b"MAILTO=\"\"\n")
            with (root / "cron.log").open("wb") as output:
                cron = subprocess.Popen(ns + ["cron", "-f"], stdout=output, stderr=subprocess.STDOUT)
            socket = f"unix://{root}/docker.sock"
            with (root / "daemon.log").open("wb") as output:
                daemon = subprocess.Popen(ns + [
                    "dockerd", "--host", socket, "--host", "unix:///run/docker.sock",
                    "--data-root", str(root / "docker"), "--exec-root", str(root / "run/docker"),
                    "--pidfile", str(root / "run/daemon.pid"), "--feature", "containerd-snapshotter=true",
                    "--storage-driver", "overlayfs", "--bip", GATEWAY + "/24", "--dns", GATEWAY],
                    stdout=output, stderr=subprocess.STDOUT)
            docker = ns + ["docker", "--host", socket]
            deadline = time.monotonic() + 25
            while True:
                assert daemon.poll() is None, (root / "daemon.log").read_text()[-4000:]
                result = subprocess.run(docker + ["info", "--format", "{{json .}}"],
                                        capture_output=True, timeout=3)
                if result.returncode == 0:
                    break
                assert time.monotonic() < deadline, "隔离 daemon 启动超时"
                time.sleep(0.1)
            info = json.loads(result.stdout)
            assert info["OSType"] == "linux" and "name=rootless" not in info["SecurityOptions"]
            with (root / "dns.log").open("wb") as output:
                dns = subprocess.Popen(ns + ["python3", "-c", DNS], stdout=output, stderr=subprocess.STDOUT)
            assert cron.poll() is None, (root / "cron.log").read_text()
            # 验证真实调度登记，但不让墙钟任务干扰事务故障的确定性检查。
            command(ns + ["pkill", "-STOP", "-x", "cron"])
            command(docker + ["load", "--input", str(archive)], timeout=120)
            for name, item in inputs.items():
                actual = json.loads(command(docker + ["image", "inspect", item["reference"]]))[0]
                assert actual["Id"] == item["image_id"], name + " 镜像不匹配"
            env = os.environ | {
                "DOCKER_HOST": socket, "PADM_DOCKER_INSTALL_DIR": str(root / "deployment"),
                "PADM_DOCKER_BIN_DIR": str(root / "bin"), "HOME": str(root / "home"),
                "TMPDIR": str(root / "tmp"), "PYTHONDONTWRITEBYTECODE": "1",
                "PADM_DOCKER_HEALTH_TIMEOUT": "10",
            }
            node = {"path": root, "pid": pid, "enter": ns, "docker": docker, "env": env}
            certificates(node)
            website = command(docker + [
                "run", "-d", "--network", "host", "--read-only", "--user", "0:0",
                "--cap-drop", "ALL", "--security-opt", "no-new-privileges:true",
                "--mount", f"type=bind,src={root}/certs,dst=/fixture,readonly",
                "--entrypoint", "python3", images["ops"], "/fixture/server.py"]).decode().strip()
            node["website"] = website
            website_state = json.loads(command(docker + ["inspect", website]))[0]
            node["website_identity"] = (website_state["Id"], website_state["State"]["StartedAt"])
            reality = {"server_name": TARGET, "target_host": TARGET, "target_port": 8446,
                       "private_key": PRIVATE_KEY, "public_key": PUBLIC_KEY, "short_id": "6ba85179e30d4fc2"}
            def entry(identifier, listener, port):
                return {"id": identifier, "core": "xray", "listener_id": listener,
                        "server": DOMAIN, "public_port": port, "address_families": ["ipv4"],
                        "name": listener, "uuid": "11111111-1111-4111-8111-111111111111"}
            spec = {
                "schema_version": 3,
                "release": {"version": "3.15.0", "manifest_sha256": "1" * 64,
                            "signature_identity": "local-test-only-not-release-verified"},
                "core": {"type": "xray", "secondary_type": None, "protocols": [
                    entry(1, "entry-vision", 443 if arguments.selected == "vision" else 35442) | {
                        "reality": reality},
                    entry(2, "entry-xhttp", 443 if arguments.selected == "xhttp" else 35442) | {
                        "reality": reality, "xhttp": {"path": "/cli-xhttp", "host": TARGET, "mode": "auto"}},
                    entry(21, "entry-website", 35443) | {"websocket": {
                        "domain": DOMAIN, "path": "cliws-test", "backend_port": 31297, "tls_port": 8443}}]},
                "tls": {"domain": DOMAIN}, "subscription": {"enabled": False, "token": "0" * 16},
                "site": {"mode": "default"},
                "images": images, "host_integrations": [], "accounts": [{
                    "id": ACCOUNT, "name": "local-cli-account", "enabled": True,
                    "uuid": ACCOUNT_UUID, "password": "Local.-~@+=:Secret",
                    "shadowsocks_password": None, "listeners": ["entry-vision", "entry-xhttp", "entry-website"]}],
            }
            save(root / "spec.json", spec)
            result = subprocess.run(ns + ["bash", str(ROOT / "docker/tests/control-deployment-node.sh"),
                                         str(root)], env=env, capture_output=True, timeout=180)
            if result.returncode:
                text = (root / "seed-private.log").read_text(errors="replace")
                raise AssertionError(shared.diagnostic(node, text).replace(PRIVATE_KEY, "[已隐藏]")[-8000:])
            release_fixture(node, images)
            acme = root / "deployment/data/acme"
            for relative in ("account.conf", f"{DOMAIN}_ecc/{DOMAIN}.conf"):
                path = acme / relative
                path.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
                path.write_text("# 本地回滚字节夹具，不代表真实 CA 账户或签发\n")
                path.chmod(0o600)
            command(ns + ["bash", "-ec", 'source "$1"; dockerAcmeRuntimePermissions "$2"', "--",
                          str(root / "deployment/bundle/install-docker.sh"), str(acme)], env=env)
            matrix(node, images, arguments.selected)
            print("reality-cli-environment-proof=" + json.dumps({
                "engine_id": info["ID"], "netns": os.readlink(f"/proc/{pid}/ns/net"),
                "scope": "isolated-linux-amd64-cli-transactions", "release_trust": "local-fixture",
                "target_metadata": "local-fixture", "public_reality_target": False,
                "selected": arguments.selected, "transparent_enabled": False}), flush=True)
        finally:
            failed = sys.exc_info()[0] is not None
            errors = []
            if node:
                try:
                    ids = command(node["docker"] + ["ps", "-aq"]).decode().split()
                    if ids:
                        command(node["docker"] + ["rm", "-f", *ids], timeout=45)
                except Exception as error:
                    errors.append("容器：" + type(error).__name__)
            if cron:
                cron.send_signal(signal.SIGCONT)
            for process in (cron, dns, daemon, holder):
                if process:
                    try:
                        stop(process)
                    except Exception as error:
                        errors.append("进程：" + type(error).__name__)
            if node:
                deadline = time.monotonic() + 5
                while Path(f"/proc/{node['pid']}/ns/net").exists() and time.monotonic() < deadline:
                    time.sleep(0.02)
                if Path(f"/proc/{node['pid']}/ns/net").exists():
                    errors.append("网络命名空间未清理")
            if errors:
                print("reality-cli-cleanup-failed:" + ",".join(errors), file=sys.stderr)
                if not failed:
                    raise AssertionError("隔离环境清理失败")
    print("docker-reality-stream-cli-real-ok", flush=True)


if __name__ == "__main__":
    main()
