#!/usr/bin/env python3
"""固定 acme.sh 3.1.6 单域名 ECC 状态的纯数据重建与材料校验。"""

import argparse
import base64
import datetime
import hashlib
import json
import math
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlsplit


TRUSTED_PATH = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
WEBROOT = "/var/lib/padm/acme-webroot"
VALIDATIONS = ("standalone-http01", "webroot-http01", "tls-alpn01", "dns-01")
DNS_FIELDS = {"ACMEDNS_USERNAME", "ACMEDNS_PASSWORD", "ACMEDNS_SUBDOMAIN", "ACMEDNS_BASE_URL"}
MAX_CONFIG = 64 * 1024
MAX_FILE = 1024 * 1024
P256_SPKI = bytes.fromhex("3059301306072a8648ce3d020106082a8648ce3d03010703420004")
HOOKS = ("Le_PreHook", "Le_PostHook", "Le_RenewHook", "Le_ReloadCmd", "Le_DeployHook")
TIMES = ("Le_CertCreateTime", "Le_NextRenewTime", "Le_InstallCertSuccessTime")
LINKS = ("Le_OrderFinalize", "Le_LinkOrder", "Le_LinkCert")
OUTPUTS = ("Le_RealCertPath", "Le_RealCACertPath", "Le_RealKeyPath", "Le_RealFullChainPath")
DOMAIN_REQUIRED = {"Le_Domain", "Le_Alt", "Le_Webroot", "Le_API", "Le_Keylength"}
DOMAIN_FIELDS = DOMAIN_REQUIRED | {"Le_HTTPPort", "Le_TLSPort", "Le_DNSSleep"} | DNS_FIELDS | set(HOOKS + TIMES + LINKS + OUTPUTS) | {
    field + "Str" for field in TIMES
}


def require(condition):
    if not condition:
        raise ValueError("ACME 恢复输入或材料校验失败")


def read_json(data):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result)
            result[key] = value
        return result

    def constant(_value):
        raise ValueError("ACME 账户 JSON 不接受非有限数值")

    require(isinstance(data, bytes) and 0 < len(data) <= MAX_CONFIG)
    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=unique, parse_constant=constant)
    except (UnicodeError, RecursionError) as error:
        raise ValueError("ACME 账户 JSON 校验失败") from error
    budget = [4096]

    def bounded(item, depth=0):
        budget[0] -= 1
        require(depth <= 24 and budget[0] >= 0)
        if isinstance(item, dict):
            require(all(isinstance(key, str) and len(key) <= 256 for key in item))
            for child in item.values():
                bounded(child, depth + 1)
        elif isinstance(item, list):
            for child in item:
                bounded(child, depth + 1)
        elif isinstance(item, str):
            require(len(item) <= 4096 and "\0" not in item)
        else:
            require(item is None or type(item) in (bool, int, float))
            require(type(item) is not float or math.isfinite(item))

    bounded(value)
    return value


def assignments(data, fields, required=()):
    require(isinstance(data, bytes) and 0 < len(data) <= MAX_CONFIG)
    try:
        text = data.decode("ascii")
    except UnicodeError as error:
        raise ValueError("ACME 配置必须为规范 ASCII 赋值") from error
    require("\r" not in text and "\0" not in text)
    result = {}
    for line in text.removesuffix("\n").split("\n"):
        match = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*)='([^']*)'", line)
        require(match is not None)
        key, value = match.groups()
        require(key in fields and key not in result and len(value) <= 2048)
        require(not any(char in value for char in "\\$`;|&<>()")
                and all(32 <= ord(char) < 127 for char in value))
        result[key] = value
    require(set(required) <= set(result))
    return result


def encoded(values):
    return "".join("{}='{}'\n".format(key, value) for key, value in values.items()).encode("ascii")


def checked_domain(domain):
    require(isinstance(domain, str) and len(domain) <= 253 and "." in domain
            and all(re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", label)
                    for label in domain.split(".")))
    require(not re.fullmatch(r"[0-9.]+", domain))
    return domain


