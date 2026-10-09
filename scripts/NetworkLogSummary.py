"""Print only error domain/codes from this application's CFNetwork log.

Never print messages or request URLs; calendar subscription tokens are private.
"""
import json
import re
import sys
from urllib.parse import urlsplit

try:
    records = json.load(sys.stdin)
except (ValueError, OSError):
    print("No readable application network diagnostics.")
    raise SystemExit(0)

codes = set()
hosts = set()
ssl_codes = set()
stream_codes = set()
for record in records:
    message = record.get("eventMessage", "")
    codes.update(re.findall(r"Error Domain=([A-Za-z][A-Za-z0-9_.]+) Code=(-?\d+)", message))
    for address in re.findall(r'\bhttps?://[^\s"<>]+', message):
        try:
            url = urlsplit(address)
            host = url.hostname or ""
            if host == "bb.cuhk.edu.cn" or host.endswith(".cuhk.edu.cn"):
                hosts.add(f"{host}:{url.port or (443 if url.scheme == 'https' else 80)}")
        except ValueError:
            pass
    ssl_codes.update(re.findall(r"\b(?:SSLHandshake|SSL|TLS)[A-Za-z ]*(?:failed|error)[A-Za-z :]*\((-?\d+)\)", message))
    stream_codes.update(re.findall(r"(_kCFStreamErrorCodeKey|_kCFNetworkCFStreamSSLErrorOriginalValue|_kCFStreamErrorDomainKey)\s*[=:]\s*(-?\d+)", message))
    stream_codes.update(("connect", value) for value in re.findall(r"failed to connect \d+:(-?\d+)", message))
for domain, code in sorted(codes):
    print(f"{domain}: {code}")
if not codes:
    print("No recorded application network error codes.")
for host in sorted(hosts):
    print(f"School server: {host}")
for code in sorted(ssl_codes):
    print(f"TLS detail code: {code}")
for key, code in sorted(stream_codes):
    print(f"{key}: {code}")
