#!/usr/bin/env python3
import argparse
import os
import re
import stat
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

TOKEN = re.compile(r"^[A-Za-z0-9_-]{16,128}$")
MAX_SUBSCRIPTION_BYTES = 1024 * 1024


class SubscriptionHandler(BaseHTTPRequestHandler):
    server_version = "padm-subscription/1"

    def do_GET(self):
        if self.path == "/healthz":
            self._reply(200, b"ok\n")
            return
        token = self.path.removeprefix("/")
        if not TOKEN.fullmatch(token):
            self.send_error(404)
            return
        try:
            content = read_subscription(self.server.subscription_root, token)
        except (FileNotFoundError, OSError, ValueError):
            self.send_error(404)
            return
        self._reply(200, content)

    def _reply(self, status_code, content):
        self.send_response(status_code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(content)

    def log_message(self, message_format, *args):
        status = args[1] if len(args) > 1 else "-"
        print(f"subscription-request status={status}", flush=True)


def read_subscription(root, token):
    root_path = Path(root).resolve(strict=True)
    target = root_path / token
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(target, flags)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > MAX_SUBSCRIPTION_BYTES:
            raise ValueError("unsafe subscription file")
        with os.fdopen(descriptor, "rb", closefd=False) as source:
            return source.read(MAX_SUBSCRIPTION_BYTES + 1)
    finally:
        os.close(descriptor)


def health_check(url):
    with urllib.request.urlopen(url, timeout=3) as response:
        if response.status != 200 or response.read(16) != b"ok\n":
            raise RuntimeError("subscription health check failed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", default=8081, type=int)
    parser.add_argument("--root", default=os.environ.get("PADM_SUBSCRIPTION_ROOT", "/var/lib/padm/subscription"))
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--health")
    args = parser.parse_args()
    if args.check:
        if not TOKEN.fullmatch("0123456789abcdef"):
            raise RuntimeError("token validator is unavailable")
        return
    if args.health:
        health_check(args.health)
        return
    root = Path(args.root).resolve(strict=True)
    if not root.is_dir() or not 1 <= args.port <= 65535:
        raise SystemExit(64)
    server = ThreadingHTTPServer((args.bind, args.port), SubscriptionHandler)
    server.subscription_root = root
    server.serve_forever()


if __name__ == "__main__":
    main()