def checked_url(value, origin=None):
    require(isinstance(value, str) and len(value) <= 2048)
    try:
        parsed = urlsplit(value)
        port = parsed.port
    except ValueError as error:
        raise ValueError("ACME URL 校验失败") from error
    require(parsed.scheme == "https" and parsed.hostname and parsed.username is None
            and parsed.password is None and not parsed.query and not parsed.fragment
            and re.fullmatch(r"[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?", parsed.hostname)
            and all(label and len(label) <= 63 and not label.startswith("-")
                    and not label.endswith("-") for label in parsed.hostname.split(".")))
    authority = parsed.hostname + (":" + str(port) if port is not None else "")
    require(value == "https://" + authority + parsed.path and (port is None or 0 < port <= 65535)
            and re.fullmatch(r"/[A-Za-z0-9._~/-]*", parsed.path)
            and "//" not in parsed.path and
            all(part not in (".", "..") for part in parsed.path.split("/")))
    observed = (parsed.hostname, port or 443)
    require(origin is None or observed == origin)
    return parsed, observed


def ca_directory(api):
    parsed, origin = checked_url(api)
    # 与固定客户端一致，CA 目录不包含 URL 端口。
    return "ca/" + parsed.hostname + parsed.path.rstrip("/"), origin


def dns_credentials(data):
    """仅恢复固定 dns_acmedns 插件的预登记凭据，不触发交互注册。"""
    require(isinstance(data, bytes) and 0 < len(data) <= MAX_CONFIG)
    try:
        text = data.decode("ascii")
    except UnicodeError as error:
        raise ValueError("ACME DNS 凭据校验失败") from error
    values = {}
    for line in text.split("\n"):
        line = line.removesuffix("\r")
        if not line or line.startswith("#"):
            continue
        name, separator, value = line.partition("=")
        require(separator and name in DNS_FIELDS and name not in values)
        values[name] = value
    require(set(values) == DNS_FIELDS)
    for field in ("ACMEDNS_USERNAME", "ACMEDNS_PASSWORD"):
        require(re.fullmatch(r"[A-Za-z0-9_-]{1,256}", values[field]))
    require(re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?",
                         values["ACMEDNS_SUBDOMAIN"]))
    url = values["ACMEDNS_BASE_URL"]
    require(not url.endswith("/"))
    checked_url(url if urlsplit(url).path else url + "/")
    return values


def jwk_public(value):
    require(isinstance(value, dict) and set(value) == {"kty", "crv", "x", "y"}
            and value["kty"] == "EC" and value["crv"] == "P-256")
    coordinates = []
    for field in ("x", "y"):
        part = value[field]
        require(isinstance(part, str) and re.fullmatch(r"[A-Za-z0-9_-]{43}", part))
        decoded = base64.urlsafe_b64decode(part + "=")
        require(len(decoded) == 32 and
                base64.urlsafe_b64encode(decoded).decode().rstrip("=") == part)
        coordinates.append(decoded)
    return P256_SPKI + b"".join(coordinates)


def account_metadata(data, email, account_url, origin):
    account = read_json(data)
    require(isinstance(account, dict) and account)
    require("status" not in account or account["status"] == "valid")
    if "contact" in account:
        require(account["contact"] == ["mailto:" + email])
    if "orders" in account:
        checked_url(account["orders"], origin)
    if "url" in account:
        require(account["url"] == account_url)
    for field in ("externalAccountBinding", "eab", "eab_kid", "eab_hmac_key"):
        require(field not in account or account[field] in (None, "", {}))
    public = []

    def inspect(item):
        if isinstance(item, dict):
            if "kty" in item or "crv" in item:
                public.append(jwk_public(item))
            for key, child in item.items():
                if key in ("key", "jwk"):
                    public.append(jwk_public(child))
                else:
                    inspect(child)
        elif isinstance(item, list):
            for child in item:
                inspect(child)

    inspect(account)
    require(not public or all(item == public[0] for item in public))
    return public[0] if public else None


