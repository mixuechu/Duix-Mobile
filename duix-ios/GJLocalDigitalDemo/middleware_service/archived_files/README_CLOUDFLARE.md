# 🌐 TTS WebSocket服务 - Cloudflare Tunnel配置指南

## 🎯 功能概述
通过Cloudflare Tunnel将本地TTS WebSocket服务暴露到公网，让iOS设备可以通过公网URL访问。

## 📋 前置条件

### 1. 安装依赖
```bash
# 安装cloudflared (如果未安装)
brew install cloudflared

# 安装Python依赖
pip install websockets volcengine
```

### 2. 配置火山引擎API
确保 `tts_websocket_server.py` 中的火山引擎配置正确：
```python
# 替换为你的实际配置
APP_ID = "your_app_id"
ACCESS_TOKEN = "your_access_token" 
CLUSTER = "volcano_tts"
```

## 🚀 快速启动

### 一键启动服务
```bash
./start_tts_service.sh
```

这个脚本会：
1. ✅ 检查所有依赖
2. ✅ 启动TTS WebSocket服务 (端口8765)
3. ✅ 创建Cloudflare隧道
4. ✅ 显示公网访问URL

## 📱 iOS端配置

启动成功后，你会看到类似输出：
```
🚀 TTS WebSocket服务启动完成！
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📍 本地服务地址: ws://localhost:8765
🌐 公网HTTP地址: https://abc123.trycloudflare.com
🔗 公网WSS地址:  wss://abc123.trycloudflare.com

📱 iOS端配置:
   将WebSocket URL设置为: wss://abc123.trycloudflare.com
```

在iOS代码中使用公网WSS地址：
```swift
let websocketURL = "wss://abc123.trycloudflare.com"
```

## 🧪 测试方法

### 1. 本地测试
```bash
python3 test_websocket_client.py
```

### 2. 公网测试
修改 `test_websocket_client.py` 中的URL：
```python
# 替换为你的实际公网URL
uri = "wss://your-tunnel-url.trycloudflare.com"
```

## 🔧 消息协议

### TTS请求
```json
{
    "type": "tts_request",
    "text": "要转换的文本"
}
```

### 服务器响应
```json
// 连接欢迎
{"type": "welcome", "client_id": "uuid"}

// TTS开始
{"type": "tts_start", "session_id": "session_uuid"}

// 音频数据 (多个)
{"type": "audio_data", "data": "base64_audio", "timestamp": 0}

// TTS完成
{"type": "tts_end"}

// 心跳响应
{"type": "pong"}
```

## ⚠️ 注意事项

1. **临时URL**: Cloudflare隧道URL是临时的，重启后会变化
2. **安全性**: 这是免费的临时隧道，不建议用于生产环境
3. **网络要求**: iOS设备需要能访问公网
4. **流量限制**: Cloudflare有免费额度限制

## 🛠️ 故障排除

### 问题1: cloudflared未安装
```bash
brew install cloudflared
```

### 问题2: Python依赖缺失
```bash
pip install websockets volcengine
```

### 问题3: 端口被占用
脚本会自动处理，或手动清理：
```bash
lsof -ti:8765 | xargs kill -9
```

### 问题4: 隧道启动失败
- 检查网络连接
- 重新运行脚本
- 查看日志: `tail -f logs/cloudflared.log`

### 问题5: iOS连接失败
- 确认使用WSS协议 (wss://)
- 检查URL是否正确
- 验证服务器是否运行

## 📊 监控和日志

### 实时监控
```bash
# 查看隧道日志
tail -f logs/cloudflared.log

# 查看服务器输出
# 直接在启动脚本的终端查看
```

### 服务状态检查
```bash
# 检查端口状态
lsof -i :8765

# 检查进程
ps aux | grep python
ps aux | grep cloudflared
```

## 🎯 生产环境建议

对于生产环境，建议：
1. 使用Cloudflare的付费隧道服务
2. 配置自定义域名
3. 添加SSL证书验证
4. 实现更完善的错误处理和重连机制
5. 添加访问控制和认证

## 🔗 相关链接

- [Cloudflare Tunnel文档](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [WebSocket协议文档](https://tools.ietf.org/html/rfc6455)
- [火山引擎TTS API](https://www.volcengine.com/docs/6561/79824) 