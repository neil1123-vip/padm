#!/usr/bin/env python3
"""正式 TLS URI 的显式 Xray 配置转换；不代表客户端原生 URI 导入。"""
import base64
import json
import re
import sys
import urllib.parse
import uuid


def unique(pairs):
    result = {}
    for key, value in pairs:
        assert key not in result, "重复字段"
        result[key] = value
    return result


def text(value):
    assert isinstance(value, str) and value and not any(ord(c) < 33 for c in value)
    return value


def port(value):
    assert not isinstance(value, bool) and str(value).isascii() and str(value).isdigit()
    result = int(value)
    assert 0 < result <= 65535
    return result


def xray_client(uri, local):
    assert isinstance(uri, str) and not any(c.isspace() for c in uri)
    local = port(local)
    if uri.startswith("vmess://"):
        raw = base64.b64decode(uri[8:], validate=True)
        value = json.loads(raw, object_pairs_hook=unique)
        assert set(value) == {
            "v", "ps", "add", "port", "id", "aid", "scy", "net", "type",
            "host", "path", "tls", "sni"}
        assert value["v"] == "2" and value["aid"] == "0" and value["scy"] == "auto"
        assert value["type"] == "none" and value["tls"] == "tls"
        assert value["net"] in ("ws", "httpupgrade")
        text(value["ps"])
        protocol, address, remote = "vmess", text(value["add"]), port(value["port"])
        identity = text(value["id"])
        network, sni = value["net"], text(value["sni"])
        host, path = text(value["host"]), text(value["path"])
        assert path.startswith("/") and host == sni
        user = {"id": identity, "alterId": 0, "security": "auto"}
        tls = {"serverName": sni, "allowInsecure": False}
    else:
        parsed = urllib.parse.urlsplit(uri)
        assert parsed.scheme in ("vless", "trojan")
        assert parsed.username and parsed.password is None and not parsed.path
        assert parsed.hostname and parsed.port and parsed.fragment
        assert not re.search(r"%(?![0-9a-fA-F]{2})", uri)
        protocol, address, remote = parsed.scheme, text(parsed.hostname), port(parsed.port)
        identity = text(urllib.parse.unquote(parsed.username, errors="strict"))
        query = unique(urllib.parse.parse_qsl(
            parsed.query, keep_blank_values=True, strict_parsing=True, errors="strict"))
        assert all(text(key) and text(value) for key, value in query.items())
        network, sni = query["type"], text(query["sni"])
        assert network in ("ws", "grpc", "tcp")
        expected = {"type", "sni"}
        if protocol == "vless":
            expected |= {"security", "encryption"}
            assert query["security"] == "tls" and query["encryption"] == "none"
            user = {"id": identity, "encryption": "none"}
        else:
            expected |= {"peer", "fp"}
            assert query["peer"] == sni and query["fp"] == "chrome"
            assert network in ("grpc", "tcp")
            if network == "tcp":
                expected.add("security")
                assert query["security"] == "tls"
            user = {"password": identity}
        tls = {"serverName": sni, "allowInsecure": False}
        if "fp" in query:
            tls["fingerprint"] = query["fp"]
        if network == "ws":
            expected |= {"host", "path"}
            host, path = text(query["host"]), text(query["path"])
            assert protocol == "vless" and host == sni and path.startswith("/")
        elif network == "grpc":
            expected |= {"alpn", "serviceName"}
            assert query["alpn"] == "h2"
            service = text(query["serviceName"])
            tls["alpn"] = ["h2"]
        else:
            expected |= {"fp", "alpn"}
            assert query["fp"] == "chrome"
            tls["fingerprint"] = query["fp"]
            assert query["alpn"] in ("h2,http/1.1", "http/1.1,h2", "http/1.1")
            tls["alpn"] = query["alpn"].split(",")
            if protocol == "vless":
                expected.add("flow")
                assert query["flow"] == "xtls-rprx-vision"
                user["flow"] = query["flow"]
        assert set(query) == expected, "非正式 TLS 模板参数"
    if protocol != "trojan":
        assert str(uuid.UUID(identity)) == identity
    stream = {"network": network, "security": "tls", "tlsSettings": tls}
    if network == "ws":
        stream["wsSettings"] = {"path": path, "headers": {"Host": host}}
    elif network == "httpupgrade":
        stream["httpupgradeSettings"] = {"path": path, "host": host}
    elif network == "grpc":
        stream["grpcSettings"] = {"serviceName": service}
    settings = ({"servers": [{"address": address, "port": remote, **user}]}
                if protocol == "trojan" else
                {"vnext": [{"address": address, "port": remote, "users": [user]}]})
    return {
        "log": {"loglevel": "debug"},
        "inbounds": [{"listen": "127.0.0.1", "port": local, "protocol": "socks",
                      "settings": {"auth": "noauth", "udp": False}}],
        "outbounds": [{"protocol": protocol, "settings": settings, "streamSettings": stream}],
    }


