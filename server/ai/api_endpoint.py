"""Pure HTTP endpoint parsing matching scripts/providers/api_endpoint.gd."""
from __future__ import annotations

import ipaddress
import re
import urllib.parse

MAX_URL_LENGTH = 2048


def _failure(message):
    return {"success": False, "url": "", "message": message}


def _valid_port(port):
    if not port or any(c not in "0123456789" for c in port):
        return False
    significant = port.lstrip("0") or "0"
    return len(significant) <= 5 and 1 <= int(significant) <= 65535


def _valid_host(host):
    if not host:
        return False
    if all(c in "0123456789." for c in host):
        parts = host.split(".")
        return len(parts) == 4 and all(part and len(part) <= 3 and int(part) <= 255 for part in parts)
    domain = host[:-1] if host.endswith(".") else host
    return bool(domain) and len(domain) <= 253 and all(
        1 <= len(label) <= 63 and not label.startswith("-") and not label.endswith("-")
        and re.fullmatch(r"[A-Za-z0-9-]+", label) for label in domain.split("."))


def _parse_http_url(url):
    if not isinstance(url, str) or not 1 <= len(url) <= MAX_URL_LENGTH:
        return _failure("HTTP 地址需为 1–2048 个字符。")
    for character in url:
        code = ord(character)
        if (code <= 32 or 127 <= code <= 160 or code in (0x1680, 0x180e, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff)
                or 0x2000 <= code <= 0x200f or 0x202a <= code <= 0x202e or 0x2060 <= code <= 0x206f):
            return _failure("地址中不能包含空白或控制字符。")
    if any(marker in url for marker in ('@', '?', '#', '\\', '"', '<', '>', '{', '}', '|', '^', '`')):
        return _failure("地址不能包含账号、查询参数、片段或未转义的特殊字符。")
    separator = url.find("://")
    if separator < 0:
        return _failure("地址需以 http:// 或 https:// 开头。")
    scheme = url[:separator].lower()
    if scheme not in ("http", "https"):
        return _failure("接口地址仅支持 HTTP 或 HTTPS。")
    try:
        parsed = urllib.parse.urlsplit(url)
    except ValueError:
        return _failure("请填写有效的主机名或 IP 地址。")
    authority, path = parsed.netloc, parsed.path
    if not authority:
        return _failure("请填写有效的主机名或 IP 地址。")
    if re.search(r"%(?![0-9a-fA-F]{2})", path):
        return _failure("地址中的百分号需要有效的两位十六进制转义。")
    port = ""
    if authority.startswith("["):
        closing = authority.find("]")
        if closing < 0:
            return _failure("IPv6 地址需要完整的方括号。")
        address = authority[1:closing]
        try:
            if ":" not in address or "%" in address:
                raise ValueError("not a plain IPv6 address")
            ipaddress.IPv6Address(address)
        except ValueError:
            return _failure("方括号中需要有效的 IPv6 地址。")
        host = "[" + address.lower() + "]"
        suffix = authority[closing + 1:]
        if suffix:
            if not suffix.startswith(":"):
                return _failure("IPv6 地址的方括号后只能跟端口。")
            port = suffix[1:]
            if not _valid_port(port):
                return _failure("端口必须是 1–65535 的整数。")
    elif "[" in authority or "]" in authority:
        return _failure("IPv6 地址需要放在方括号中。")
    else:
        host, colon, port = authority.partition(":")
        if colon and not _valid_port(port):
            return _failure("端口必须是 1–65535 的整数，IPv6 地址需使用方括号。")
        if not _valid_host(host):
            return _failure("请填写有效的域名、IPv4 地址或带方括号的 IPv6 地址。")
        host = host.lower()
    port = ":" + str(int(port)) if port else ""
    origin = scheme + "://" + host + port
    return {"success": True, "url": origin + path, "origin": origin, "path": path, "message": ""}


def http_url_valid(url):
    """Validate existing transport paths without adding a chat endpoint."""
    return _parse_http_url(url)["success"]


def normalize_chat_url(raw):
    if not isinstance(raw, str) or len(raw) > MAX_URL_LENGTH:
        return _failure("接口地址不能超过 2048 个字符。")
    value = raw.strip(" ")
    if not value:
        return {"success": True, "url": "", "message": ""}
    separator = value.find("://")
    if separator >= 0:
        prefix = value[:separator].rstrip("\\")
        if prefix.lower() in ("http", "https"):
            value = prefix + value[separator:]
    value = value.rstrip("\\/")
    parsed = _parse_http_url(value)
    if not parsed["success"]:
        return _failure(parsed["message"])
    path = parsed["path"]
    if not path:
        path = "/v1/chat/completions"
    elif path.endswith("/chat/completions"):
        pass
    elif path.endswith("/v1/chat"):
        path += "/completions"
    elif path.endswith("/v1"):
        path += "/chat/completions"
    else:
        return _failure("请填写根地址、以 /v1 或 /v1/chat 结尾的地址，或完整的 /chat/completions 接口。")
    url = parsed["origin"] + path
    if len(url) > MAX_URL_LENGTH:
        return _failure("补全后的接口地址不能超过 2048 个字符。")
    return {"success": True, "url": url, "message": ""}
