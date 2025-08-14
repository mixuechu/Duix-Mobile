#!/usr/bin/env python3
import asyncio
import websockets
import json

async def test_websocket():
    uri = "wss://valley-matched-constitute-shore.trycloudflare.com"
    
    try:
        print(f"🔌 连接到: {uri}")
        async with websockets.connect(uri) as websocket:
            print("✅ 连接成功!")
            
            # 先接收welcome消息
            print("⏳ 等待welcome消息...")
            welcome_response = await asyncio.wait_for(websocket.recv(), timeout=5)
            print(f"📥 Welcome: {welcome_response}")
            
            # 测试ping
            print("📤 发送ping...")
            await websocket.send(json.dumps({"type": "ping"}))
            
            print("⏳ 等待ping响应...")
            ping_response = await asyncio.wait_for(websocket.recv(), timeout=5)
            print(f"📥 Ping响应: {ping_response}")
            
            response_data = json.loads(ping_response)
            if response_data.get("type") == "pong":
                print("🏓 Ping测试成功!")
                
                # 测试TTS请求
                print("\n📤 发送TTS请求...")
                tts_request = {
                    "type": "tts_request",
                    "text": "你好，这是一个测试。",
                    "voice_type": "zh_female_cancan_mars_bigtts",
                    "session_id": "test_session_123"
                }
                await websocket.send(json.dumps(tts_request))
                
                print("⏳ 等待TTS响应...")
                while True:
                    try:
                        response = await asyncio.wait_for(websocket.recv(), timeout=15)
                        response_data = json.loads(response)
                        
                        print(f"📥 收到: {response_data.get('type')}")
                        
                        if response_data.get("type") == "audio_chunk":
                            print(f"📦 音频块大小: {len(response_data.get('audio_data', ''))}")
                        elif response_data.get("type") == "tts_complete":
                            print("✅ TTS完成!")
                            break
                        elif response_data.get("type") == "error":
                            print(f"❌ 错误: {response_data.get('message')}")
                            break
                            
                    except asyncio.TimeoutError:
                        print("⏰ 超时")
                        break
            else:
                print("❌ Ping失败")
                
    except Exception as e:
        print(f"❌ 错误: {e}")

if __name__ == "__main__":
    asyncio.run(test_websocket()) 