def selfcheck():
    identity, domain = "11111111-1111-4111-8111-111111111111", "TLS.padm.test"
    base = {"v": "2", "ps": "entry", "add": "127.0.0.1", "port": "2450", "id": identity,
            "aid": "0", "scy": "auto", "net": "ws", "type": "none", "host": domain,
            "path": "/中文/path?x=1", "tls": "tls", "sni": domain}
    def vmess(value):
        return "vmess://" + base64.b64encode(
            json.dumps(value, ensure_ascii=False).encode()).decode()
    def uri(protocol, query, secret=identity):
        return (protocol + "://" + urllib.parse.quote(secret, safe="") +
                "@[::1]:2450?" + urllib.parse.urlencode(query) + "#entry")
    vless = {"encryption": "none", "security": "tls", "sni": domain}
    trojan = {"peer": domain, "fp": "chrome", "sni": domain}
    rows = [
        (vmess(base), "vmess", "ws"),
        (vmess(dict(base, net="httpupgrade")), "vmess", "httpupgrade"),
        (uri("vless", vless | {"type": "ws", "host": domain, "path": base["path"]}), "vless", "ws"),
        (uri("vless", vless | {"type": "grpc", "alpn": "h2", "serviceName": "subscriptions"}), "vless", "grpc"),
        (uri("trojan", trojan | {"type": "grpc", "alpn": "h2", "serviceName": "native_tls_25"}, "A+B:@%中文"), "trojan", "grpc"),
        (uri("vless", vless | {"type": "tcp", "fp": "chrome", "alpn": "http/1.1,h2",
                             "flow": "xtls-rprx-vision"}), "vless", "tcp"),
        (uri("trojan", trojan | {"type": "tcp", "security": "tls", "alpn": "h2,http/1.1"}), "trojan", "tcp"),
    ]
    for source, protocol, network in rows:
        result = xray_client(source, 2080)
        assert len(result["inbounds"]) == len(result["outbounds"]) == 1
        assert result["inbounds"][0] == {
            "listen": "127.0.0.1", "port": 2080, "protocol": "socks",
            "settings": {"auth": "noauth", "udp": False}}
        outbound = result["outbounds"][0]
        assert outbound["protocol"] == protocol
        stream = outbound["streamSettings"]
        assert stream["network"] == network and stream["security"] == "tls"
        assert stream["tlsSettings"]["serverName"] == domain
        assert stream["tlsSettings"]["allowInsecure"] is False
        if network in ("ws", "httpupgrade"):
            assert stream[network + "Settings"]["path"] == base["path"]
        if protocol == "trojan" and network == "grpc":
            assert outbound["settings"]["servers"][0]["password"] == "A+B:@%中文"
            assert stream["grpcSettings"]["serviceName"] == "native_tls_25"
        if protocol == "vless" and network == "tcp":
            assert outbound["settings"]["vnext"][0]["users"][0]["flow"] == "xtls-rprx-vision"
            assert stream["tlsSettings"]["alpn"] == ["http/1.1", "h2"]
    duplicate_json = json.dumps(base)[:-1] + ',"tls":"tls"}'
    bad = [
        vmess(dict(base, insecure=True)), vmess(dict(base, tls="none")),
        vmess(dict(base, net="tcp")), vmess(dict(base, aid="1")),
        "vmess://" + base64.b64encode(duplicate_json.encode()).decode(),
        rows[2][0].replace("security=tls", "security=reality"),
        rows[2][0].replace("type=ws", "type=xhttp"),
        rows[2][0].replace("#entry", "&sni=duplicate#entry"),
        rows[2][0].replace("#entry", "&insecure=1#entry"),
        rows[3][0].replace("alpn=h2", "alpn=h3"),
        rows[4][0].replace("peer=TLS.padm.test", "peer=wrong.test"),
        rows[5][0].replace("flow=xtls-rprx-vision", "flow=none"),
        rows[6][0].replace("security=tls", "security=none"),
        rows[2][0].replace("sni=TLS", "sni=%ZZTLS"),
    ]
    for source in bad:
        try:
            xray_client(source, 2080)
        except (AssertionError, ValueError, KeyError, TypeError):
            pass
        else:
            raise AssertionError("非法 TLS URI 未拒绝")
    print(json.dumps({"tls_uri_xray_selfcheck": "pass", "templates": len(rows),
                      "rejections": len(bad), "uri_native_import": False}))


if __name__ == "__main__":
    assert sys.argv[1:] == ["--selfcheck"]
    selfcheck()
