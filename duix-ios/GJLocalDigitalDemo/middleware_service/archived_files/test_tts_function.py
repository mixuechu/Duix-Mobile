#!/usr/bin/env python3
"""
测试simple_tts_test函数
"""

import asyncio
import json
import logging
import time
import uuid
import websockets
import base64

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
                logger.info(f"收到消息: {msg.type}, 事件: {getattr(msg, 'event', 'N/A')}")
                
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


async def main():
    """主函数"""
    text = "你好"
    print(f"测试文本: {text}")
    
    audio_chunks = await simple_tts_test(text)
    
    print(f"收到 {len(audio_chunks)} 个音频块")
    
    if audio_chunks:
        # 保存音频文件
        import wave
        all_audio_data = b""
        for chunk in audio_chunks:
            audio_data = base64.b64decode(chunk)
            all_audio_data += audio_data
        
        filename = "function_test_output.wav"
        with wave.open(filename, 'wb') as wav_file:
            wav_file.setnchannels(1)
            wav_file.setsampwidth(2)
            wav_file.setframerate(16000)
            wav_file.writeframes(all_audio_data)
        
        print(f"音频保存到: {filename}, 大小: {len(all_audio_data)} bytes")
    else:
        print("没有收到音频数据")


if __name__ == "__main__":
    asyncio.run(main())
