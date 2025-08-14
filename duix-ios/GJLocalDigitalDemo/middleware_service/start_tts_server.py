#!/usr/bin/env python3
"""
启动TTS WebSocket服务器
"""

import asyncio
import os
import sys

# 添加当前目录到Python路径
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from tts_websocket_server import TTSWebSocketServer


async def main():
    """启动服务器"""
    print("=" * 60)
    print("🎵 TTS WebSocket Server")
    print("=" * 60)
    print()
    print("服务器功能:")
    print("• 接受WebSocket客户端连接")
    print("• 提供实时文本转语音服务")
    print("• 支持流式音频输出")
    print("• 集成火山引擎TTS API")
    print()
    print("客户端消息格式:")
    print('''
    {
        "type": "tts_request",
        "text": "要转换的文本",
        "voice_type": "zh_female_cancan_mars_bigtts",
        "encoding": "pcm"
    }
    ''')
    print()
    print("服务器响应格式:")
    print("• tts_start: 开始转换")
    print("• audio_chunk: 音频数据块")
    print("• sentence_end: 句子结束")
    print("• tts_complete: 转换完成")
    print("• error: 错误信息")
    print()
    
    # 创建并启动服务器
    server = TTSWebSocketServer(host="0.0.0.0", port=8765)
    
    try:
        print("🚀 Starting server...")
        await server.start_server()
    except KeyboardInterrupt:
        print("\n📱 Server stopped by user")
    except Exception as e:
        print(f"❌ Server error: {e}")


if __name__ == "__main__":
    asyncio.run(main()) 