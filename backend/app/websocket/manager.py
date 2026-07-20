"""WebSocket connection manager."""

import asyncio
from typing import Dict
from fastapi import WebSocket


class ConnectionManager:
    def __init__(self):
        self.active_connections: Dict[str, WebSocket] = {}

    async def connect(self, job_id: str, ws: WebSocket):
        await ws.accept()
        self.active_connections[job_id] = ws

    def disconnect(self, job_id: str):
        self.active_connections.pop(job_id, None)

    async def send(self, job_id: str, data: dict):
        ws = self.active_connections.get(job_id)
        if ws:
            try:
                await ws.send_json(data)
            except Exception:
                self.disconnect(job_id)


manager = ConnectionManager()
