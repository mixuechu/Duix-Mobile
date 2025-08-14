#!/usr/bin/env python3
"""
简化的调试版WebSocket TTS服务器
"""

import asyncio
import json
import logging
import time
import uuid
import websockets
import base64
from websockets.server import WebSocketServerProtocol
from typing import Dict, Any

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

logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


async def simple_tts_test(text: str):
    """简单的TTS测试"""
    appid = "3549748956"
    access_token = "wwooHO7HA6pCVuHvRF6kLaOPB9NGUs1K"
    endpoint = "wss://openspeech.bytedance.com/api/v3/tts/bidirection"
    voice_type = "zh_female_cancan_mars_bigtts"
    
    headers = {
        "X-Api-App-Key": appid,
        "X-Api-Access-Key": access_token,
        "X-Api-Resource-Id": "volc.service_type.10029",
        "X-Api-Connect-Id": str(uuid.uuid4()),
    }
    
    try:
        logger.info(f"连接火山引擎: {endpoint}")
        websocket = await websockets.connect(
            endpoint,
            extra_headers=headers,
            max_size=10 * 1024 * 1024,
            ping_interval=None,
            ping_timeout=None,
        )
        
        logger.info("启动连接...")
        await start_connection(websocket)
        await wait_for_event(websocket, MsgType.FullServerResponse, EventType.ConnectionStarted)
        
        logger.info("开始会话...")
        session_id = str(uuid.uuid4())
        base_request = {
            "user": {"uid": str(uuid.uuid4())},
            "namespace": "BidirectionalTTS",
            "req_params": {
                "speaker": voice_type,
                "audio_params": {
                    "format": "pcm",
                    "sample_rate": 16000,
                    "bit_rate": 16000,
                    "enable_timestamp": True,
                },
            },
            "event": EventType.StartSession
        }
        
        await start_session(websocket, json.dumps(base_request).encode(), session_id)
        await wait_for_event(websocket, MsgType.FullServerResponse, EventType.SessionStarted)
        
        logger.info(f"发送文本: {text}")
        
        # 发送每个字符
        import copy
        for char in text:
            synthesis_request = copy.deepcopy(base_request)
            synthesis_request["event"] = EventType.TaskRequest
            synthesis_request["req_params"]["text"] = char
            await task_request(websocket, json.dumps(synthesis_request).encode(), session_id)
            await asyncio.sleep(0.005)  # 5ms delay between characters
        
        # 结束会话发送
        await finish_session(websocket, session_id)
        
        logger.info("接收音频数据...")
        audio_chunks = []
        
        while True:
            try:
                msg = await receive_message(websocket)
                logger.debug(f"收到消息: {msg.type}, 事件: {getattr(msg, 'event', 'N/A')}")
                
                if msg.type == MsgType.AudioOnlyServer:
                    logger.info(f"收到音频数据: {len(msg.payload)} bytes")
                    audio_b64 = base64.b64encode(msg.payload).decode('utf-8')
                    audio_chunks.append(audio_b64)
                    
                elif msg.type == MsgType.FullServerResponse:
                    if msg.event == EventType.SessionFinished:
                        logger.info("会话完成")
                        break
                    # 其他事件继续处理
                        
            except Exception as e:
                logger.error(f"接收消息错误: {e}")
                break
        
        # 会话已经在发送过程中结束了，等待SessionFinished事件
        
        logger.info("关闭连接...")
        await finish_connection(websocket)
        await wait_for_event(websocket, MsgType.FullServerResponse, EventType.ConnectionFinished)
        
        await websocket.close()
        
        return audio_chunks
        
    except Exception as e:
        logger.error(f"TTS测试失败: {e}")
        return []


async def handle_client(websocket: WebSocketServerProtocol, path: str):
    """处理客户端连接"""
    client_id = str(uuid.uuid4())
    logger.info(f"客户端 {client_id} 连接")
    
    try:
        # 发送欢迎消息
        await websocket.send(json.dumps({
            "type": "welcome",
            "client_id": client_id
        }))
        
        async for message in websocket:
            try:
                data = json.loads(message)
                msg_type = data.get("type")
                
                if msg_type == "tts_request":
                    text = data.get("text", "")
                    logger.info(f"收到TTS请求: {text}")
                    
                    # 发送开始消息
                    await websocket.send(json.dumps({
                        "type": "tts_start",
                        "text": text
                    }))
                    
                    # 执行TTS
                    audio_chunks = await simple_tts_test(text)
                    
                    # 发送音频数据
                    for i, chunk in enumerate(audio_chunks):
                        await websocket.send(json.dumps({
                            "type": "audio_chunk",
                            "audio_data": chunk,
                            "chunk_id": i
                        }))
                    
                    # 发送完成消息
                    await websocket.send(json.dumps({
                        "type": "tts_complete",
                        "total_chunks": len(audio_chunks)
                    }))
                    
                elif msg_type == "ping":
                    await websocket.send(json.dumps({"type": "pong"}))
                    
            except json.JSONDecodeError:
                await websocket.send(json.dumps({
                    "type": "error",
                    "message": "Invalid JSON"
                }))
            except Exception as e:
                logger.error(f"处理消息错误: {e}")
                await websocket.send(json.dumps({
                    "type": "error",
                    "message": str(e)
                }))
                
    except websockets.ConnectionClosed:
        logger.info(f"客户端 {client_id} 断开连接")
    except Exception as e:
        logger.error(f"客户端处理错误: {e}")


async def main():
    """启动服务器"""
    host = "localhost"
    port = 8765
    
    logger.info(f"启动调试WebSocket服务器 {host}:{port}")
    
    async with websockets.serve(handle_client, host, port):
        logger.info(f"服务器运行在 ws://{host}:{port}")
        await asyncio.Future()  # Run forever


if __name__ == "__main__":
    asyncio.run(main()) 