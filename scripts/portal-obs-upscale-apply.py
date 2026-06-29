"""
Apply the NVIDIA RTX Super Resolution 2x filter chain to a named OBS source.

Connects to OBS via the obs-websocket 5.x protocol, creates two filters in
order on the named source, and reports what was applied. Idempotent: running
twice does not duplicate filters.

The filter chain (see docs/keeping-portal-alive.md#upscale):
  1. NVIDIA Artefact Reduction
  2. NVIDIA Super Resolution (2x)

The script does not enable obs-websocket by itself - that is a one-time OBS
Settings toggle; see obsproject.com/obswebsocket.

SECURITY: the password is sent over the wire in plaintext because v5 plain
ws:// has no TLS build on OBS Studio. Use this only against localhost
(127.0.0.1). A non-default --host is overridden to refuse.

Requires: Python 3.10+ (uses PEP 604 union syntax).

Usage:
  python3 portal-obs-upscale-apply.py \\
      --host 127.0.0.1 --port 4455 --password <secret> \\
      --source "PortalCam" [--scene "Scene"]

Exit codes:
  0 = applied (or already present)
  1 = connection / negotiation failure
  2 = source not found
  3 = filter creation rejected
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from typing import Any

import websocket  # type: ignore[import-untyped]

FILTER_ARTEFACT = "NVIDIA Artefact Reduction"
FILTER_SUPERRES = "NVIDIA Super Resolution"
REQUEST_TIMEOUT = 10.0

# obs-websocket v5 numeric error codes we care about.
OBS_ERR_SOURCE_NOT_FOUND = 600
OBS_ERR_NO_SOURCE = 600  # alias used by some plugin backends
LOCALHOST_NAMES = {"127.0.0.1", "localhost", "::1"}


class _ObsRpcError(RuntimeError):
    def __init__(self, method: str, code: int | None, comment: str) -> None:
        self.method = method
        self.code = code
        self.comment = comment
        super().__init__(f"obs-websocket RPC {method} failed (code={code}): {comment}")


def _rpc(ws: "websocket.WebSocket", method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
    """Send one obs-websocket v5 RPC and return the response data dict."""
    payload = {
        "op": 6,
        "d": {"requestType": method, "requestData": params or {}, "requestId": str(int(time.time() * 1000))},
    }
    ws.send(json.dumps(payload))
    while True:
        msg = json.loads(ws.recv())
        if msg.get("op") == 7:
            data = msg.get("d", {})
            status = data.get("requestStatus", {})
            if status.get("result"):
                return data
            raise _ObsRpcError(method, status.get("code"), status.get("comment", ""))


def _list_filters(ws: "websocket.WebSocket", source: str) -> list[dict[str, Any]]:
    return _rpc(ws, "GetSourceFilters", {"sourceName": source}).get("filters", [])


def _filter_kind_for(ws: "websocket.WebSocket", source: str, display_name: str) -> str | None:
    """Resolve an OBS display name to its kind id, via GetSourceFilterKindList."""
    kind_list = _rpc(ws, "GetSourceFilterKindList", {"sourceName": source})
    kinds = {k.get("name"): k.get("type") for k in kind_list.get("sourceFilterKinds", [])}
    if display_name in kinds:
        return kinds[display_name]
    lowered = display_name.lower()
    for name, kind in kinds.items():
        if name and lowered in name.lower():
            return kind
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=4455)
    parser.add_argument("--password", default="")
    parser.add_argument("--source", required=True, help="OBS source name to attach filters to")
    parser.add_argument("--scene", default=None, help="OBS scene name (informational only)")
    args = parser.parse_args()

    # SECURITY: refuse non-localhost unless the user explicitly opts in via
    # TELEPORT_PORTAL_OBS_ALLOW_REMOTE=1. Plain ws:// leaks the password.
    if args.host not in LOCALHOST_NAMES and not os.environ.get("TELEPORT_PORTAL_OBS_ALLOW_REMOTE"):
        print(
            f"ERROR: --host {args.host} is non-localhost. Plain ws:// would leak the password. "
            f"Set TELEPORT_PORTAL_OBS_ALLOW_REMOTE=1 to override this guard.",
            file=sys.stderr,
        )
        return 1

    url = f"ws://{args.host}:{args.port}"
    try:
        ws = websocket.create_connection(url, timeout=REQUEST_TIMEOUT)
    except Exception as e:
        print(f"ERROR: cannot connect to obs-websocket at {url}: {e}", file=sys.stderr)
        return 1

    # Negotiate Hello / Identify (obs-websocket v5)
    hello = json.loads(ws.recv())
    if hello.get("op") != 0:
        print(f"ERROR: expected op 0 (Hello), got {hello}", file=sys.stderr)
        return 1
    identify = {
        "op": 1,
        "d": {
            "rpcVersion": 1,
            "authentication": ({"password": args.password} if args.password else None),
        },
    }
    ws.send(json.dumps(identify))
    identified = json.loads(ws.recv())
    if identified.get("op") != 2:
        print(f"ERROR: expected op 2 (Identified), got {identified}", file=sys.stderr)
        return 1

    # Sanity-check the named source exists.
    try:
        _rpc(ws, "GetSourceSettings", {"sourceName": args.source})
    except _ObsRpcError as e:
        if e.method == "GetSourceSettings" and e.code in (OBS_ERR_SOURCE_NOT_FOUND, OBS_ERR_NO_SOURCE):
            print(
                f"ERROR: source '{args.source}' not found in OBS. Open OBS, create it, and re-run.",
                file=sys.stderr,
            )
            return 2
        raise

    existing = {f.get("filterName") for f in _list_filters(ws, args.source)}
    print(f"== Existing filters on '{args.source}': {sorted(existing) if existing else 'none'}")

    applied: list[str] = []
    skipped: list[str] = []
    for display_name in (FILTER_ARTEFACT, FILTER_SUPERRES):
        if display_name in existing:
            skipped.append(display_name)
            continue
        kind = _filter_kind_for(ws, args.source, display_name)
        if not kind:
            print(
                f"WARNING: filter kind for '{display_name}' not found by name; the OBS RTX Super "
                f"Resolution plugin (https://github.com/Bemjo/OBS-RTX-SuperResolution) may not "
                f"be installed. Skipping.",
                file=sys.stderr,
            )
            continue
        try:
            _rpc(
                ws,
                "CreateSourceFilter",
                {
                    "sourceName": args.source,
                    "filterName": display_name,
                    "filterKind": kind,
                    "filterSettings": (
                        {"scale": 2.0, "sharpness": 0.20} if display_name == FILTER_SUPERRES else {}
                    ),
                },
            )
            applied.append(display_name)
        except _ObsRpcError as e:
            print(f"ERROR: CreateSourceFilter '{display_name}' failed: {e}", file=sys.stderr)
            return 3

    print(f"== Applied: {applied or 'none new'}")
    print(f"== Skipped (already present): {skipped}")
    print("== Done. The NVIDIA filter chain is now attached to the source in OBS.")
    ws.close()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("interrupted", file=sys.stderr)
        sys.exit(130)
