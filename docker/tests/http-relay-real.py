import base64
import contextlib
import importlib.util
import json
from pathlib import Path
import socket
import subprocess
import sys
import threading


module_spec = importlib.util.spec_from_file_location(
    "routing_fixture", Path(__file__).with_name("routing-socks5-real.py"))
fixture = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(fixture)
BODY = b"routing-destination-ok"
RESPONSE = (b"HTTP/1.1 200 OK\r\nContent-Length: " + str(len(BODY)).encode() +
            b"\r\nConnection: close\r\n\r\n" + BODY)
USER, PASSWORD = "11111111-1111-4111-8111-111111111111", "relay:password"
TAG, DIRECT = "padm-relay-http", "padm-relay-http-direct"


def headers(stream):
    data = b""
    while not data.endswith(b"\r\n\r\n"):
        data += fixture.exact(stream, 1)
        assert len(data) <= 16384, "HTTP 响应头超限"
    return data


def http(host, source, listener, destination, method, password=PASSWORD, dest_name=None):
    target_host = dest_name or host
    address = (f"[{target_host}]:{destination}" if ":" in target_host
               else f"{target_host}:{destination}")
    authorization = (b"Proxy-Authorization: Basic " +
                     base64.b64encode(f"{USER}:{password}".encode()) + b"\r\n"
                     if password is not None else b"")
    with socket.create_connection((host, listener), timeout=1,
                                  source_address=(source, 0)) as stream:
        target = address if method == "CONNECT" else f"http://{address}/routing-check"
        stream.sendall(method.encode() + b" " + target.encode() + b" HTTP/1.1\r\nHost: " +
                       address.encode() + b"\r\n" + authorization + b"Connection: close\r\n\r\n")
        try:
            header = headers(stream)
            status = int(header.split(b" ", 2)[1])
            if status != 200:
                # 核心明确失败响应或 EOF 才算拒绝，客户端超时会直接失败。
                assert 400 <= status <= 599, header
                return status
            if method == "CONNECT":
                stream.sendall(b"GET /routing-check HTTP/1.1\r\nHost: fixture\r\nConnection: close\r\n\r\n")
                assert fixture.exact(stream, len(RESPONSE)) == RESPONSE
            else:
                assert b"content-length: 22\r\n" in header.lower()
                assert fixture.exact(stream, len(BODY)) == BODY
            return status
        except (EOFError, ConnectionResetError, BrokenPipeError):
            return 0


def runtime(root):
    config = json.loads((root / "xray.json").read_text())
    relay = [item for item in config["inbounds"] if item["tag"] == TAG]
    assert len(relay) == 1
    local, other = fixture.port("127.0.0.1"), fixture.port("127.0.0.1")
    while local == other:
        other = fixture.port("127.0.0.1")
    assert relay[0]["protocol"] == "http"
    assert relay[0]["settings"]["accounts"] == [dict(user=USER, **{"pass": PASSWORD})]
    assert relay[0]["settings"]["userLevel"] == 1
    assert config["policy"]["levels"]["1"]["statsUserUplink"] is False
    assert config["policy"]["levels"]["1"]["statsUserDownlink"] is False
    assert config["policy"]["levels"]["0"]["statsUserUplink"] is True
    assert config["policy"]["levels"]["0"]["statsUserDownlink"] is True
    assert any(user.get("email") == USER for inbound in config["inbounds"]
               for user in inbound.get("settings", {}).get("clients", []))
    relay[0]["port"] = local
    config["log"]["loglevel"] = "debug"
    config["inbounds"].append(dict(protocol="http", tag="fixture-account-control",
                                 listen="::", port=other,
                                 settings=dict(userLevel=0, accounts=[
                                     dict(user=USER, **{"pass": PASSWORD})])))
    rules = config["routing"]["rules"]
    relay_rules = [rule for rule in rules if TAG in rule.get("inboundTag", [])]
    assert len(relay_rules) == 2 and relay_rules[0]["outboundTag"] == DIRECT
    assert relay_rules[1]["outboundTag"] != DIRECT
    last = rules.index(relay_rules[-1]) + 1
    rules[last:last] = [dict(type="field", ip=["127.0.0.0/8", "::1/128"],
                            outboundTag=DIRECT)]
    return config, local, other


