#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import asyncio
import websockets
import json
import base64
import time
import os
from datetime import datetime

class TTSTestClient:
    def __init__(self, websocket_url):
        self.websocket_url = websocket_url
        self.websocket = None
        
    async def connect(self):
        """连接到WebSocket服务"""
        try:
            print(f"🔌 正在连接到: {self.websocket_url}")
            self.websocket = await websockets.connect(
                self.websocket_url,
                ping_interval=30,
                ping_timeout=10,
                close_timeout=10
            )
            print("✅ WebSocket连接成功!")
            return True
        except Exception as e:
            print(f"❌ 连接失败: {e}")
            return False
    
    async def send_tts_request(self, text, voice_id="zh_female_shuangkuaisisi_moon_bigtts"):
        """发送TTS请求"""
        if not self.websocket:
            print("❌ WebSocket未连接")
            return None
            
        request = {
            "type": "tts_request",
            "text": text,
            "voice_type": voice_id,
            "session_id": f"test_session_{int(time.time())}"
        }
        
        try:
            print(f"📤 发送TTS请求: {text[:50]}...")
            await self.websocket.send(json.dumps(request))
            print("✅ TTS请求已发送")
            return True
                
        except Exception as e:
            print(f"❌ 发送请求失败: {e}")
            return False
    
    async def save_audio(self, audio_base64, filename=None):
        """保存音频文件"""
        if not filename:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"test_audio_{timestamp}.wav"
        
        try:
            audio_data = base64.b64decode(audio_base64)
            
            # 确保输出目录存在
            output_dir = "test_output"
            os.makedirs(output_dir, exist_ok=True)
            
            filepath = os.path.join(output_dir, filename)
            with open(filepath, 'wb') as f:
                f.write(audio_data)
            
            print(f"🎵 音频文件已保存: {filepath}")
            print(f"📊 文件大小: {len(audio_data)} bytes")
            return filepath
        except Exception as e:
            print(f"❌ 保存音频失败: {e}")
            return None
    
    async def test_connection(self):
        """测试连接"""
        if await self.connect():
            try:
                # 先接收welcome消息
                welcome_response = await asyncio.wait_for(self.websocket.recv(), timeout=5)
                welcome_data = json.loads(welcome_response)
                print(f"📥 Welcome: {welcome_data.get('message', '')}")
                
                # 发送ping测试
                ping_request = {"type": "ping"}
                await self.websocket.send(json.dumps(ping_request))
                
                response = await asyncio.wait_for(self.websocket.recv(), timeout=5)
                response_data = json.loads(response)
                
                if response_data.get("type") == "pong":
                    print("🏓 Ping测试成功!")
                    return True
                else:
                    print("❌ Ping测试失败")
                    return False
            except Exception as e:
                print(f"❌ 连接测试失败: {e}")
                return False
        return False
    
    async def close(self):
        """关闭连接"""
        if self.websocket:
            await self.websocket.close()
            print("🔌 WebSocket连接已关闭")

async def main():
    # 使用Cloudflare隧道的URL
    websocket_url = "wss://valley-matched-constitute-shore.trycloudflare.com"
    
    client = TTSTestClient(websocket_url)
    
    try:
        print("🚀 TTS WebSocket 客户端测试")
        print("=" * 50)
        
        # 测试连接
        if not await client.test_connection():
            print("❌ 连接测试失败，退出")
            return
        
        # 测试文本列表 (只使用中文，因为配置的是中文语音)
        test_texts = [
            "你好，这是一个测试音频。",
            "今天天气很好，适合出门散步。", 
            "欢迎使用我们的TTS服务！",
            "这是最后一个测试文本。"
        ]
        
        print("\n🎯 开始TTS测试...")
        print("-" * 30)
        
        for i, text in enumerate(test_texts, 1):
            print(f"\n📝 测试 {i}/{len(test_texts)}: {text}")
            
            # 发送TTS请求
            if not await client.send_tts_request(text):
                print(f"❌ 测试 {i} 发送失败")
                continue
            
            # 处理可能的多个响应（音频块和完成消息）
            audio_chunks = []
            session_id = None
            completed = False
            
            while True:
                try:
                    response = await asyncio.wait_for(client.websocket.recv(), timeout=10)
                    response_data = json.loads(response)
                    
                    if response_data.get("type") == "audio_chunk":
                        session_id = response_data.get("session_id")
                        audio_chunks.append(response_data.get("audio_data"))
                        print(f"📦 收到音频块: {len(response_data.get('audio_data', ''))} bytes")
                        
                    elif response_data.get("type") == "tts_complete":
                        print("✅ TTS完成")
                        completed = True
                        break
                        
                    elif response_data.get("type") == "sentence_end":
                        print("✅ 句子完成")
                        completed = True
                        break
                        
                    elif response_data.get("type") == "error":
                        print(f"❌ 服务器错误: {response_data.get('message', '未知错误')}")
                        break
                        
                except asyncio.TimeoutError:
                    print("⏰ 等待响应超时")
                    break
                except Exception as e:
                    print(f"❌ 处理响应失败: {e}")
                    break
            
            # 合并音频块并保存
            if audio_chunks and completed:
                # 合并所有音频块
                import base64
                combined_audio = b""
                for chunk in audio_chunks:
                    combined_audio += base64.b64decode(chunk)
                
                # 保存合并的音频
                filename = f"test_{i}_{int(time.time())}.wav"
                filepath = os.path.join("test_output", filename)
                os.makedirs("test_output", exist_ok=True)
                
                with open(filepath, 'wb') as f:
                    f.write(combined_audio)
                
                print(f"✅ 测试 {i} 成功! 文件: {filepath} ({len(combined_audio)} bytes)")
            else:
                print(f"❌ 测试 {i} 失败: 音频数据不完整")
            
            # 添加小延迟
            await asyncio.sleep(1)
        
        print("\n🎉 所有测试完成!")
        
    except KeyboardInterrupt:
        print("\n\n⏹️ 用户中断测试")
    except Exception as e:
        print(f"\n❌ 测试过程中出错: {e}")
    finally:
        await client.close()

if __name__ == "__main__":
    asyncio.run(main()) 