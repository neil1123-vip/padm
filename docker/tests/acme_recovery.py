#!/usr/bin/env python3
"""受限 ACME 配置解析、真实材料绑定与命令入口回归。"""

import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


HELPER = Path(__file__).resolve().parents[1] / "lib/acme_recovery.py"
SPEC = importlib.util.spec_from_file_location("padm_acme_recovery", HELPER)
acme = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(acme)
DOMAIN = "restore.example.test"
EMAIL = "restore@example.test"
API = "https://ca.example.test:14000/dir"
CA = "ca/ca.example.test/dir"
DIRECTORY = DOMAIN + "_ecc"
CONF = DIRECTORY + "/" + DOMAIN + ".conf"
KEY = DIRECTORY + "/" + DOMAIN + ".key"
LEAF = DIRECTORY + "/" + DOMAIN + ".cer"
ROOT = DIRECTORY + "/ca.cer"
CHAIN = DIRECTORY + "/fullchain.cer"


def fixture():
    account_key = b"account-private-marker\n"
    return {
        "account.conf": acme.encoded({"USER_PATH": acme.TRUSTED_PATH}),
        CA + "/account.key": account_key,
        CA + "/account.json": json.dumps({
            "status": "valid", "contact": ["mailto:" + EMAIL],
            "orders": "https://ca.example.test:14000/orders",
            "vendorMetadata": {"accepted": True, "terms": ["v1", 3, None]},
        }).encode(),
        CA + "/ca.conf": acme.encoded({
            "CA_EMAIL": EMAIL, "ACCOUNT_URL": "https://ca.example.test:14000/accounts/1",
            "CA_KEY_HASH": base64.b64encode(hashlib.sha256(account_key).digest()).decode(),
        }),
        CONF: acme.encoded({
            "Le_Domain": DOMAIN, "Le_Alt": "no", "Le_Webroot": "no",
            "Le_API": API, "Le_HTTPPort": "8080", "Le_Keylength": "ec-256",
            "Le_PreHook": "", "Le_PostHook": "", "Le_RenewHook": "", "Le_ReloadCmd": "",
            "Le_OrderFinalize": "https://ca.example.test:14000/order/1/finalize",
            "Le_LinkOrder": "https://ca.example.test:14000/order/1",
            "Le_LinkCert": "https://ca.example.test:14000/cert/1",
            "Le_CertCreateTime": "1792204237",
            "Le_CertCreateTimeStr": "2026-10-17T02:30:37Z",
        }),
        KEY: b"domain-private-marker\n", LEAF: b"leaf-public-marker\n",
        ROOT: b"ca-public-marker\n", CHAIN: b"chain-public-marker\n",
    }


def config(files, path, **changes):
    fields = acme.DOMAIN_FIELDS if path == CONF else {
        "USER_PATH", "CA_BUNDLE", "CA_EMAIL", "ACCOUNT_URL", "CA_KEY_HASH"}
    values = acme.assignments(files[path], fields)
    values.update(changes)
    files[path] = acme.encoded(values)


def webroot(files):
    files = dict(files)
    values = acme.assignments(files[CONF], acme.DOMAIN_FIELDS)
    values["Le_Webroot"] = acme.WEBROOT
    values.pop("Le_HTTPPort")
    files[CONF] = acme.encoded(values)
    return files


def alpn(files):
    files = dict(files)
    values = acme.assignments(files[CONF], acme.DOMAIN_FIELDS)
    values.update(Le_Webroot="alpn", Le_TLSPort="8443")
    values.pop("Le_HTTPPort")
    files[CONF] = acme.encoded(values)
    return files