def counters():
    result = subprocess.run(["/routing-cores/xray", "api", "statsquery",
                             "--server=127.0.0.1:10085", "-pattern", "user"],
                            capture_output=True, text=True, check=True)
    value = json.loads(result.stdout)
    return {row["name"]: int(row.get("value", 0))
            for row in value.get("stat", [])
            if row["name"].startswith(f"user>>>{USER}>>>traffic>>>")}


def main(root):
    assert sys.platform == "linux" and Path("/.dockerenv").is_file()
    root.chmod(0o755)
    with contextlib.ExitStack() as stack:
        # 只修改本轮隔离容器 hosts；关闭所有核心后恢复原始字节。
        hosts = Path("/etc/hosts")
        original_hosts = hosts.read_bytes()
        stack.callback(hosts.write_bytes, original_hosts)
        hosts.write_bytes(original_hosts + b"\n127.0.0.1 relay.padm.invalid\n")
        origins = {}
        for host in ("127.0.0.1", "::1"):
            server = stack.enter_context(fixture.Server((host, 0), fixture.Destination))
            server.accepted, server.received = 0, []
            origins[host] = server
            thread = threading.Thread(target=server.serve_forever,
                                      kwargs=dict(poll_interval=0.02), daemon=True)
            thread.start()
            stack.callback(thread.join, 1)
            stack.callback(server.shutdown)
        for core in ("xray",):
            config, local, other = runtime(root)
            path = root / f"{core}.runtime.json"
            fixture.write_config(path, config)
            with fixture.running([f"/routing-cores/{core}", "run", "-c"], path,
                                 "127.0.0.1", local, root / f"{core}.log") as process:
                before_counters = counters()
                for method in ("GET", "CONNECT"):
                    for host in ("127.0.0.1", "::1"):
                        origin = origins[host]
                        before = origin.accepted
                        assert http(host, host, local, origin.server_address[1], method) == 200
                        assert origin.accepted == before + 1
                    origin = origins["127.0.0.1"]
                    before = origin.accepted
                    assert http("127.0.0.1", "127.0.0.2", local,
                                origin.server_address[1], method) != 200
                    assert origin.accepted == before, "拒绝来源到达目的端"
                    assert http("127.0.0.1", "127.0.0.1", local,
                                origin.server_address[1], method, "wrong-password") != 200
                    assert origin.accepted == before, "错误认证到达目的端"
                    assert http("127.0.0.1", "127.0.0.1", local,
                                origin.server_address[1], method, None) != 200
                    assert origin.accepted == before, "无认证到达目的端"
                    assert http("127.0.0.1", "127.0.0.1", local,
                                origin.server_address[1], method,
                                dest_name="relay.padm.invalid") == 200
                    assert origin.accepted == before + 1, "relay 沿用了全局 hosts/DNS"
                    before = origin.accepted
                    assert http("127.0.0.1", "127.0.0.2", local,
                                origin.server_address[1], method,
                                dest_name="relay.padm.invalid") != 200
                    assert origin.accepted == before, "拒绝来源域名请求到达目的端"
                assert counters() == before_counters, "同名 relay 流量计入了业务账号"
                # 同名等级 0 入站是业务统计控制对照，等级 1 relay 不参与该账号统计。
                for host, source in (("127.0.0.1", "127.0.0.2"), ("::1", "::1")):
                    origin = origins[host]
                    before = origin.accepted
                    assert http(host, source, other, origin.server_address[1], "GET") == 200
                    assert origin.accepted == before + 1
                assert process.poll() is None
                after_counters = counters()
                assert sum(after_counters.values()) > sum(before_counters.values()), (
                    "业务等级 0 同名账号没有实际统计", after_counters)
                for method in ("GET", "CONNECT"):
                    for host in ("127.0.0.1", "::1"):
                        origin = origins[host]
                        before = origin.accepted
                        assert http(host, host, local, origin.server_address[1], method) == 200
                        assert origin.accepted == before + 1
                assert counters() == after_counters, "已有同名账号计数器被 relay 改变"
            print(f"http-relay-real-{core}: HTTP/CONNECT/auth/source/direct/isolated-DNS/account-control passed",
                  flush=True)


if __name__ == "__main__":
    main(Path(sys.argv[1]))
