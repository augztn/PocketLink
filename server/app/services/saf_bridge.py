"""Authenticated client for the same-device Android SAF bridge."""
from __future__ import annotations

import os
from pathlib import Path
from typing import AsyncIterator

import httpx
from fastapi import HTTPException, UploadFile

BRIDGE_URL = os.getenv("HOMESERVER_SAF_BRIDGE_URL", "http://127.0.0.1:8765").rstrip("/")
TOKEN_FILE = Path(os.getenv("HOMESERVER_SAF_BRIDGE_TOKEN_FILE", "/opt/homeserver/ssd-bridge-token.txt"))


def _token() -> str:
    value = os.getenv("HOMESERVER_SAF_BRIDGE_TOKEN", "").strip()
    if not value and TOKEN_FILE.is_file():
        value = TOKEN_FILE.read_text(encoding="utf-8").strip()
    if not value:
        raise HTTPException(503, "SSD bridge token is not configured")
    return value


def _headers(extra: dict[str, str] | None = None) -> dict[str, str]:
    return {"Authorization": f"Bearer {_token()}", **(extra or {})}


def _raise_bridge_error(response: httpx.Response) -> None:
    if response.is_error:
        try:
            detail = response.json().get("detail", "SSD storage operation failed")
        except Exception:
            detail = "SSD storage operation failed"
        raise HTTPException(response.status_code, detail)


async def bridge_json(method: str, endpoint: str, *, params: dict | None = None) -> dict:
    try:
        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.request(
                method, f"{BRIDGE_URL}{endpoint}", params=params, headers=_headers()
            )
    except httpx.RequestError as error:
        raise HTTPException(503, "Cannot connect to the Android SSD bridge") from error
    _raise_bridge_error(response)
    return response.json()


async def upload_document(volume: str, path: str, upload: UploadFile) -> dict:
    async def chunks() -> AsyncIterator[bytes]:
        while chunk := await upload.read(1024 * 1024):
            yield chunk

    # NanoHTTPD requires a known request length; avoid chunked transfer encoding.
    upload.file.seek(0, os.SEEK_END)
    content_length = upload.file.tell()
    upload.file.seek(0)

    try:
        async with httpx.AsyncClient(timeout=None) as client:
            response = await client.put(
                f"{BRIDGE_URL}/v1/write",
                params={"volume": volume, "path": path},
                content=chunks(),
                headers=_headers({
                    "Content-Type": "application/octet-stream",
                    "Content-Length": str(content_length),
                }),
            )
    except httpx.RequestError as error:
        raise HTTPException(503, "Cannot connect to the Android SSD bridge") from error
    _raise_bridge_error(response)
    return response.json()


async def open_document_stream(volume: str, path: str, range_header: str | None):
    """Return a live bridge response and a generator that closes its resources."""
    client = httpx.AsyncClient(timeout=None)
    headers = _headers({"Range": range_header} if range_header else None)
    request = client.build_request(
        "GET", f"{BRIDGE_URL}/v1/read",
        params={"volume": volume, "path": path}, headers=headers,
    )
    try:
        response = await client.send(request, stream=True)
    except Exception:
        await client.aclose()
        raise HTTPException(503, "Cannot connect to the Android SSD bridge")
    if response.is_error:
        try:
            await response.aread()
            _raise_bridge_error(response)
        finally:
            await response.aclose()
            await client.aclose()
    async def body() -> AsyncIterator[bytes]:
        try:
            async for chunk in response.aiter_bytes():
                yield chunk
        finally:
            await response.aclose()
            await client.aclose()
    return response, body()
