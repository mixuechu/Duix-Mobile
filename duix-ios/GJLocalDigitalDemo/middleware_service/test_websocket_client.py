#!/usr/bin/env python3
"""
WebSocket TTS 客户端测试脚本
用于测试TTS WebSocket服务器的功能
"""

import asyncio
import json
import websockets
import base64
import wave
import os


async def save_audio_chunks(chunks, filename):
    """将音频块保存为WAV文件"""
    if not chunks:
        print("No audio chunks to save")
        return
    
    # 合并所有音频数据
    all_audio_data = b""
    for chunk in chunks:
        try:
            audio_data = base64.b64decode(chunk)
            all_audio_data += audio_data
        except Exception as e:
            print(f"Error decoding audio chunk: {e}")
    
    # 保存为WAV文件
    with wave.open(filename, 'wb') as wav_file:
        wav_file.setnchannels(1)  # 单声道
        wav_file.setsampwidth(2)  # 16位
        wav_file.setframerate(16000)  # 16kHz
        wav_file.writeframes(all_audio_data)
    
    print(f"Audio saved to: {filename}")


async def test_tts_client():
    """测试TTS客户端"""
    uri = "ws://localhost:8765"
    
    try:
        async with websockets.connect(uri) as websocket:
            print(f"Connected to TTS server at {uri}")
            
            # 接收欢迎消息
            welcome_msg = await websocket.recv()
            welcome_data = json.loads(welcome_msg)
            print(f"Welcome: {welcome_data}")
            
            # 测试文本列表
            test_texts = [
                "你好，这是一个测试。",
                "今天天气真不错，适合出去走走。",
                "人工智能技术正在快速发展，改变着我们的生活。"
            ]
            
            for i, text in enumerate(test_texts):
                print(f"\n--- Testing text {i+1}: {text} ---")
                
                # 发送TTS请求
                tts_request = {
                    "type": "tts_request",
                    "text": text,
                    "voice_type": "zh_female_cancan_mars_bigtts",
                    "encoding": "pcm"
                }
                
                await websocket.send(json.dumps(tts_request))
                print(f"Sent TTS request: {text}")
                
                # 接收响应
                audio_chunks = []
                session_id = None
                
                while True:
                    try:
                        response = await websocket.recv()
                        data = json.loads(response)
                        
                        msg_type = data.get("type")
                        
                        if msg_type == "tts_start":
                            session_id = data.get("session_id")
                            print(f"TTS started, session: {session_id}")
                            
                        elif msg_type == "audio_chunk":
                            audio_data = data.get("audio_data")
                            timestamp = data.get("timestamp", 0)
                            audio_chunks.append(audio_data)
                            print(f"Received audio chunk (timestamp: {timestamp})")
                            
                        elif msg_type == "sentence_end":
                            print("Sentence ended")
                            
                        elif msg_type == "tts_complete":
                            print("TTS completed")
                            break
                            
                        elif msg_type == "error":
                            print(f"Error: {data.get('message')}")
                            break
                            
                        else:
                            print(f"Unknown message type: {msg_type}")
                            
                    except websockets.ConnectionClosed:
                        print("Connection closed")
                        break
                    except Exception as e:
                        print(f"Error receiving message: {e}")
                        break
                
                # 保存音频文件
                if audio_chunks:
                    output_dir = "output_audio"
                    os.makedirs(output_dir, exist_ok=True)
                    filename = f"{output_dir}/test_output_{i+1}.wav"
                    await save_audio_chunks(audio_chunks, filename)
                else:
                    print("No audio data received")
                
                # 等待一下再发送下一个请求
                await asyncio.sleep(1)
            
            print("\n--- Testing ping ---")
            await websocket.send(json.dumps({"type": "ping"}))
            pong_response = await websocket.recv()
            pong_data = json.loads(pong_response)
            print(f"Ping response: {pong_data}")
            
    except ConnectionRefusedError:
        print("Failed to connect to server. Make sure the server is running.")
    except Exception as e:
        print(f"Error: {e}")


async def main():
    """主函数"""
    print("TTS WebSocket Client Test")
    print("=" * 50)
    
    try:
        await test_tts_client()
    except KeyboardInterrupt:
        print("\nTest interrupted by user")
    except Exception as e:
        print(f"Test failed: {e}")


if __name__ == "__main__":
    asyncio.run(main()) 