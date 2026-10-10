#!/usr/bin/env python3
import copy
import hashlib
import http.client
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OPS = ROOT / "docker/images/ops"
ADDRESS, PEER_ADDRESS = "10.231.0.1", "10.231.0.2"
PORT = 39778
LOG_SECRET, FORGED_SOURCE = "ControlLogPrivacyMarker", "198.51.100.77"
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"


def namespace(pid):
    return ["nsenter", "--target", str(pid), "--net", "--"]


def run(arguments, pid=None, *, content=None, timeout=8):
    result = subprocess.run(
        (namespace(pid) if pid else []) + arguments,
        input=content, capture_output=True, timeout=timeout,
    )
    assert result.returncode == 0, (
        f"隔离工具执行失败：{arguments[0]}，退出码 {result.returncode}："
        + result.stderr.decode(errors="replace").strip()
    )
    return result.stdout


def stop(process):
    if process.poll() is None:
        process.terminate()
    try:
        process.communicate(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.communicate(timeout=3)


def identity(number):
    return f"{number:08d}-1111-4111-8111-{number:012d}"


def account(number):
    return {
        "id": identity(number), "name": f"账号{number}", "enabled": True,
        "uuid": identity(number + 100), "password": f"Password.-~@+=:{number:08d}",
        "shadowsocks_password": None,
    }


def save(path, value, *, api=False):
    candidate = path.with_suffix(".next")
    candidate.write_text(json.dumps(value, ensure_ascii=True), encoding="ascii")
    candidate.chmod(0o640 if api else 0o600)
    if api:
        os.chown(candidate, 0, 10001)
    candidate.replace(path)


def counters(pid):
    handshake = run(["wg", "show", "wg-padm", "latest-handshakes"], pid).split()
    transfer = run(["wg", "show", "wg-padm", "transfer"], pid).split()
    assert len(handshake) == 2 and int(handshake[1]) > 0, "真实 WireGuard 未完成握手"
    assert len(transfer) == 3, "真实 WireGuard Peer 数量不匹配"
    received, sent = map(int, transfer[1:])
    assert received > 0 and sent > 0, "真实 WireGuard 未双向传输"
    return {"latest_handshake": int(handshake[1]), "rx_bytes": received, "tx_bytes": sent}


def main():
    assert sys.platform == "linux" and os.getuid() == 0, "仅在隔离 Linux root 容器内运行"
    assert Path("/.dockerenv").is_file(), "不得直接操作宿主网络"
    original_links = {item["ifname"] for item in json.loads(run(["ip", "-j", "link", "show"]))}
    assert original_links == {"lo"}, "测试容器必须使用 network none，且不得复用现有接口"
    holders, server = [], None
    names = ["pc" + uuid.uuid4().hex[:10], "pp" + uuid.uuid4().hex[:10]]
    with tempfile.TemporaryDirectory(prefix=".tmp-control-two-node-", dir="/var/lib") as directory:
        work = Path(directory)
        work.chmod(0o750)
        os.chown(work, 0, 10001)
        api_log, client_log, sync_log = [work / name for name in ("api.log", "client.log", "sync.log")]
        for log in (api_log, client_log, sync_log):
            log.touch(mode=0o600)
        try:
            # 保留进程持有私有网络空间，避免 ip netns 的全局挂载和命名空间目录。
            original_namespace = os.readlink("/proc/self/ns/net")
            for _ in range(2):
                process = subprocess.Popen(
                    ["unshare", "--net", "--", sys.executable, "-c", "import time; time.sleep(3600)"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                )
                holders.append(process)
                for _ in range(200):
                    if process.poll() is not None:
                        raise AssertionError(
                            f"无法创建隔离网络空间，退出码 {process.returncode}："
                            + process.communicate()[1].decode(errors="replace").strip()
                        )
                    if os.readlink(f"/proc/{process.pid}/ns/net") != original_namespace:
                        break
                    time.sleep(0.01)
                else:
                    raise AssertionError("隔离网络空间创建超时")
            controller, controlled = [process.pid for process in holders]
            assert os.readlink(f"/proc/{controller}/ns/net") != os.readlink(f"/proc/{controlled}/ns/net")
            evidence = {
                "scope": "api-client-planning-only",
                "network_namespaces": {
                    "container": original_namespace,
                    "controller": os.readlink(f"/proc/{controller}/ns/net"),
                    "controlled": os.readlink(f"/proc/{controlled}/ns/net"),
                },
                "api": {"uid": 10001, "gid": 10001, "cap_eff": 0},
                "client": {"uid": 0, "cap_eff": 0},
            }
            run(["ip", "link", "add", names[0], "type", "veth", "peer", "name", names[1]])
            for name, pid in zip(names, (controller, controlled)):
                run(["ip", "link", "set", name, "netns", str(pid)])
                run(["ip", "link", "set", name, "name", "underlay"], pid)
                run(["ip", "link", "set", "lo", "up"], pid)
            keys, public = [], []
            for number in range(2):
                key = run(["wg", "genkey"])
                path = work / f"private-{number}"
                path.write_bytes(key)
                path.chmod(0o600)
                keys.append(path)
                public.append(run(["wg", "pubkey"], content=key).decode().strip())
            for index, pid in enumerate((controller, controlled)):
                address = (ADDRESS, PEER_ADDRESS)[index]
                peer_address = (PEER_ADDRESS, ADDRESS)[index]
                run(["ip", "address", "add", f"192.0.2.{index + 1}/30", "dev", "underlay"], pid)
                run(["ip", "link", "set", "underlay", "up"], pid)
                run(["ip", "link", "add", "wg-padm", "type", "wireguard"], pid)
                run(["wg", "set", "wg-padm", "private-key", str(keys[index]), "listen-port", "51820",
                     "peer", public[1 - index], "allowed-ips", f"{peer_address}/32",
                     "endpoint", f"192.0.2.{2 - index}:51820"], pid)
                run(["ip", "address", "add", f"{address}/32", "dev", "wg-padm"], pid)
                run(["ip", "link", "set", "wg-padm", "up"], pid)
                run(["ip", "route", "add", f"{peer_address}/32", "dev", "wg-padm"], pid)
                route = json.loads(run(["ip", "-j", "route", "get", peer_address], pid))[0]
                assert route["dev"] == "wg-padm" and route["prefsrc"] == address, "控制流量未走受管接口"

            token, rotated = "a" * 48, "b" * 48
            expires = int(time.time()) + 3600
            state = {
                "schema_version": 1, "role": "main", "node_id": identity(1), "revision": 7,
                "listen": {"interface": "wg-padm", "address": ADDRESS, "port": PORT},
                "peer": {"id": identity(2), "address": PEER_ADDRESS, "enabled": True,
                         "expires_at": expires, "token_sha256": hashlib.sha256(token.encode()).hexdigest()},
                "accounts": [account(4)],
            }
            invitation = {
                "format": "padm-docker-control-invite", "schema_version": 1,
                "controller_id": identity(1), "node_id": identity(2),
                "listen": state["listen"].copy(), "peer_address": PEER_ADDRESS,
                "token": token, "expires_at": expires,
            }
            local = dict(account(3), listeners=["entry-main"])
            spec = {
                "schema_version": 3,
                "core": {"protocols": [{"listener_id": "entry-main", "id": 1, "uuid": identity(9)}]},
                "accounts": [local],
            }
            state_path, spec_path, invite_path = [work / name for name in ("state.json", "spec.json", "invite.json")]
            save(state_path, state, api=True)
            save(spec_path, spec)
            save(invite_path, invitation)
            log_started = int(time.time())
            with api_log.open("ab") as output:
                server = subprocess.Popen(
                    namespace(controller) + [sys.executable, str(Path(__file__).resolve()),
                                             "--api", "--state", str(state_path)],
                    stdout=output, stderr=subprocess.STDOUT,
                )
            for _ in range(100):
                assert server.poll() is None, "实际控制 API 启动失败"
                health = subprocess.run(
                    namespace(controller) + [sys.executable, str(Path(__file__).resolve()),
                                             "--api", "--state", str(state_path), "--health"],
                    capture_output=True, timeout=4,
                )
                if health.returncode == 0:
                    assert not health.stdout and not health.stderr
                    break
                time.sleep(0.02)
            else:
                raise AssertionError("实际控制 API 未通过健康检查")
            status = Path(f"/proc/{server.pid}/status").read_text()
            for line in ("Uid:\t10001\t10001\t10001\t10001", "Gid:\t10001\t10001\t10001\t10001",
                         "CapEff:\t0000000000000000", "CapPrm:\t0000000000000000",
                         "CapInh:\t0000000000000000", "CapAmb:\t0000000000000000"):
                assert line in status, "实际 API 必须以 10001:10001 且无能力运行"

            run([sys.executable, str(Path(__file__).resolve()), "--log-probe"], controlled)

            def client(*, join=False, accepted=True):
                before = spec_path.read_bytes(), invite_path.read_bytes()
                arguments = ["setpriv", "--bounding-set=-all", "--inh-caps=-all",
                             "--ambient-caps=-all", "--", sys.executable,
                             str(Path(__file__).resolve()), "--client",
                             "--spec", str(spec_path), "--invite", str(invite_path)]
                if join:
                    arguments += ["--listener", "entry-main"]
                result = subprocess.run(namespace(controlled) + arguments, capture_output=True, timeout=7)
                with client_log.open("ab") as output:
                    output.write(result.stderr)
                assert before == (spec_path.read_bytes(), invite_path.read_bytes()), "客户端改写了规划输入"
                if not accepted:
                    assert result.returncode == 78 and not result.stdout, "异常同步未安全拒绝"
                    assert result.stderr == "被控接入或同步输入无效、授权失配或网络响应不支持\n".encode()
                    return None
                assert result.returncode == 0 and not result.stderr, "真实客户端规划失败"
                draft = json.loads(result.stdout)
                assert draft["accounts"][0] == local, "本机账号被同步覆盖"
                assert token not in result.stdout.decode() and rotated not in result.stdout.decode()
                return draft

            joined = client(join=True)
            assert joined["control_sync"]["last_revision"] == 7
            assert joined["control_sync"]["connection"] == {
                "listen": state["listen"], "peer_address": PEER_ADDRESS,
            }
            assert joined["accounts"][1] == dict(account(4), listeners=["entry-main"])
            initial_counters = [counters(pid) for pid in (controller, controlled)]
            # 仅把规划草稿作为下次输入；不冒充 Compose 应用、备份或双机服务健康验收。
            save(spec_path, joined)
            assert client() == joined, "同版本重试不是幂等规划"
            state.update(revision=8, accounts=[dict(account(4), enabled=False), account(5)])
            save(state_path, state, api=True)
            advanced = client()
            assert advanced["control_sync"]["last_revision"] == 8
            assert advanced["accounts"][1:] == [
                dict(source, listeners=["entry-main"]) for source in state["accounts"]
            ]
            save(spec_path, advanced)

            state["peer"]["token_sha256"] = hashlib.sha256(rotated.encode()).hexdigest()
            save(state_path, state, api=True)
            client(accepted=False)
            invitation["token"] = rotated
            save(invite_path, invitation)
            assert client() == advanced, "轮换邀请不能保留已有同步版本"
            state["peer"]["enabled"] = False
            save(state_path, state, api=True)
            client(accepted=False)
            state["peer"].update(enabled=True, expires_at=int(time.time()) - 1)
            save(state_path, state, api=True)
            client(accepted=False)
            state["peer"]["expires_at"] = expires
            save(state_path, state, api=True)
            invitation["expires_at"] = int(time.time()) - 1
            save(invite_path, invitation)
            client(accepted=False)
            invitation["expires_at"] = expires
            save(invite_path, invitation)

            expected_accounts = copy.deepcopy(state["accounts"])
            state["revision"] = 7
            save(state_path, state, api=True)
            client(accepted=False)
            state["revision"] = 8
            state["accounts"][0]["name"] = "同版本冲突"
            save(state_path, state, api=True)
            client(accepted=False)
            state["accounts"] = expected_accounts
            save(state_path, state, api=True)
            assert client() == advanced, "拒绝异常后不能恢复同版本重试"
            run(["ip", "link", "set", "underlay", "down"], controlled)
            started = time.monotonic()
            client(accepted=False)
            assert time.monotonic() - started < 6.5, "断网请求超出生产总时限"
            run(["ip", "link", "set", "underlay", "up"], controlled)
            state.update(revision=9, accounts=[account(5)])
            save(state_path, state, api=True)
            recovered = client()
            assert recovered["control_sync"]["last_revision"] == 9
            assert recovered["accounts"] == [local, dict(account(5), listeners=["entry-main"])]
            final_counters = []
            for before, pid in zip(initial_counters, (controller, controlled)):
                after = counters(pid)
                assert all(after[key] > before[key] for key in ("rx_bytes", "tx_bytes")), \
                    "恢复后控制流量未经过真实 WireGuard"
                final_counters.append(after)
            evidence["wireguard"] = dict(zip(("controller", "controlled"), final_counters))

            save(spec_path, recovered)
            desired_path = work / "desired.json"
            save(desired_path, {
                "ok": True, "api_version": 1, "controller_id": identity(1), "node_id": identity(2),
                "revision": state["revision"], "accounts": state["accounts"],
            })
            result = subprocess.run(
                namespace(controlled) + [sys.executable, str(OPS / "control_sync.py"),
                                         "--spec", str(spec_path), "--desired", str(desired_path)],
                capture_output=True, timeout=4,
            )
            sync_log.write_bytes(result.stderr)
            assert result.returncode == 0 and not result.stderr and json.loads(result.stdout) == recovered
            stop(server)
            server = None
            logs = b"".join(path.read_bytes() for path in (api_log, client_log, sync_log))
            secrets = [token, rotated, identity(9)] + [
                value for number in (3, 4, 5) for value in (account(number)["password"], account(number)["uuid"])
            ]
            secrets += [path.read_text().strip() for path in keys]
            secrets += [LOG_SECRET, FORGED_SOURCE]
            assert all(secret.encode() not in logs for secret in secrets), "三个生产 CLI 的日志泄露凭据"
            entries = []
            for line in api_log.read_text().splitlines():
                match = re.fullmatch(
                    r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z) control-request "
                    r"status=([1-5]\d{2}|connection_closed) source=(10\.231\.0\.[12]) "
                    rf"target={re.escape(ADDRESS)} port={PORT}", line,
                )
                assert match, "真实控制日志格式或 socket 来源不匹配"
                timestamp = datetime.strptime(match[1], "%Y-%m-%dT%H:%M:%S.%fZ").replace(tzinfo=timezone.utc)
                assert log_started <= timestamp.timestamp() <= time.time(), "控制日志时间不是本次 UTC 时间"
                entries.append((match[2], match[3]))
            assert {("200", PEER_ADDRESS), ("401", PEER_ADDRESS), ("401", ADDRESS)} <= set(entries), \
                "控制日志缺少真实 Peer 或本机健康来源"
            evidence["source_logs"] = {
                "target": ADDRESS, "port": PORT, "sources": sorted({source for _, source in entries}),
                "forwarded_headers_ignored": True, "secrets_absent": True, "utc": True,
            }
        finally:
            if server is not None:
                stop(server)
            for process in holders:
                if process.poll() is None:
                    for interface in ("wg-padm", "underlay"):
                        subprocess.run(namespace(process.pid) + ["ip", "link", "delete", interface],
                                       capture_output=True, timeout=3)
                stop(process)
            for name in names:
                subprocess.run(["ip", "link", "delete", name], capture_output=True, timeout=3)
            current_links = {item["ifname"] for item in json.loads(run(["ip", "-j", "link", "show"]))}
            assert current_links == original_links, "隔离验收留下了网络接口"
    assert not work.exists(), "隔离验收留下了私钥或授权文件"
    print("docker-control-two-node-real-proof=" + json.dumps(evidence, sort_keys=True))
    print("docker-control-two-node-real-regression-ok")


if __name__ == "__main__":
    if sys.argv[1:2] == ["--api"]:
        # 先进入指定网络空间，再降权并 exec 未修改的生产入口。
        os.setgroups([])
        os.setgid(10001)
        os.setuid(10001)
        os.execv(sys.executable, [sys.executable, str(OPS / "control_api.py"), *sys.argv[2:]])
    if sys.argv[1:2] == ["--client"]:
        status = Path("/proc/self/status").read_text()
        assert os.getuid() == 0
        for capability in ("CapEff", "CapPrm", "CapInh", "CapAmb", "CapBnd"):
            assert f"{capability}:\t0000000000000000" in status, "实际客户端必须无能力运行"
        os.execv(sys.executable, [sys.executable, str(OPS / "control_client.py"), *sys.argv[2:]])
    if sys.argv[1:2] == ["--log-probe"]:
        connection = http.client.HTTPConnection(ADDRESS, PORT, timeout=4)
        try:
            connection.request("GET", f"/v1/health?{LOG_SECRET}", headers={
                "Authorization": f"Bearer {LOG_SECRET}", "X-Padm-Control-Version": "1",
                "Forwarded": f"for={FORGED_SOURCE}", "X-Forwarded-For": FORGED_SOURCE,
                "X-Real-IP": FORGED_SOURCE, "X-Private": LOG_SECRET,
            })
            with connection.getresponse() as response:
                assert response.status == 401
                assert response.read() == b'{"ok":false,"error":"unauthorized"}'
        finally:
            connection.close()
        sys.exit(0)
    main()
