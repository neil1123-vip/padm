#!/usr/bin/env python3
"""检查静态站点的公开资源合同。"""

import argparse
import hashlib
from html.parser import HTMLParser
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit


PLACEHOLDERS = {"__SITE_TITLE__", "__SITE_ACCENT__"}
DISCLOSURE = re.compile(
    r"\b(?:fallback|masquerade|hysteria2?|padm)\b|"
    r"no external (?:assets|dependencies)|randomi[sz](?:ed|ation)",
    re.IGNORECASE,
)
TOKEN = re.compile(r"__[A-Z][A-Z0-9_]*__")
CSS_URL = re.compile(r"url\(\s*(['\"]?)(.*?)\1\s*\)", re.IGNORECASE)
MANIFEST_LINE = re.compile(
    r"([a-f0-9]{64})  (sites/(?:notes|photos|docs)/"
    r"(?:[a-z0-9][a-z0-9-]*\.html|assets/[a-z0-9][a-z0-9-]*\.(?:css|jpg|png)))"
)


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids = set()
        self.links = []
        self.tags = set()
        self.viewport = False
        self.favicon = False
        self.title = False
        self.has_title = False

    def handle_starttag(self, tag, attributes):
        attributes = dict(attributes)
        self.tags.add(tag)
        if attributes.get("id"):
            require(attributes["id"] not in self.ids, "duplicate element id")
            self.ids.add(attributes["id"])
        if tag == "title":
            self.title = True
        if tag == "meta" and attributes.get("name") == "viewport":
            self.viewport = "width=device-width" in attributes.get("content", "")
        if tag == "link" and "icon" in attributes.get("rel", "").split():
            self.favicon = True
        for key in ("src", "href", "poster"):
            if key in attributes:
                runtime = key != "href" or tag == "link"
                self.links.append((attributes[key], runtime))
        if "srcset" in attributes:
            self.links.extend(
                (item.strip().split()[0], True)
                for item in attributes["srcset"].split(",")
                if item.strip()
            )
        if tag == "img":
            require("alt" in attributes, "image needs alt text")

    def handle_endtag(self, tag):
        if tag == "title":
            self.title = False

    def handle_data(self, data):
        if self.title and data.strip():
            self.has_title = True


def require(condition, message):
    if not condition:
        raise ValueError(message)


def local_target(root, source, value, runtime):
    require(value.strip(), f"{source.name}: empty link")
    address = urlsplit(value)
    if address.scheme or address.netloc:
        require(not runtime, f"{source.name}: remote runtime resource {value}")
        require(address.scheme in {"https", "http", "mailto"}, f"unsupported link {value}")
        return None, ""
    path = unquote(address.path)
    require("\\" not in path and "\0" not in path, f"invalid resource path {value}")
    target = root / path.lstrip("/") if path.startswith("/") else source.parent / path
    if not path:
        target = source
    target = target.resolve()
    require(target.is_relative_to(root), f"{source.name}: resource escapes site {value}")
    if target.is_dir():
        target /= "index.html"
    require(target.is_file(), f"{source.name}: missing resource {value}")
    return target, unquote(address.fragment)


def check_site(directory, installed=False):
    root = directory.resolve()
    require(root.is_dir(), f"missing site directory {directory}")
    require(not (root / "check").exists(), f"{directory}: public check marker")
    pages = {}
    for path in sorted(root.rglob("*")):
        require(not path.is_symlink(), f"{path}: symlink in public assets")
        if not path.is_file():
            continue
        require(path.stat().st_nlink == 1, f"{path}: hard link in public assets")
        require(not any(part.startswith(".") for part in path.relative_to(root).parts),
                f"{path}: private file in public assets")
        require(path.stat().st_size > 0, f"{path}: empty asset")
        if path.suffix.lower() in {".html", ".css", ".js"}:
            content = path.read_text(encoding="utf-8")
            tokens = set(TOKEN.findall(content))
            require(not tokens if installed else tokens <= PLACEHOLDERS,
                    f"{path}: unexpected placeholders {sorted(tokens)}")
            require(not DISCLOSURE.search(content), f"{path}: installation disclosure")
            if path.suffix == ".html":
                page = Page()
                page.feed(content)
                require(page.has_title and {"h1", "nav"} <= page.tags and page.viewport
                        and page.favicon, f"{path}: incomplete page structure")
                pages[path] = page
            if path.suffix == ".css":
                require("@import" not in content.lower(), f"{path}: imported stylesheet")
                for match in CSS_URL.finditer(content):
                    local_target(root, path, match.group(2), True)
        if path.suffix == ".png":
            require(path.read_bytes().startswith(b"\x89PNG\r\n\x1a\n"), f"{path}: invalid PNG")
        if path.suffix.lower() in {".jpg", ".jpeg"}:
            require(path.read_bytes().startswith(b"\xff\xd8\xff"), f"{path}: invalid JPEG")
    require(len(pages) >= 4, f"{directory}: incomplete site")
    require(root / "index.html" in pages and root / "404.html" in pages,
            f"{directory}: missing index or 404 page")
    for source, page in pages.items():
        for value, runtime in page.links:
            target, fragment = local_target(root, source, value, runtime)
            if fragment and target in pages:
                require(fragment in pages[target].ids, f"{source}: missing fragment {value}")
    return len(pages)


def check_manifest(root):
    manifest = root / "sites.sha256"
    require(manifest.is_file() and not manifest.is_symlink()
            and manifest.stat().st_nlink == 1, "missing or unsafe resource manifest")
    content = manifest.read_bytes()
    require(content.endswith(b"\n") and b"\r" not in content, "nonstandard resource manifest")
    expected = {}
    for line in content.decode("ascii").splitlines():
        match = MANIFEST_LINE.fullmatch(line)
        require(match is not None, "invalid resource manifest path or hash")
        digest, relative = match.groups()
        require(relative not in expected, f"duplicate resource manifest path {relative}")
        target = root / relative
        require(target.is_file() and not target.is_symlink() and target.stat().st_nlink == 1,
                f"missing or unsafe manifest resource {relative}")
        require(hashlib.sha256(target.read_bytes()).hexdigest() == digest,
                f"resource manifest hash mismatch {relative}")
        expected[relative] = digest
    actual = {path.relative_to(root).as_posix()
              for path in (root / "sites").rglob("*") if path.is_file()}
    require(set(expected) == actual, "resource manifest differs from complete asset set")
    print(f"static-site-assets: manifest:{len(expected)} files")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("project", type=Path)
    parser.add_argument("--installed", type=Path)
    arguments = parser.parse_args()
    if arguments.installed:
        count = check_site(arguments.installed, installed=True)
        print(f"static-site-assets: installed:{count} pages")
        return
    sites = arguments.project / "assets/static-sites/sites"
    fingerprints = set()
    for theme in ("notes", "photos", "docs"):
        directory = sites / theme
        count = check_site(directory)
        fingerprints.add(hashlib.sha256((directory / "index.html").read_bytes()).digest())
        print(f"static-site-assets: {theme}:{count} pages")
    require(len(fingerprints) == 3, "site homepages must differ")
    check_manifest(sites.parent)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        raise SystemExit(f"static-site-assets: {error}") from error
