# TTS WebSocket API 使用说明

## 概述

这是一个基于WebSocket的文本转语音(TTS)服务，集成了火山引擎TTS API，提供实时流式音频输出。

## 服务器启动

```bash
# 启动服务器
python start_tts_server.py

# 或直接运行服务器
python tts_websocket_server.py --host 0.0.0.0 --port 8765
```

服务器默认监听: `ws://localhost:8765`

## API 接口

### 连接建立

客户端连接成功后会收到欢迎消息：

```json
{
    "type": "welcome",
    "message": "Connected to TTS WebSocket Server",
    "client_id": "uuid-string"
}
```

### TTS 请求

发送文本转语音请求：

```json
{
    "type": "tts_request",
    "text": "要转换的文本内容",
    "voice_type": "zh_female_cancan_mars_bigtts",
    "encoding": "pcm"
}
```

**参数说明:**
- `text`: 必须，要转换的文本
- `voice_type`: 可选，声音类型，默认 "zh_female_cancan_mars_bigtts"
- `encoding`: 可选，音频编码格式，默认 "pcm"

### 服务器响应

#### 1. TTS 开始
```json
{
    "type": "tts_start",
    "session_id": "session-uuid",
    "text": "转换的文本",
    "voice_type": "zh_female_cancan_mars_bigtts"
}
```

#### 2. 音频数据块
```json
{
    "type": "audio_chunk",
    "session_id": "session-uuid",
    "audio_data": "base64-encoded-audio-data",
    "timestamp": 1234567890
}
```

#### 3. 句子结束
```json
{
    "type": "sentence_end",
    "session_id": "session-uuid"
}
```

#### 4. TTS 完成
```json
{
    "type": "tts_complete",
    "session_id": "session-uuid"
}
```

#### 5. 错误信息
```json
{
    "type": "error",
    "message": "错误描述"
}
```

### Ping/Pong

保持连接活跃：

**发送:**
```json
{
    "type": "ping"
}
```

**响应:**
```json
{
    "type": "pong"
}
```

## 音频格式

- **格式**: PCM
- **采样率**: 16000 Hz
- **位深**: 16 bit
- **声道**: 单声道
- **编码**: Base64

## 客户端示例

### Python 客户端

```python
import asyncio
import json
import websockets
import base64
import wave

async def tts_client():
    uri = "ws://localhost:8765"
    
    async with websockets.connect(uri) as websocket:
        # 发送TTS请求
        request = {
            "type": "tts_request",
            "text": "你好，世界！",
            "voice_type": "zh_female_cancan_mars_bigtts"
        }
        await websocket.send(json.dumps(request))
        
        # 接收响应
        audio_chunks = []
        while True:
            response = await websocket.recv()
            data = json.loads(response)
            
            if data["type"] == "audio_chunk":
                audio_chunks.append(data["audio_data"])
            elif data["type"] == "tts_complete":
                break
            elif data["type"] == "error":
                print(f"Error: {data['message']}")
                break
        
        # 保存音频
        if audio_chunks:
            all_audio = b"".join(base64.b64decode(chunk) for chunk in audio_chunks)
            with wave.open("output.wav", "wb") as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(16000)
                wav.writeframes(all_audio)

asyncio.run(tts_client())
```

### JavaScript 客户端

```javascript
const ws = new WebSocket('ws://localhost:8765');

ws.onopen = function() {
    // 发送TTS请求
    const request = {
        type: 'tts_request',
        text: '你好，世界！',
        voice_type: 'zh_female_cancan_mars_bigtts'
    };
    ws.send(JSON.stringify(request));
};

ws.onmessage = function(event) {
    const data = JSON.parse(event.data);
    
    switch(data.type) {
        case 'tts_start':
            console.log('TTS started:', data.session_id);
            break;
        case 'audio_chunk':
            // 处理音频数据
            const audioData = atob(data.audio_data);
            console.log('Received audio chunk');
            break;
        case 'tts_complete':
            console.log('TTS completed');
            break;
        case 'error':
            console.error('Error:', data.message);
            break;
    }
};
```

## 测试

运行测试客户端：

```bash
python test_websocket_client.py
```

这会测试多个文本转换并将结果保存为WAV文件。

## 支持的声音类型

- `zh_female_cancan_mars_bigtts` - 中文女声
- `zh_male_*` - 其他男声（需要检查火山引擎文档）
- `S_*` - MegaTTS声音（需要特殊资源ID）

## 错误处理

常见错误：
- 文本为空
- 连接火山引擎失败
- 音频数据接收失败
- JSON格式错误

## 性能优化

- 服务器为每个客户端维护独立的火山引擎连接
- 支持声音类型切换时自动重连
- 包含连接复用和错误恢复机制

## 安全考虑

- 当前配置包含硬编码的API密钥
- 生产环境应使用环境变量或配置文件
- 建议添加访问控制和速率限制 