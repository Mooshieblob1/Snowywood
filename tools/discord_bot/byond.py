"""Async client for the BYOND world-topic interface (DreamDaemon).

DreamDaemon exposes a binary "world Topic" protocol on the game port. We use it
to query server status and to push messages into the running round (OOC bridge,
admin replies). The packet format mirrors the legacy announce.js sender.
"""

from __future__ import annotations

import asyncio
import struct
from urllib.parse import urlencode, parse_qs


def build_packet(query: str) -> bytes:
    """Encode a topic query string (must start with '?') into a BYOND packet."""
    body = query.encode("utf-8")
    # 0x0083 = topic export, then big-endian length of everything after these
    # two length bytes (5 pad bytes + body + trailing NUL), 5 pad bytes, body, NUL.
    return b"\x00\x83" + struct.pack(">H", len(body) + 6) + b"\x00" * 5 + body + b"\x00"


def parse_response(data: bytes):
    """Decode a BYOND topic response. Returns a float, str, or None."""
    if len(data) < 5 or data[0:2] != b"\x00\x83":
        return None
    rtype = data[4]
    if rtype == 0x2A:  # float
        return struct.unpack("<f", data[5:9])[0]
    if rtype == 0x06:  # null-terminated string
        end = data.find(b"\x00", 5)
        end = end if end != -1 else len(data)
        return data[5:end].decode("utf-8", errors="replace")
    return None


def build_query(keyword: str, value: str | None = None, **params: str) -> str:
    """Build a url-encoded topic query understood by /world/Topic (params2list)."""
    fields: dict[str, str] = {keyword: "" if value is None else value}
    for key, val in params.items():
        if val is not None:
            fields[key] = val
    return "?" + urlencode(fields)


async def world_topic(host: str, port: int, query: str, timeout: float = 5.0):
    """Open a short-lived TCP connection, send one topic query, return the parsed reply."""
    try:
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(host, port), timeout
        )
    except (OSError, asyncio.TimeoutError):
        return None
    try:
        writer.write(build_packet(query))
        await writer.drain()
        data = await asyncio.wait_for(reader.read(65536), timeout)
    except (OSError, asyncio.TimeoutError):
        return None
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except OSError:
            pass
    return parse_response(data)


async def get_status(host: str, port: int, comms_key: str, timeout: float = 5.0) -> dict | None:
    """Query the 'status' handler and return its fields as a flat dict of strings."""
    raw = await world_topic(host, port, build_query("status", key=comms_key), timeout)
    if not isinstance(raw, str):
        return None
    # status returns list2params output: key=val&key2=val2 (url-encoded)
    return {k: v[0] for k, v in parse_qs(raw, keep_blank_values=True).items()}