def normalize_acme_home(files, domain, email=None, validation=None, credentials=None):
    """返回规范文件和非秘密摘要；路径、权限和清单信任由恢复入口负责。"""
    checked_domain(domain)
    require(isinstance(files, dict) and len(files) <= 20)
    require(all(isinstance(path, str) and isinstance(data, bytes) and len(data) <= MAX_FILE
                for path, data in files.items()))
    directory = domain + "_ecc"
    domain_path = directory + "/" + domain + ".conf"
    require("account.conf" in files and domain_path in files)
    account = assignments(files["account.conf"],
                          {"USER_PATH", "CA_BUNDLE", "DEFAULT_ACME_SERVER"}, {"USER_PATH"})
    require(account["USER_PATH"] == TRUSTED_PATH and not account.get("CA_BUNDLE"))
    config = assignments(files[domain_path], DOMAIN_FIELDS, DOMAIN_REQUIRED)
    require(config["Le_Domain"] == domain and config["Le_Alt"] == "no"
            and config["Le_Keylength"] == "ec-256"
            and all(not config.get(field) for field in HOOKS))
    dns = config["Le_Webroot"] == "dns_acmedns"
    require(dns or (credentials is None and not (set(config) & (DNS_FIELDS | {"Le_DNSSleep"}))))
    if config["Le_Webroot"] == "no":
        require(config.get("Le_HTTPPort") == "8080" and "Le_TLSPort" not in config)
        observed_validation = "standalone-http01"
    elif config["Le_Webroot"] == "alpn":
        require(config.get("Le_TLSPort") == "8443" and "Le_HTTPPort" not in config)
        observed_validation = "tls-alpn01"
    elif dns:
        require("Le_HTTPPort" not in config and "Le_TLSPort" not in config
                and {field: config.get(field) for field in DNS_FIELDS} == dns_credentials(credentials))
        sleep = config.get("Le_DNSSleep", "")
        require(sleep == "" or (re.fullmatch(r"[1-9][0-9]{0,3}", sleep) and int(sleep) <= 3600))
        observed_validation = "dns-01"
    else:
        # 固定客户端仅在自监听方式保存端口，webroot 不接受残留或自定义端口。
        require(config["Le_Webroot"] == WEBROOT
                and "Le_HTTPPort" not in config and "Le_TLSPort" not in config)
        observed_validation = "webroot-http01"
    require(validation is None or validation == observed_validation)
    ca, origin = ca_directory(config["Le_API"])
    # 上游默认 CA 仅接受当前域名已验证的同目录和来源，重建时不保留全局选择。
    if "DEFAULT_ACME_SERVER" in account:
        require(ca_directory(account["DEFAULT_ACME_SERVER"]) == (ca, origin))
    required = {"account.conf", domain_path, ca + "/account.key", ca + "/account.json",
                ca + "/ca.conf", directory + "/" + domain + ".key",
                directory + "/" + domain + ".cer", directory + "/ca.cer",
                directory + "/fullchain.cer"}
    discarded = {"http.header", directory + "/" + domain + ".csr",
                 directory + "/" + domain + ".csr.conf", directory + "/backup/"}
    require(required <= set(files) and set(files) <= required | discarded)
    require(directory + "/backup/" not in files or files[directory + "/backup/"] == b"")
    ca_config = assignments(files[ca + "/ca.conf"], {"CA_EMAIL", "ACCOUNT_URL", "CA_KEY_HASH"},
                            {"ACCOUNT_URL", "CA_KEY_HASH"})
    # 上游账户可省略邮箱，只能由调用方提供的受管续期登记补全。
    address = ca_config.get("CA_EMAIL", email)
    require(isinstance(address, str)
            and re.fullmatch(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}", address)
            and (email is None or email == address))
    ca_config["CA_EMAIL"] = address
    checked_url(ca_config["ACCOUNT_URL"], origin)
    require(ca_config["CA_KEY_HASH"] ==
            base64.b64encode(hashlib.sha256(files[ca + "/account.key"]).digest()).decode())
    account_metadata(files[ca + "/account.json"], address, ca_config["ACCOUNT_URL"], origin)
    for field in LINKS:
        if field in config:
            checked_url(config[field], origin)
    for field in TIMES:
        if field in config:
            require(re.fullmatch(r"[0-9]{1,12}", config[field]))
        if field + "Str" in config:
            require(field in config)
            try:
                timestamp = datetime.datetime.strptime(
                    config[field + "Str"], "%Y-%m-%dT%H:%M:%SZ").replace(
                        tzinfo=datetime.timezone.utc).timestamp()
            except ValueError as error:
                raise ValueError("ACME 时间校验失败") from error
            require(timestamp == int(config[field]))
    outputs = dict(zip(OUTPUTS, ("", "", "/var/lib/padm/tls-output/" + domain + ".key",
                                 "/var/lib/padm/tls-output/" + domain + ".crt")))
    require(all(config.get(field, "") in ("", value) for field, value in outputs.items()))
    normalized = {path: files[path] for path in sorted(required)}
    normalized["account.conf"] = encoded({"USER_PATH": TRUSTED_PATH, "CA_BUNDLE": ""})
    config.update(outputs)
    normalized[domain_path] = encoded({key: config[key] for key in sorted(config)})
    normalized[ca + "/ca.conf"] = encoded(ca_config)
    return normalized, {"acme_version": "3.1.6", "validation": observed_validation,
                        "key_type": "EC-P256", "normalized_files": len(normalized),
                        "discarded_files": len(set(files) - required)}


