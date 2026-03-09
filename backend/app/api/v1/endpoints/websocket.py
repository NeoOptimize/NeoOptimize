from collections import defaultdict

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

router = APIRouter()


class ConnectionManager:
    def __init__(self) -> None:
        self._connections: dict[str, set[WebSocket]] = defaultdict(set)

    async def connect(self, client_id: str, websocket: WebSocket) -> None:
        await websocket.accept()
        self._connections[client_id].add(websocket)

    def disconnect(self, client_id: str, websocket: WebSocket) -> None:
        if client_id in self._connections:
            self._connections[client_id].discard(websocket)
            if not self._connections[client_id]:
                self._connections.pop(client_id, None)

    async def broadcast(self, client_id: str, payload: dict[str, object]) -> None:
        for connection in list(self._connections.get(client_id, set())):
            await connection.send_json(payload)


manager = ConnectionManager()


@router.websocket("/clients/{client_id}")
async def client_channel(websocket: WebSocket, client_id: str) -> None:
    await manager.connect(client_id, websocket)

    try:
        while True:
            payload = await websocket.receive_json()
            await websocket.send_json(
                {
                    "type": "ack",
                    "client_id": client_id,
                    "received": payload,
                }
            )
    except WebSocketDisconnect:
        manager.disconnect(client_id, websocket)