class NormalizationTests(unittest.TestCase):
    def setUp(self):
        self.files = fixture()

    def rejected(self, files=None, domain=DOMAIN):
        with self.assertRaises(ValueError):
            acme.normalize_acme_home(self.files if files is None else files, domain, EMAIL)

    def test_round_trip_outputs_preserved_material_and_private_summary(self):
        normalized, summary = acme.normalize_acme_home(self.files, DOMAIN, EMAIL)
        config_values = acme.assignments(normalized[CONF], acme.DOMAIN_FIELDS)
        self.assertEqual(config_values["Le_RealCertPath"], "")
        self.assertEqual(config_values["Le_RealCACertPath"], "")
        self.assertEqual(config_values["Le_RealKeyPath"], "/var/lib/padm/tls-output/" + DOMAIN + ".key")
        self.assertEqual(config_values["Le_RealFullChainPath"],
                         "/var/lib/padm/tls-output/" + DOMAIN + ".crt")
        for path in (CA + "/account.key", CA + "/account.json", CA + "/ca.conf",
                     KEY, LEAF, ROOT, CHAIN):
            self.assertEqual(normalized[path], self.files[path])
        self.assertEqual(acme.normalize_acme_home(normalized, DOMAIN, EMAIL), (normalized, summary))
        for secret in (DOMAIN, EMAIL, API, "marker", "accounts/1"):
            self.assertNotIn(secret, json.dumps(summary))
        self.assertEqual(summary["normalized_files"], 9)
        self.assertEqual(summary["discarded_files"], 0)
        self.assertEqual(summary["validation"], "standalone-http01")

    def test_expected_validation_must_match_materials(self):
        normalized, summary = acme.normalize_acme_home(
            self.files, DOMAIN, EMAIL, validation="standalone-http01")
        self.assertEqual(summary["validation"], "standalone-http01")
        self.assertEqual(acme.normalize_acme_home(
            normalized, DOMAIN, EMAIL, validation="standalone-http01"), (normalized, summary))
        for validation in ("webroot-http01", "tls-alpn01", "dns", "alpn", "", False):
            with self.subTest(validation=validation), self.assertRaises(ValueError):
                acme.normalize_acme_home(self.files, DOMAIN, EMAIL, validation=validation)
        files = webroot(self.files)
        normalized, summary = acme.normalize_acme_home(
            files, DOMAIN, EMAIL, validation="webroot-http01")
        self.assertEqual(summary["validation"], "webroot-http01")
        self.assertEqual(acme.normalize_acme_home(
            normalized, DOMAIN, EMAIL, validation="webroot-http01"), (normalized, summary))
        with self.assertRaises(ValueError):
            acme.normalize_acme_home(files, DOMAIN, EMAIL, validation="standalone-http01")

    def test_fixed_webroot_shape_normalizes_without_http_port(self):
        files = webroot(self.files)
        normalized, summary = acme.normalize_acme_home(files, DOMAIN, EMAIL)
        values = acme.assignments(normalized[CONF], acme.DOMAIN_FIELDS)
        self.assertEqual(values["Le_Webroot"], "/var/lib/padm/acme-webroot")
        self.assertNotIn("Le_HTTPPort", values)
        self.assertEqual(values["Le_RealKeyPath"], "/var/lib/padm/tls-output/" + DOMAIN + ".key")
        self.assertEqual(summary["validation"], "webroot-http01")
        self.assertEqual(summary["normalized_files"], 9)
        self.assertEqual(set(normalized), set(self.files))
        for path in (CA + "/account.key", CA + "/account.json", CA + "/ca.conf",
                     KEY, LEAF, ROOT, CHAIN):
            self.assertEqual(normalized[path], files[path])

    def test_webroot_rejects_port_leftovers_other_challenges_and_execution(self):
        for field, value in (
            ("Le_HTTPPort", ""), ("Le_HTTPPort", "80"), ("Le_HTTPPort", "8080"),
            ("Le_Webroot", "/var/www"), ("Le_Webroot", acme.WEBROOT + "/"),
            ("Le_Webroot", acme.WEBROOT + "/../outside"), ("Le_Webroot", "no"),
            ("Le_Webroot", "alpn"), ("Le_Webroot", "dns_cf"),
            ("Le_Domain", "foreign.example.test"), ("Le_Alt", "extra.example.test"),
            ("Le_Keylength", "ec-384"), ("Le_ReloadCmd", "encoded-command"),
            ("Le_RealKeyPath", "/tmp/foreign"),
        ):
            with self.subTest(field=field, value=value):
                files = webroot(self.files)
                config(files, CONF, **{field: value})
                self.rejected(files)

    def test_fixed_alpn_shape_preserves_material_and_normalizes_idempotently(self):
        files = alpn(self.files)
        normalized, summary = acme.normalize_acme_home(
            files, DOMAIN, EMAIL, validation="tls-alpn01")
        values = acme.assignments(normalized[CONF], acme.DOMAIN_FIELDS)
        self.assertEqual(values["Le_Webroot"], "alpn")
        self.assertEqual(values["Le_TLSPort"], "8443")
        self.assertNotIn("Le_HTTPPort", values)
        self.assertEqual(summary["validation"], "tls-alpn01")
        self.assertEqual(summary["normalized_files"], 9)
        self.assertEqual(set(normalized), set(files))
        for path in (CA + "/account.key", CA + "/account.json", CA + "/ca.conf",
                     KEY, LEAF, ROOT, CHAIN):
            self.assertEqual(normalized[path], files[path])
        self.assertEqual(acme.normalize_acme_home(
            normalized, DOMAIN, EMAIL, validation="tls-alpn01"), (normalized, summary))
        for validation in ("standalone-http01", "webroot-http01"):
            with self.subTest(validation=validation), self.assertRaises(ValueError):
                acme.normalize_acme_home(files, DOMAIN, EMAIL, validation=validation)

    def test_alpn_rejects_missing_or_foreign_ports_and_challenge_drift(self):
        files = alpn(self.files)
        values = acme.assignments(files[CONF], acme.DOMAIN_FIELDS)
        del values["Le_TLSPort"]
        files[CONF] = acme.encoded(values)
        self.rejected(files)
        for field, value in (
            ("Le_TLSPort", ""), ("Le_TLSPort", "443"), ("Le_TLSPort", "8444"),
            ("Le_TLSPort", "08443"), ("Le_HTTPPort", ""), ("Le_HTTPPort", "8080"),
            ("Le_Webroot", "no"), ("Le_Webroot", acme.WEBROOT), ("Le_Webroot", "dns_cf"),
        ):
            with self.subTest(field=field, value=value):
                files = alpn(self.files)
                config(files, CONF, **{field: value})
                self.rejected(files)

    def test_http_challenges_reject_tls_port_leftovers(self):
        for source in (self.files, webroot(self.files)):
            for value in ("", "8443"):
                with self.subTest(source=source[CONF], port=value):
                    files = dict(source)
                    config(files, CONF, Le_TLSPort=value)
                    self.rejected(files)

    def test_known_transient_files_are_discarded(self):
        for path in ("http.header", DIRECTORY + "/" + DOMAIN + ".csr",
                     DIRECTORY + "/" + DOMAIN + ".csr.conf"):
            self.files[path] = b"transient-marker"
        self.files[DIRECTORY + "/backup/"] = b""
        normalized, summary = acme.normalize_acme_home(self.files, DOMAIN)
        self.assertEqual(set(normalized), set(fixture()))
        self.assertEqual(summary["discarded_files"], 4)
        self.files[DIRECTORY + "/backup/"] = b"not-empty"
        self.rejected()

    def test_missing_unknown_or_oversized_files_are_rejected(self):
        for path in self.files:
            with self.subTest(missing=path):
                files = dict(self.files)
                del files[path]
                self.rejected(files)
        for path in ("dnsapi/dns_test.sh", ".hidden", "../outside", DIRECTORY + "/backup/key"):
            with self.subTest(unknown=path):
                self.rejected({**self.files, path: b""})
        self.rejected({**self.files, KEY: b"x" * (acme.MAX_FILE + 1)})

    def test_shell_syntax_and_duplicate_or_unknown_fields_are_rejected(self):
        additions = (
            b"Le_Domain='other'\n", b"Le_DNS='dns_test'\n", b"Le_EAB_HMAC_KEY='secret'\n",
            b"Le_DeployHook='__ACME_BASE64__START_dG91Y2g=__ACME_BASE64__END_'\n",
            b"Le_DeployHook='touch /tmp/marker'\n", b"Le_PreHook=\"\"\n",
            b"Le_DeployHook='a' 'b'\n", b"Le_DeployHook='a\\b'\n",
            b"Le_DeployHook='$(id)'\n", b"Le_DeployHook='`id`'\n",
            b"Le_DeployHook='a;b'\n", b"Le_DeployHook='a|b'\n", b"Le_DeployHook='a&b'\n",
            b"Le_DeployHook='a>b'\n", b"Le_DeployHook='a<b'\n", b"Le_DeployHook='a(b)'\n",
            b"\n", b"# comment\n", b"\r\n", b"\x00",
        )
        for addition in additions:
            with self.subTest(addition=addition):
                self.rejected({**self.files, CONF: self.files[CONF] + addition})

    def test_nonempty_hooks_and_custom_outputs_are_rejected(self):
        for field in acme.HOOKS:
            with self.subTest(hook=field):
                files = dict(self.files)
                config(files, CONF, **{field: "encoded-command"})
                self.rejected(files)
        for field in acme.OUTPUTS:
            with self.subTest(output=field):
                files = dict(self.files)
                config(files, CONF, **{field: "/tmp/foreign"})
                self.rejected(files)

    def test_only_fixed_standalone_shape_is_accepted(self):
        for field, value in (
            ("Le_Domain", "foreign.example.test"), ("Le_Alt", "alt.example.test"),
            ("Le_Webroot", "/var/www"), ("Le_HTTPPort", "80"), ("Le_Keylength", "ec-384"),
        ):
            with self.subTest(field=field):
                files = dict(self.files)
                config(files, CONF, **{field: value})
                self.rejected(files)
        for domain in ("../outside", "UPPER.example.test", "a..test", "*.example.test",
                       "127.0.0.1", "local", "-bad.example.test", "a." + "x" * 64):
            with self.subTest(domain=domain):
                self.rejected(domain=domain)

    def test_account_execution_settings_are_rejected(self):
        for suffix in (
            b"CA_BUNDLE='/ca/local.crt'\n", b"SAVED_CA_BUNDLE='/ca/local.crt'\n",
            b"SAVED_CF_Token='private'\n", b"ACCOUNT_EMAIL='other@example.test'\n",
            b"USER_PATH='/usr/bin'\n", b"ACCOUNT_KEY_PATH='/tmp/key'\n",
        ):
            with self.subTest(setting=suffix):
                self.rejected({**self.files, "account.conf": self.files["account.conf"] + suffix})
        files = dict(self.files)
        config(files, "account.conf", USER_PATH="/usr/bin")
        self.rejected(files)
        config(files, "account.conf", USER_PATH=acme.TRUSTED_PATH, CA_BUNDLE="")
        self.assertEqual(acme.normalize_acme_home(files, DOMAIN)[1]["normalized_files"], 9)

    def test_account_hash_email_and_same_origin_are_enforced(self):
        for field, value in (
            ("CA_KEY_HASH", "invalid"), ("CA_EMAIL", "other@example.test"),
            ("ACCOUNT_URL", "https://foreign.example.test:14000/accounts/1"),
            ("ACCOUNT_URL", "https://ca.example.test/accounts/1"),
        ):
            with self.subTest(field=field, value=value):
                files = dict(self.files)
                config(files, CA + "/ca.conf", **{field: value})
                self.rejected(files)
        for field in acme.LINKS:
            files = dict(self.files)
            config(files, CONF, **{field: "https://other.example.test:14000/resource"})
            self.rejected(files)

    def test_ca_url_canonical_path_and_port(self):
        self.assertEqual(acme.ca_directory(API), (CA, ("ca.example.test", 14000)))
        self.assertEqual(acme.ca_directory(API + "/"), (CA, ("ca.example.test", 14000)))
        for url in (
            "http://ca.example.test/dir", "https://user@ca.example.test/dir",
            "https://ca.example.test/dir?x=1", "https://ca.example.test/dir#fragment",
            "https://ca.example.test/%64ir", "https://ca.example.test/a/../dir",
            "https://ca.example.test/./dir", "https://ca.example.test//dir",
            "https://ca.example.test:014000/dir", "https://ca.example.test:0/dir",
            "https://ca.example.test:65536/dir", "https://CA.example.test/dir",
            "https://ca.example.test\\evil/dir", "https://[::1]/dir",
        ):
            with self.subTest(url=url):
                files = dict(self.files)
                config(files, CONF, Le_API=url)
                self.rejected(files)

    def test_time_fields_are_validated(self):
        for changes in (
            {"Le_CertCreateTime": "-1"}, {"Le_CertCreateTimeStr": "2026-10-17T02:30:38Z"},
            {"Le_CertCreateTimeStr": "not-a-date"}, {"Le_NextRenewTimeStr": "2026-10-17T02:30:37Z"},
        ):
            with self.subTest(changes=changes):
                files = dict(self.files)
                config(files, CONF, **changes)
                self.rejected(files)

    def test_bounded_strict_json_and_inert_metadata(self):
        for data in (
            b'{"status":"valid","status":"valid"}', b'{"meta":{"a":1,"a":2}}',
            b'{"n":NaN}', b'{"n":Infinity}', b'{"n":1e10000}', b'{"n":-1e10000}',
            b"[]", b"{}", b'{"n":"' + b"x" * 4097 + b'"}',
            b'{"n":' + b"[" * 25 + b"0" + b"]" * 25 + b"}",
            b'{"n":[' + b"0," * 4096 + b"0]}", b"x" * (acme.MAX_CONFIG + 1),
        ):
            with self.subTest(size=len(data)):
                self.rejected({**self.files, CA + "/account.json": data})
        data = b'{"vendor":{"notes":"$(id); harmless inert metadata","version":0.5}}'
        normalized, _ = acme.normalize_acme_home({**self.files, CA + "/account.json": data}, DOMAIN)
        self.assertEqual(normalized[CA + "/account.json"], data)

    def test_account_metadata_rejects_foreign_binding_and_eab(self):
        for account in (
            {"status": "revoked"}, {"contact": ["mailto:other@example.test"]},
            {"orders": "https://foreign.example.test:14000/orders"},
            {"url": "https://ca.example.test:14000/accounts/2"},
            {"externalAccountBinding": {"protected": "opaque"}},
            {"eab_kid": "kid"}, {"eab_hmac_key": "secret"},
        ):
            with self.subTest(account=account):
                self.rejected({**self.files, CA + "/account.json": json.dumps(account).encode()})

    def test_jwk_must_be_canonical_p256_public_data(self):
        jwk = {"kty": "EC", "crv": "P-256", "x": "A" * 43, "y": "A" * 43}
        self.assertEqual(len(acme.jwk_public(jwk)), len(acme.P256_SPKI) + 64)
        for changes in (
            {"kty": "RSA"}, {"crv": "P-384"}, {"x": "A" * 42}, {"x": "A" * 43 + "="},
            {"x": "A" * 42 + "B"}, {"x": "/" * 43}, {"d": "secret"},
        ):
            with self.subTest(changes=changes):
                self.rejected({**self.files, CA + "/account.json":
                               json.dumps({"key": {**jwk, **changes}}).encode()})


class MaterialTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="padm-acme-test-", dir=os.environ["TMPDIR"])
        cls.addClassCleanup(cls.directory.cleanup)
        cls.root = Path(cls.directory.name)

        def run(*arguments, data=None):
            result = subprocess.run(["openssl", *arguments], input=data, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, timeout=15, check=True)
            return result.stdout

        cls.run_openssl = staticmethod(run)
        cls.account_key = run("genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256")
        cls.domain_key = run("genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256")
        cls.other_key = run("genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256")
        cls.ca_key = cls.root / "ca.key"
        cls.ca_key.write_bytes(run("genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256"))
        cls.ca_cert = run("req", "-new", "-x509", "-key", str(cls.ca_key), "-subj", "/CN=Restore Test CA",
                          "-days", "2", "-addext", "basicConstraints=critical,CA:TRUE",
                          "-addext", "keyUsage=critical,keyCertSign,cRLSign")
        cls.ca_path = cls.root / "ca.pem"
        cls.ca_path.write_bytes(cls.ca_cert)
        cls.leaf = cls.issue_certificate(DOMAIN, cls.domain_key)
        cls.files = fixture()
        cls.files[CA + "/account.key"] = cls.account_key
        config(cls.files, CA + "/ca.conf",
               CA_KEY_HASH=base64.b64encode(hashlib.sha256(cls.account_key).digest()).decode())
        cls.files[KEY] = cls.domain_key
        cls.files[LEAF] = cls.leaf
        cls.files[ROOT] = cls.ca_cert
        cls.files[CHAIN] = cls.leaf + cls.ca_cert
        account = json.loads(cls.files[CA + "/account.json"])
        public = run("pkey", "-pubout", "-outform", "DER", data=cls.account_key)
        account["key"] = {
            "kty": "EC", "crv": "P-256",
            "x": base64.urlsafe_b64encode(public[-64:-32]).decode().rstrip("="),
            "y": base64.urlsafe_b64encode(public[-32:]).decode().rstrip("="),
        }
        cls.files[CA + "/account.json"] = json.dumps(account).encode()

    @classmethod
    def issue_certificate(cls, domain, key, additional_san=None, days="1", critical=False):
        san = "DNS:" + domain + (",DNS:" + additional_san if additional_san else "")
        request = cls.run_openssl("req", "-new", "-key", "/dev/stdin", "-subj", "/CN=" + domain,
                                  "-addext", "subjectAltName=" + ("critical," if critical else "") + san,
                                  data=key)
        return cls.run_openssl(
            "x509", "-req", "-CA", str(cls.ca_path), "-CAkey", str(cls.ca_key),
            "-set_serial", "42", "-days", days, "-copy_extensions", "copy", data=request)

    def verify(self, files=None, tls_key=None, tls_fullchain=None, validation=None):
        return acme.verify_materials(
            self.files if files is None else files, DOMAIN,
            self.domain_key if tls_key is None else tls_key,
            self.files[CHAIN] if tls_fullchain is None else tls_fullchain,
            email=EMAIL, validation=validation)

    def test_real_account_jwk_and_tls_materials(self):
        self.assertEqual(self.verify(),
                         {"account_key": "EC-P256", "tls_key": "EC-P256", "certificates": 2})
        files = dict(self.files)
        account = json.loads(files[CA + "/account.json"])
        del account["key"]
        files[CA + "/account.json"] = json.dumps(account).encode()
        self.assertEqual(self.verify(files)["certificates"], 2)

    def test_webroot_keeps_real_material_and_expected_validation_binding(self):
        files = webroot(self.files)
        self.assertEqual(self.verify(files, validation="webroot-http01"),
                         {"account_key": "EC-P256", "tls_key": "EC-P256", "certificates": 2})
        for source, validation in ((self.files, "webroot-http01"),
                                   (files, "standalone-http01")):
            with self.subTest(validation=validation), self.assertRaises(ValueError):
                self.verify(source, validation=validation)
        with self.assertRaises(ValueError):
            self.verify(files, tls_key=self.other_key, validation="webroot-http01")
        config(files, CA + "/ca.conf", CA_EMAIL="other@example.test")
        with self.assertRaises(ValueError):
            self.verify(files, validation="webroot-http01")

    def test_alpn_keeps_real_material_and_expected_validation_binding(self):
        files = alpn(self.files)
        self.assertEqual(self.verify(files, validation="tls-alpn01"),
                         {"account_key": "EC-P256", "tls_key": "EC-P256", "certificates": 2})
        for validation in ("standalone-http01", "webroot-http01"):
            with self.subTest(validation=validation), self.assertRaises(ValueError):
                self.verify(files, validation=validation)
        with self.assertRaises(ValueError):
            self.verify(files, tls_key=self.other_key, validation="tls-alpn01")

    def test_jwk_must_match_account_key_and_be_a_curve_point(self):
        for coordinates in ("foreign", "zero"):
            with self.subTest(coordinates=coordinates):
                files = dict(self.files)
                account = json.loads(files[CA + "/account.json"])
                public = self.run_openssl("pkey", "-pubout", "-outform", "DER", data=self.other_key)
                account["key"]["x"] = (base64.urlsafe_b64encode(public[-64:-32]).decode().rstrip("=")
                                      if coordinates == "foreign" else "A" * 43)
                account["key"]["y"] = (base64.urlsafe_b64encode(public[-32:]).decode().rstrip("=")
                                      if coordinates == "foreign" else "A" * 43)
                files[CA + "/account.json"] = json.dumps(account).encode()
                with self.assertRaises(ValueError):
                    self.verify(files)

    def test_critical_san_preserves_single_domain_constraint(self):
        leaf = self.issue_certificate(DOMAIN, self.domain_key, critical=True)
        files = {**self.files, LEAF: leaf, CHAIN: leaf + self.ca_cert}
        self.assertEqual(self.verify(files, tls_fullchain=files[CHAIN])["certificates"], 2)
        leaf = self.issue_certificate(DOMAIN, self.domain_key, "extra.example.test", critical=True)
        files = {**self.files, LEAF: leaf, CHAIN: leaf + self.ca_cert}
        with self.assertRaises(ValueError):
            self.verify(files, tls_fullchain=files[CHAIN])

    def test_wrong_key_type_and_curve_are_rejected(self):
        for arguments in (
            ("-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-384"),
            ("-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048"),
        ):
            with self.subTest(algorithm=arguments):
                key = self.run_openssl("genpkey", *arguments)
                with self.assertRaises(ValueError):
                    self.verify(tls_key=key)
                files = dict(self.files)
                files[CA + "/account.key"] = key
                config(files, CA + "/ca.conf",
                       CA_KEY_HASH=base64.b64encode(hashlib.sha256(key).digest()).decode())
                with self.assertRaises(ValueError):
                    self.verify(files)

    def test_private_keys_reject_extra_pem_payload_and_encryption(self):
        traditional = self.run_openssl("pkey", "-traditional", data=self.domain_key)
        self.assertEqual(self.verify(tls_key=traditional)["tls_key"], "EC-P256")
        encrypted = self.run_openssl(
            "pkey", "-aes-256-cbc", "-passout", "pass:", data=self.domain_key)
        for data in (self.domain_key + b"foreign payload",
                     self.domain_key + self.other_key, encrypted,
                     b"x" * (acme.MAX_FILE + 1)):
            with self.subTest(size=len(data)):
                with self.assertRaises(ValueError):
                    self.verify(tls_key=data)
        for path, original in ((CA + "/account.key", self.account_key), (KEY, self.domain_key)):
            with self.subTest(path=path):
                files = {**self.files, path: original + b"foreign payload"}
                if path == CA + "/account.key":
                    config(files, CA + "/ca.conf", CA_KEY_HASH=base64.b64encode(
                        hashlib.sha256(files[path]).digest()).decode())
                with self.assertRaises(ValueError):
                    self.verify(files)

    def test_chain_order_duplicates_and_unrelated_issuers_are_rejected(self):
        foreign_ca = self.run_openssl(
            "req", "-new", "-x509", "-key", "/dev/stdin", "-subj", "/CN=Foreign Test CA",
            "-days", "2", "-addext", "basicConstraints=critical,CA:TRUE",
            "-addext", "keyUsage=critical,keyCertSign,cRLSign", data=self.other_key)
        for chain in (self.ca_cert * 2, foreign_ca + self.ca_cert,
                      self.ca_cert + foreign_ca, self.leaf):
            with self.subTest(certificates=chain.count(b"-----BEGIN CERTIFICATE-----")):
                files = {**self.files, ROOT: chain, CHAIN: self.leaf + chain}
                with self.assertRaises(ValueError):
                    self.verify(files, tls_fullchain=files[CHAIN])

    def test_intermediate_chain_accepts_only_ca_issuers(self):
        with tempfile.TemporaryDirectory(prefix="issuer-", dir=self.root) as temporary:
            root = Path(temporary)
            issuer_key = root / "issuer.key"
            issuer_key.write_bytes(self.other_key)
            issuer_cert = root / "issuer.pem"
            for ca in ("TRUE", "FALSE"):
                request = self.run_openssl(
                    "req", "-new", "-key", str(issuer_key), "-subj", "/CN=Restore Issuer",
                    "-addext", "basicConstraints=critical,CA:" + ca)
                issuer = self.run_openssl(
                    "x509", "-req", "-CA", str(self.ca_path), "-CAkey", str(self.ca_key),
                    "-set_serial", "43", "-days", "1", "-copy_extensions", "copy", data=request)
                issuer_cert.write_bytes(issuer)
                request = self.run_openssl(
                    "req", "-new", "-key", "/dev/stdin", "-subj", "/CN=" + DOMAIN,
                    "-addext", "subjectAltName=DNS:" + DOMAIN, data=self.domain_key)
                leaf = self.run_openssl(
                    "x509", "-req", "-CA", str(issuer_cert), "-CAkey", str(issuer_key),
                    "-set_serial", "44", "-days", "1", "-copy_extensions", "copy", data=request)
                for chain in (issuer, issuer + self.ca_cert):
                    with self.subTest(ca=ca, certificates=chain.count(b"-----BEGIN CERTIFICATE-----")):
                        files = {**self.files, ROOT: chain, LEAF: leaf, CHAIN: leaf + chain}
                        if ca == "TRUE":
                            self.assertEqual(self.verify(files, tls_fullchain=files[CHAIN])[
                                "certificates"], 1 + chain.count(b"-----BEGIN CERTIFICATE-----"))
                        else:
                            with self.assertRaises(ValueError):
                                self.verify(files, tls_fullchain=files[CHAIN])
                if ca == "TRUE":
                    limited_ca = self.run_openssl(
                        "req", "-new", "-x509", "-key", str(self.ca_key),
                        "-subj", "/CN=Restore Test CA", "-days", "2",
                        "-addext", "basicConstraints=critical,CA:TRUE,pathlen:0",
                        "-addext", "keyUsage=critical,keyCertSign,cRLSign")
                    chain = issuer + limited_ca
                    files = {**self.files, ROOT: chain, LEAF: leaf, CHAIN: leaf + chain}
                    with self.assertRaises(ValueError):
                        self.verify(files, tls_fullchain=files[CHAIN])

    def test_tls_targets_leaf_fullchain_and_pem_must_match(self):
        with self.assertRaises(ValueError):
            self.verify(tls_key=self.other_key)
        with self.assertRaises(ValueError):
            self.verify(tls_fullchain=self.leaf)
        for path, data in (
            (KEY, self.other_key), (LEAF, self.ca_cert), (ROOT, self.leaf),
            (CHAIN, self.ca_cert + self.leaf), (CHAIN, self.files[CHAIN] + b"foreign payload"),
            (CA + "/account.key", b"invalid key"), (KEY, b""), (LEAF, b"invalid cert"),
        ):
            with self.subTest(path=path):
                files = dict(self.files)
                files[path] = data
                if path == CA + "/account.key":
                    config(files, CA + "/ca.conf",
                           CA_KEY_HASH=base64.b64encode(hashlib.sha256(data).digest()).decode())
                with self.assertRaises(ValueError):
                    self.verify(files)

    def test_foreign_domain_and_extra_san_are_rejected(self):
        for domain, extra in (("foreign.example.test", None), (DOMAIN, "extra.example.test")):
            with self.subTest(domain=domain, extra=extra):
                leaf = self.issue_certificate(domain, self.domain_key, extra)
                files = {**self.files, LEAF: leaf, CHAIN: leaf + self.ca_cert}
                with self.assertRaises(ValueError):
                    self.verify(files, tls_fullchain=files[CHAIN])

    def test_expired_certificate_and_oversized_chain_are_rejected(self):
        leaf = self.issue_certificate(DOMAIN, self.domain_key, days="0")
        files = {**self.files, LEAF: leaf, CHAIN: leaf + self.ca_cert}
        with self.assertRaises(ValueError):
            self.verify(files, tls_fullchain=files[CHAIN])
        with self.assertRaises(ValueError):
            acme.certificates("openssl", self.ca_cert * 9)

    def test_missing_openssl_and_cli_failure_do_not_leak_material(self):
        with self.assertRaises(ValueError):
            acme.verify_materials(self.files, DOMAIN, self.domain_key, self.files[CHAIN],
                                  openssl="/missing/padm-test-openssl")
        with tempfile.TemporaryDirectory(prefix="cli-", dir=self.root) as temporary:
            root = Path(temporary)
            home = root / "home"
            tls = root / "tls"
            home.mkdir()
            tls.mkdir()
            for path, data in self.files.items():
                destination = home / path
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(data)
            (tls / (DOMAIN + ".key")).write_bytes(self.domain_key)
            (tls / (DOMAIN + ".crt")).write_bytes(self.files[CHAIN])
            command = [sys.executable, str(HELPER), "check", "--home", str(home),
                       "--domain", DOMAIN, "--tls-directory", str(tls), "--email", EMAIL]
            success = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     timeout=30, check=False)
            self.assertEqual(success.returncode, 0, success.stderr.decode())
            self.assertEqual(json.loads(success.stdout)["materials"]["certificates"], 2)
            for files, validation in ((webroot(self.files), "webroot-http01"),
                                      (alpn(self.files), "tls-alpn01")):
                (home / CONF).write_bytes(files[CONF])
                success = subprocess.run(command + ["--validation", validation],
                                         stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                         timeout=30, check=False)
                self.assertEqual(success.returncode, 0, success.stderr.decode())
                self.assertEqual(json.loads(success.stdout)["validation"], validation)
            mismatch = subprocess.run(command + ["--validation", "standalone-http01"],
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                      timeout=30, check=False)
            self.assertEqual(mismatch.returncode, 1)
            self.assertEqual(mismatch.stdout, b"")
            self.assertNotIn(b"PRIVATE KEY", mismatch.stderr)
            self.assertNotIn(EMAIL.encode(), mismatch.stderr)
            (home / CONF).write_bytes(self.files[CONF] + b"Le_DNS='private-marker'\n")
            failed = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    timeout=30, check=False)
            self.assertEqual(failed.returncode, 1)
            self.assertEqual(failed.stdout, b"")
            self.assertNotIn(b"private-marker", failed.stderr)
            self.assertNotIn(b"PRIVATE KEY", failed.stderr)
            self.assertNotIn(EMAIL.encode(), failed.stderr)


if __name__ == "__main__":
    unittest.main()
