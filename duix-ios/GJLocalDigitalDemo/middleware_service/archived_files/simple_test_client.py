#!/usr/bin/env python3
"""
简单的WebSocket TTS客户端测试
"""

import asyncio
import json
import websockets
import base64
import wave
import os


async def simple_test():
    """简单测试"""
    uri = "ws://localhost:8765"
    
    try:
        async with websockets.connect(uri) as websocket:
            print(f"连接到服务器: {uri}")
            
            # 接收欢迎消息
            welcome_msg = await websocket.recv()
            welcome_data = json.loads(welcome_msg)
            print(f"欢迎消息: {welcome_data}")
            
            # 发送TTS请求
            text = "你好"
            request = {
                "type": "tts_request",
                "text": text
            }
            
            await websocket.send(json.dumps(request))
            print(f"发送TTS请求: {text}")
            
            # 接收响应
            audio_chunks = []
            
            while True:
                try:
                    response = await websocket.recv()
                    data = json.loads(response)
                    
                    msg_type = data.get("type")
                    print(f"收到消息: {msg_type}")
                    
                    if msg_type == "tts_start":
                        print("TTS开始")
                        
                    elif msg_type == "audio_chunk":
                        audio_data = data.get("audio_data")
                        chunk_id = data.get("chunk_id", 0)
                        print(f"收到音频块 {chunk_id}: {len(audio_data) if audio_data else 0} chars")
                        if audio_data:
                            audio_chunks.append(audio_data)
                        
                    elif msg_type == "tts_complete":
                        total_chunks = data.get("total_chunks", 0)
                        print(f"TTS完成，总块数: {total_chunks}")
                        break
                        
                    elif msg_type == "error":
                        print(f"错误: {data.get('message')}")
                        break
                        
                except Exception as e:
                    print(f"接收消息错误: {e}")
                    break
            
            # 保存音频文件
            if audio_chunks:
                print(f"收到 {len(audio_chunks)} 个音频块")
                
                # 合并音频数据
                all_audio_data = b""
                for chunk in audio_chunks:
                    try:
                        audio_data = base64.b64decode(chunk)
                        all_audio_data += audio_data
                        print(f"解码音频块: {len(audio_data)} bytes")
                    except Exception as e:
                        print(f"解码错误: {e}")
                
                if all_audio_data:
                    # 保存为WAV文件
                    filename = "simple_test_output.wav"
                    with wave.open(filename, 'wb') as wav_file:
                        wav_file.setnchannels(1)  # 单声道
                        wav_file.setsampwidth(2)  # 16位
                        wav_file.setframerate(16000)  # 16kHz
                        wav_file.writeframes(all_audio_data)
                    
                    print(f"音频保存到: {filename}, 大小: {len(all_audio_data)} bytes")
                else:
                    print("没有有效的音频数据")
            else:
                print("没有收到音频数据")
                
    except Exception as e:
        print(f"连接错误: {e}")


if __name__ == "__main__":
    asyncio.run(simple_test())
