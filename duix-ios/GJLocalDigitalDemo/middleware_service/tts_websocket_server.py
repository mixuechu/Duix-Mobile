#!/usr/bin/env python3
"""
WebSocket TTS 服务器
提供流式文本转语音服务，客户端可以通过WebSocket连接发送文本，实时接收音频数据
"""

import asyncio
import json
import logging
import time
import uuid
import websockets
from websockets.server import WebSocketServerProtocol
from typing import Dict, Any, Optional
import os

from protocols import (
    EventType,
    MsgType,
    finish_connection,
    finish_session,
    receive_message,
    start_connection,
    start_session,
    task_request,
    wait_for_event,
)

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


class TTSWebSocketServer:
    def __init__(self, host: str = "localhost", port: int = 8765):
        self.host = host
        self.port = port
        self.clients: Dict[WebSocketServerProtocol, Dict[str, Any]] = {}
        
        # 火山引擎配置
        self.appid = "3549748956"
        self.access_token = "wwooHO7HA6pCVuHvRF6kLaOPB9NGUs1K"
        self.endpoint = "wss://openspeech.bytedance.com/api/v3/tts/bidirection"

    def get_resource_id(self, voice: str) -> str:
        """根据声音类型获取资源ID"""
        if voice.startswith("S_"):
            return "volc.megatts.default"
        return "volc.service_type.10029"

    async def register_client(self, websocket: WebSocketServerProtocol):
        """注册新客户端"""
        client_id = str(uuid.uuid4())
        self.clients[websocket] = {
            "id": client_id,
            "connected_at": time.time(),
            "volc_websocket": None
        }
        logger.info(f"Client {client_id} connected from {websocket.remote_address}")

    async def unregister_client(self, websocket: WebSocketServerProtocol):
        """注销客户端"""
        if websocket in self.clients:
            client_info = self.clients[websocket]
            client_id = client_info["id"]
            
            # 关闭与火山引擎的连接
            if client_info.get("volc_websocket"):
                try:
                    await client_info["volc_websocket"].close()
                except:
                    pass
            
            del self.clients[websocket]
            logger.info(f"Client {client_id} disconnected")

    async def connect_to_volc(self, websocket: WebSocketServerProtocol, voice_type: str = "zh_female_cancan_mars_bigtts") -> bool:
        """为客户端建立与火山引擎的连接"""
        try:
            client_info = self.clients[websocket]
            
            # 连接火山引擎
            headers = {
                "X-Api-App-Key": self.appid,
                "X-Api-Access-Key": self.access_token,
                "X-Api-Resource-Id": self.get_resource_id(voice_type),
                "X-Api-Connect-Id": str(uuid.uuid4()),
            }
            
            volc_websocket = await websockets.connect(
                self.endpoint,
                extra_headers=headers,
                max_size=10 * 1024 * 1024,
                ping_interval=None,
                ping_timeout=None,
            )
            
            client_info["volc_websocket"] = volc_websocket
            
            # 启动连接
            await start_connection(volc_websocket)
            
            # 等待连接建立
            await wait_for_event(volc_websocket, MsgType.FullServerResponse, EventType.ConnectionStarted)
            
            logger.info(f"Connected to Volcano Engine for client {client_info['id']}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to connect to Volcano Engine: {e}")
            return False

    async def handle_tts_request(self, websocket: WebSocketServerProtocol, message: Dict[str, Any]):
        """处理TTS请求"""
        try:
            client_info = self.clients[websocket]
            client_id = client_info["id"]
            volc_websocket = client_info.get("volc_websocket")
            
            text = message.get("text", "")
            voice_type = message.get("voice_type", "zh_female_cancan_mars_bigtts")
            encoding = message.get("encoding", "pcm")
            
            if not text:
                await websocket.send(json.dumps({
                    "type": "error",
                    "message": "Text is required"
                }))
                return
            
            # 如果没有连接或声音类型改变，重新连接
            if not volc_websocket or client_info.get("last_voice_type") != voice_type:
                if volc_websocket:
                    await volc_websocket.close()
                
                if not await self.connect_to_volc(websocket, voice_type):
                    await websocket.send(json.dumps({
                        "type": "error",
                        "message": "Failed to connect to TTS service"
                    }))
                    return
                
                volc_websocket = client_info["volc_websocket"]
                client_info["last_voice_type"] = voice_type
            
            # 开始会话
            session_id = str(uuid.uuid4())
            client_info["session_active"] = True
            
            base_request = {
                "user": {
                    "uid": str(uuid.uuid4()),
                },
                "namespace": "BidirectionalTTS",
                "req_params": {
                    "speaker": voice_type,
                    "audio_params": {
                        "format": "pcm",
                        "sample_rate": 16000,
                        "bit_rate": 16000,
                        "enable_timestamp": True,
                    },
                }
            }
            
            logger.info(f"Starting new session {session_id} for client {client_id}")
            await start_session(volc_websocket, json.dumps(base_request).encode('utf-8'), session_id)
            
            # 等待会话启动
            await wait_for_event(volc_websocket, MsgType.FullServerResponse, EventType.SessionStarted)
            
            # 构建合成请求
            import copy
            synthesis_request = copy.deepcopy(base_request)
            synthesis_request["event"] = EventType.TaskRequest
            synthesis_request["req_params"]["text"] = text
            
            # 发送任务请求
            await task_request(volc_websocket, json.dumps(synthesis_request).encode('utf-8'), session_id)
            
            # 通知客户端开始接收音频
            await websocket.send(json.dumps({
                "type": "tts_start",
                "session_id": session_id,
                "text": text,
                "voice_type": voice_type
            }))
            
            # 接收并转发音频数据
            audio_received = False
            while True:
                try:
                    msg = await receive_message(volc_websocket)
                    
                    if msg.type == MsgType.AudioOnlyServer and msg.event == EventType.TTSResponse:
                        # 发送音频数据
                        import base64
                        # 确保payload是bytes类型
                        if isinstance(msg.payload, str):
                            payload_bytes = msg.payload.encode('utf-8')
                        else:
                            payload_bytes = msg.payload
                        audio_data = base64.b64encode(payload_bytes).decode('utf-8')
                        await websocket.send(json.dumps({
                            "type": "audio_chunk",
                            "session_id": session_id,
                            "audio_data": audio_data,
                            "timestamp": int(time.time() * 1000)
                        }))
                        audio_received = True
                        
                    elif msg.type == MsgType.FullServerResponse:
                        if msg.event == EventType.TTSSentenceEnd:
                            # 句子结束
                            await websocket.send(json.dumps({
                                "type": "sentence_end",
                                "session_id": session_id
                            }))
                            
                        elif msg.event == EventType.TTSEnded:
                            # TTS结束
                            await websocket.send(json.dumps({
                                "type": "tts_complete",
                                "session_id": session_id
                            }))
                            break
                            
                        elif msg.event == EventType.SessionFinished:
                            # 会话完成
                            await websocket.send(json.dumps({
                                "type": "tts_complete",
                                "session_id": session_id
                            }))
                            break
                            

                            
                except Exception as e:
                    logger.error(f"Error receiving from Volcano: {e}")
                    break
            
            # 结束会话
            try:
                await finish_session(volc_websocket, session_id)
                await wait_for_event(volc_websocket, MsgType.FullServerResponse, EventType.SessionFinished)
            except Exception as e:
                logger.warning(f"Error finishing session: {e}")
            
            # 重置客户端状态，准备下一次请求
            client_info["session_active"] = False
            
            if not audio_received:
                await websocket.send(json.dumps({
                    "type": "error",
                    "message": "No audio data received"
                }))
                
        except Exception as e:
            import traceback
            logger.error(f"Error handling TTS request: {e}")
            logger.error(f"Traceback: {traceback.format_exc()}")
            await websocket.send(json.dumps({
                "type": "error",
                "message": f"TTS processing failed: {str(e)}"
            }))

    async def handle_client_message(self, websocket: WebSocketServerProtocol, message: str):
        """处理客户端消息"""
        try:
            data = json.loads(message)
            msg_type = data.get("type")
            
            if msg_type == "tts_request":
                await self.handle_tts_request(websocket, data)
            elif msg_type == "ping":
                await websocket.send(json.dumps({"type": "pong"}))
            else:
                await websocket.send(json.dumps({
                    "type": "error",
                    "message": f"Unknown message type: {msg_type}"
                }))
                
        except json.JSONDecodeError:
            await websocket.send(json.dumps({
                "type": "error",
                "message": "Invalid JSON format"
            }))
        except Exception as e:
            logger.error(f"Error handling client message: {e}")
            await websocket.send(json.dumps({
                "type": "error",
                "message": "Message processing failed"
            }))

    async def handle_client(self, websocket: WebSocketServerProtocol, path: str):
        """处理客户端连接"""
        await self.register_client(websocket)
        
        try:
            # 发送欢迎消息
            await websocket.send(json.dumps({
                "type": "welcome",
                "message": "Connected to TTS WebSocket Server",
                "client_id": self.clients[websocket]["id"]
            }))
            
            async for message in websocket:
                await self.handle_client_message(websocket, message)
                
        except websockets.exceptions.ConnectionClosed:
            logger.info("Client connection closed")
        except Exception as e:
            logger.error(f"Error in client handler: {e}")
        finally:
            await self.unregister_client(websocket)

    async def start_server(self):
        """启动WebSocket服务器"""
        logger.info(f"Starting TTS WebSocket server on {self.host}:{self.port}")
        
        async with websockets.serve(
            self.handle_client,
            self.host,
            self.port,
            ping_interval=30,
            ping_timeout=10,
            max_size=10**7,  # 10MB max message size
        ):
            logger.info(f"TTS WebSocket server running on ws://{self.host}:{self.port}")
            await asyncio.Future()  # Run forever


async def main():
    """主函数"""
    import argparse
    
    parser = argparse.ArgumentParser(description="TTS WebSocket Server")
    parser.add_argument("--host", default="localhost", help="Server host")
    parser.add_argument("--port", type=int, default=8765, help="Server port")
    
    args = parser.parse_args()
    
    server = TTSWebSocketServer(args.host, args.port)
    
    try:
        await server.start_server()
    except KeyboardInterrupt:
        logger.info("Server stopped by user")
    except Exception as e:
        logger.error(f"Server error: {e}")


if __name__ == "__main__":
    asyncio.run(main()) 