def openssl_run(openssl, arguments, data=None):
    require(isinstance(openssl, str) and openssl)
    try:
        result = subprocess.run([openssl, *arguments], input=data, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=15, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ValueError("ACME OpenSSL 材料检查不可用") from error
    require(result.returncode == 0)
    return result.stdout


def private_public(openssl, key):
    require(isinstance(key, bytes) and 0 < len(key) <= MAX_FILE)
    require(re.fullmatch(
        rb"-----BEGIN (EC PRIVATE KEY|PRIVATE KEY)-----\r?\n"
        rb"[A-Za-z0-9+/=\r\n]+-----END \1-----[ \t\r\n]*", key) is not None)
    openssl_run(openssl, ["pkey", "-check", "-noout", "-passin", "pass:"], key)
    public = openssl_run(openssl, ["pkey", "-pubout", "-outform", "DER", "-passin", "pass:"], key)
    require(public.startswith(P256_SPKI) and len(public) == len(P256_SPKI) + 64)
    return public


def certificates(openssl, data):
    require(isinstance(data, bytes) and 0 < len(data) <= MAX_FILE)
    pattern = rb"-----BEGIN CERTIFICATE-----\r?\n[A-Za-z0-9+/=\r\n]+-----END CERTIFICATE-----"
    blocks = re.findall(pattern, data)
    require(0 < len(blocks) <= 8 and not re.sub(pattern, b"", data).strip())
    return [(block + b"\n", openssl_run(openssl, ["x509", "-outform", "DER"], block))
            for block in blocks]


def verify_materials(files, domain, tls_key, tls_fullchain, openssl="openssl", email=None,
                     validation=None, credentials=None):
    """在可信 ops 容器内验证账户及 TLS 绑定；私钥仅通过标准输入传递。"""
    normalized, _ = normalize_acme_home(files, domain, email, validation, credentials)
    directory = domain + "_ecc"
    config = assignments(normalized[directory + "/" + domain + ".conf"], DOMAIN_FIELDS)
    ca, origin = ca_directory(config["Le_API"])
    ca_config = assignments(normalized[ca + "/ca.conf"], {"CA_EMAIL", "ACCOUNT_URL", "CA_KEY_HASH"})
    public = private_public(openssl, normalized[ca + "/account.key"])
    jwk = account_metadata(normalized[ca + "/account.json"], ca_config["CA_EMAIL"],
                           ca_config["ACCOUNT_URL"], origin)
    if jwk is not None:
        openssl_run(openssl, ["pkey", "-pubin", "-inform", "DER", "-pubcheck", "-noout"], jwk)
        verified = openssl_run(openssl, ["pkey", "-pubin", "-inform", "DER",
                                        "-pubout", "-outform", "DER"], jwk)
        require(verified == public)
    key_public = private_public(openssl, normalized[directory + "/" + domain + ".key"])
    require(key_public == private_public(openssl, tls_key))
    leaf = certificates(openssl, normalized[directory + "/" + domain + ".cer"])
    chain = certificates(openssl, normalized[directory + "/ca.cer"])
    fullchain = certificates(openssl, normalized[directory + "/fullchain.cer"])
    target = certificates(openssl, tls_fullchain)
    require(len(leaf) == 1 and [item[1] for item in fullchain] ==
            [item[1] for item in leaf + chain] == [item[1] for item in target])
    require(len({item[1] for item in fullchain}) == len(fullchain))
    cert_public = openssl_run(openssl, ["x509", "-pubkey", "-noout"], leaf[0][0])
    require(openssl_run(openssl, ["pkey", "-pubin", "-outform", "DER"], cert_public) == key_public)
    san = openssl_run(openssl, ["x509", "-noout", "-ext", "subjectAltName"], leaf[0][0])
    san_lines = [line.strip() for line in san.decode("ascii").splitlines()]
    require(len(san_lines) == 2 and san_lines[0] in (
        "X509v3 Subject Alternative Name:", "X509v3 Subject Alternative Name: critical")
        and san_lines[1] == "DNS:" + domain)
    # 这里只证明归档链内部有效；公网信任仍由既有 TLS 验证与签发验收负责。
    with tempfile.TemporaryDirectory(prefix="padm-acme-material-") as temporary:
        child_path = Path(temporary, "child.pem")
        issuer_path = Path(temporary, "issuer.pem")
        for index, (child, issuer) in enumerate(zip(fullchain, chain)):
            constraints = openssl_run(
                openssl, ["x509", "-noout", "-ext", "basicConstraints"], issuer[0])
            require(re.search(rb"\bCA:TRUE(?:,|\s|$)", constraints) is not None)
            child_path.write_bytes(child[0])
            issuer_path.write_bytes(issuer[0])
            openssl_run(openssl, ["verify", "-partial_chain", "-trusted", str(issuer_path),
                                 "-no-CAfile", "-no-CApath", "-no-CAstore",
                                 *(["-verify_hostname", domain] if index == 0 else []),
                                 str(child_path)])
        # 相邻签名通过后仍须整链校验，避免遗漏上级 CA 的路径长度和名称约束。
        child_path.write_bytes(leaf[0][0])
        intermediates = Path(temporary, "intermediates.pem")
        intermediates.write_bytes(b"".join(item[0] for item in chain[:-1]))
        openssl_run(openssl, ["verify", "-partial_chain", "-trusted", str(issuer_path),
                             "-no-CAfile", "-no-CApath", "-no-CAstore",
                             *(["-untrusted", str(intermediates)] if len(chain) > 1 else []),
                             "-verify_hostname", domain, str(child_path)])
    return {"account_key": "EC-P256", "tls_key": "EC-P256", "certificates": len(fullchain)}


def main():
    parser = argparse.ArgumentParser(description="在可信容器内检查已规范化 ACME 材料")
    commands = parser.add_subparsers(dest="command", required=True)
    check = commands.add_parser("check")
    check.add_argument("--home", required=True, type=Path)
    check.add_argument("--domain", required=True)
    check.add_argument("--tls-directory", required=True, type=Path)
    check.add_argument("--email")
    check.add_argument("--validation", choices=VALIDATIONS)
    check.add_argument("--credentials", type=Path)
    arguments = parser.parse_args()
    try:
        checked_domain(arguments.domain)
        require(arguments.home.is_absolute() and arguments.home.is_dir()
                and arguments.tls_directory.is_absolute() and arguments.tls_directory.is_dir())
        # 上游已完成树、清单和权限校验；此入口只接收受信暂存目录。
        files = {path.relative_to(arguments.home).as_posix(): path.read_bytes()
                 for path in arguments.home.rglob("*") if path.is_file()}
        credentials = None
        if arguments.credentials is not None:
            require(arguments.credentials.is_absolute() and arguments.credentials.is_file()
                    and arguments.credentials.stat().st_size <= MAX_CONFIG)
            credentials = arguments.credentials.read_bytes()
        _, summary = normalize_acme_home(files, arguments.domain, arguments.email,
                                         arguments.validation, credentials)
        summary["materials"] = verify_materials(
            files, arguments.domain,
            (arguments.tls_directory / (arguments.domain + ".key")).read_bytes(),
            (arguments.tls_directory / (arguments.domain + ".crt")).read_bytes(),
            email=arguments.email, validation=arguments.validation, credentials=credentials)
    except (ValueError, OSError):
        print("ACME 恢复材料检查失败", file=sys.stderr)
        return 1
    print(json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
