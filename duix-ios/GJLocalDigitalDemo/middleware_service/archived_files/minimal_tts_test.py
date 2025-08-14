#!/usr/bin/env python3
"""
最小化TTS测试
直接基于同事脚本的架构
"""

import asyncio
import json
import logging
import uuid
import websockets
import struct

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

async def build_binary_frame(message_type, serialization, event, session_id, payload):
    """构建二进制帧"""
    try:
        # 协议版本1，头大小1
        header = bytearray(4)
        header[0] = (1 << 4) | 1  # 协议版本 1, 头大小 1
        header[1] = (message_type << 4) | 0  # 消息类型，标志位0
        header[2] = (serialization << 4) | 0  # 序列化类型，压缩0
        header[3] = 0  # 保留

        # Event number (4 bytes, big endian)
        event_bytes = struct.pack('>I', event)
        
        # Session ID (36 bytes UUID string)
        session_bytes = session_id.encode('utf-8')
        
        # Payload JSON
        payload_json = json.dumps(payload, ensure_ascii=False).encode('utf-8')
        
        # 组合所有部分
        frame = header + event_bytes + session_bytes + payload_json
        return frame
        
    except Exception as e:
        logger.error(f"构建二进制帧失败: {e}")
        return None

async def main():
    """最小化测试"""
    print("🚀 开始最小化TTS测试...")
    
    # 连接参数
    app_id = "3549748956"
    access_token = "wwooHO7HA6pCVuHvRF6kLaOPB9NGUs1K"
    endpoint = "wss://openspeech.bytedance.com/api/v3/tts/bidirection"
    
    # 连接头部
    headers = {
        "X-Api-App-Key": app_id,
        "X-Api-Access-Key": access_token,
        "X-Api-Resource-Id": "volc.megatts.default",  # 尝试这个资源ID
        "X-Api-Connect-Id": str(uuid.uuid4()),
    }
    
    logger.info(f"连接到 {endpoint}")
    logger.info(f"头部: {headers}")
    
    try:
        # 建立连接
        websocket = await websockets.connect(
            endpoint, 
            extra_headers=headers, 
            max_size=10 * 1024 * 1024
        )
        logger.info("✅ WebSocket连接成功")
        
        # 1. 发送StartConnection
        start_conn_payload = {}
        start_conn_frame = await build_binary_frame(
            message_type=0x14,  # Full-client request with event number
            serialization=0x10,  # JSON
            event=1,  # StartConnection
            session_id="",  # 空session ID
            payload=start_conn_payload
        )
        
        if start_conn_frame:
            await websocket.send(start_conn_frame)
            logger.info("✅ 已发送StartConnection")
        
        # 等待ConnectionStarted
        logger.info("⏳ 等待ConnectionStarted...")
        response = await websocket.recv()
        logger.info(f"收到响应: {len(response)} bytes")
        logger.info(f"前16字节: {response[:16].hex()}")
        
        # 2. 发送StartSession
        session_id = str(uuid.uuid4())
        start_session_payload = {
            "user": {"uid": str(uuid.uuid4())},
            "namespace": "BidirectionalTTS"
        }
        
        start_session_frame = await build_binary_frame(
            message_type=0x14,
            serialization=0x10,
            event=100,  # StartSession
            session_id=session_id,
            payload=start_session_payload
        )
        
        if start_session_frame:
            await websocket.send(start_session_frame)
            logger.info(f"✅ 已发送StartSession，session_id: {session_id}")
        
        # 等待SessionStarted
        logger.info("⏳ 等待SessionStarted...")
        response = await websocket.recv()
        logger.info(f"收到响应: {len(response)} bytes")
        logger.info(f"前16字节: {response[:16].hex()}")
        
        # 检查是否有错误响应
        try:
            response2 = await asyncio.wait_for(websocket.recv(), timeout=1.0)
            logger.info(f"收到额外响应: {len(response2)} bytes")
            logger.info(f"前16字节: {response2[:16].hex()}")
            
            # 尝试解析错误信息
            if len(response2) > 8:
                try:
                    # 假设格式为 [length][json]
                    if response2[0:4] == b'\x00\x00\x00':
                        json_len = struct.unpack('>I', response2[0:4])[0]
                        json_data = response2[4:4+json_len]
                        error_info = json.loads(json_data.decode('utf-8'))
                        logger.error(f"❌ 服务器错误: {error_info}")
                    else:
                        logger.info(f"原始错误数据: {response2}")
                except Exception as e:
                    logger.warning(f"解析错误响应失败: {e}")
        except asyncio.TimeoutError:
            logger.info("✅ 没有额外响应，继续...")
        
        # 3. 发送文本请求
        text = "你好"
        text_payload = {
            "user": {"uid": str(uuid.uuid4())},
            "namespace": "BidirectionalTTS",
            "req_params": {
                "speaker": "",  # 空speaker
                "audio_params": {
                    "format": "pcm",
                    "sample_rate": 16000,
                    "bit_rate": 16000,
                    "enable_timestamp": True,
                },
                "additions": json.dumps({
                    "disable_markdown_filter": False,
                })
            },
            "text": text
        }
        
        text_frame = await build_binary_frame(
            message_type=0x14,
            serialization=0x10,
            event=300,  # TextRequest
            session_id=session_id,
            payload=text_payload
        )
        
        if text_frame:
            await websocket.send(text_frame)
            logger.info(f"✅ 已发送文本: {text}")
        
        # 等待音频响应
        logger.info("⏳ 等待音频响应...")
        audio_count = 0
        
        for i in range(10):  # 最多等待10个消息
            try:
                response = await asyncio.wait_for(websocket.recv(), timeout=2.0)
                logger.info(f"收到消息 {i+1}: {len(response)} bytes")
                
                if len(response) >= 4:
                    header = response[:4]
                    protocol_version = (header[0] >> 4) & 0x0F
                    header_size = header[0] & 0x0F
                    message_type = (header[1] >> 4) & 0x0F
                    logger.info(f"消息类型: 0x{message_type:02x}")
                    
                    if message_type == 0x0B or message_type == 0x09:
                        # 可能的音频消息
                        if len(response) > 8:
                            audio_data = response[8:]
                            if len(audio_data) > 0:
                                audio_count += 1
                                logger.info(f"🎵 收到音频数据: {len(audio_data)} bytes")
                
            except asyncio.TimeoutError:
                logger.info("等待超时，结束接收")
                break
        
        logger.info(f"✅ 测试完成，共收到 {audio_count} 个音频包")
        await websocket.close()
        
    except Exception as e:
        logger.error(f"❌ 测试失败: {e}")

if __name__ == "__main__":
    asyncio.run(main()) 