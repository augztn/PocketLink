"""Remote file operations for Android SAF-backed USB volumes."""
from typing import Literal

from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, UploadFile
from fastapi.responses import StreamingResponse

from app.main import authenticate
from app.services.saf_bridge import bridge_json, open_document_stream, upload_document

router = APIRouter(
    prefix="/api/storage",
    tags=["Storage"],
    dependencies=[Depends(authenticate)],
)
Volume = Literal["usb1", "usb2"]


@router.get("/volumes")
async def list_volumes():
    return await bridge_json("GET", "/v1/volumes")


@router.get("/{volume}/")
async def list_storage_directory(volume: Volume, path: str = Query(default="")):
    return await bridge_json("GET", "/v1/list", params={"volume": volume, "path": path})


@router.put("/{volume}/upload")
async def upload_storage_file(
    volume: Volume, path: str = Query(...), file: UploadFile = File(...)
):
    if not path or path.endswith("/"):
        raise HTTPException(400, "A file path is required")
    try:
        return await upload_document(volume, path, file)
    finally:
        await file.close()


@router.get("/{volume}/download")
async def download_storage_file(
    volume: Volume, request: Request, path: str = Query(...),
):
    response, body = await open_document_stream(
        volume, path, request.headers.get("range")
    )
    headers = {
        key: response.headers[key]
        for key in ("content-range", "accept-ranges", "content-length", "content-type")
        if key in response.headers
    }
    return StreamingResponse(
        body,
        status_code=response.status_code,
        media_type=response.headers.get("content-type", "application/octet-stream"),
        headers=headers,
    )


@router.post("/{volume}/mkdir")
async def create_storage_directory(
    volume: Volume, path: str = Query(default=""), name: str = Query(...),
):
    return await bridge_json(
        "POST", "/v1/mkdir", params={"volume": volume, "path": path, "name": name}
    )


@router.post("/{volume}/rename")
async def rename_storage_item(
    volume: Volume, path: str = Query(...), name: str = Query(...),
):
    return await bridge_json(
        "POST", "/v1/rename", params={"volume": volume, "path": path, "name": name}
    )


@router.delete("/{volume}/item")
async def delete_storage_item(volume: Volume, path: str = Query(...)):
    return await bridge_json(
        "DELETE", "/v1/item", params={"volume": volume, "path": path}
    )
