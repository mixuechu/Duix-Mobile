#!/usr/bin/env python3
"""
优化版WebSocket TTS 服务器
使用连接池技术，实现连接复用，大幅提升性能
"""

import asyncio
import json
import logging
import time
import uuid
import websockets
from websockets.server import WebSocketServerProtocol
from typing import Dict, Any, Optional
import os

from protocols import (
    EventType,
    MsgType,
    finish_session,
    receive_message,
    start_session,
    task_request,
    wait_for_event,
)
from tts_connection_pool import TTSConnectionPool

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


class OptimizedTTSWebSocketServer:
    def __init__(self, host: str = "localhost", port: int = 8765):
        self.host = host
        self.port = port
        self.clients: Dict[WebSocketServerProtocol, Dict[str, Any]] = {}
        
        # 初始化连接池
        self.connection_pool = TTSConnectionPool(
            max_connections_per_voice=3,  # 每种声音最多3个连接
            max_total_connections=10      # 总共最多10个连接
        )
        
        # 性能统计
        self.performance_stats = {
            "total_requests": 0,
            "total_response_time": 0,
            "avg_response_time": 0,
            "fastest_response": float('inf'),
            "slowest_response": 0,
        }

    async def register_client(self, websocket: WebSocketServerProtocol):
        """注册新客户端"""
        client_id = str(uuid.uuid4())
        self.clients[websocket] = {
            "id": client_id,
            "connected_at": time.time(),
            "requests_count": 0
        }
        logger.info(f"👤 [CLIENT] {client_id} 已连接 from {websocket.remote_address}")

    async def unregister_client(self, websocket: WebSocketServerProtocol):
        """注销客户端"""
        if websocket in self.clients:
            client_info = self.clients[websocket]
            client_id = client_info["id"]
            requests_count = client_info["requests_count"]
            
            del self.clients[websocket]
            logger.info(f"👋 [CLIENT] {client_id} 已断开 (处理了 {requests_count} 个请求)")

    async def handle_tts_request(self, websocket: WebSocketServerProtocol, message: Dict[str, Any]):
        """处理TTS请求 - 优化版本使用连接池"""
        request_start_time = time.time()
        
        try:
            client_info = self.clients[websocket]
            client_id = client_info["id"]
            
            text = message.get("text", "")
            voice_type = message.get("voice_type", "zh_female_cancan_mars_bigtts")
            encoding = message.get("encoding", "pcm")
            
            if not text:
                await websocket.send(json.dumps({
                    "type": "error",
                    "message": "Text is required"
                }))
                return
            
            logger.info(f"🎯 [TTS] 开始处理请求: client={client_id}, voice={voice_type}, text='{text[:50]}...'")
            
            # 🚀 使用连接池获取连接 - 这里是关键优化点
            async with self.connection_pool.get_connection(voice_type) as pool_connection:
                volc_websocket = pool_connection.websocket
                
                if not volc_websocket or volc_websocket.closed:
                    raise Exception("连接池返回的连接不可用")
                
                # 开始会话
                session_id = str(uuid.uuid4())
                session_start_time = time.time()
                
                base_request = {
                    "user": {
                        "uid": str(uuid.uuid4()),
                    },
                    "namespace": "BidirectionalTTS",
                    "req_params": {
                        "speaker": voice_type,
                        "audio_params": {
                            "format": "pcm",
                            "sample_rate": 16000,
                            "bit_rate": 16000,
                            "enable_timestamp": True,
                        },
                    }
                }
                
                logger.info(f"📡 [SESSION] 启动会话: {session_id}")
                await start_session(volc_websocket, json.dumps(base_request).encode('utf-8'), session_id)
                
                # 等待会话启动
                await wait_for_event(volc_websocket, MsgType.FullServerResponse, EventType.SessionStarted)
                session_time = (time.time() - session_start_time) * 1000
                logger.info(f"⚡ [SESSION] 会话启动完成，耗时: {session_time:.0f}ms")
                
                # 构建合成请求
                import copy
                synthesis_request = copy.deepcopy(base_request)
                synthesis_request["event"] = EventType.TaskRequest
                synthesis_request["req_params"]["text"] = text
                
                # 发送任务请求
                task_start_time = time.time()
                await task_request(volc_websocket, json.dumps(synthesis_request).encode('utf-8'), session_id)
                
                # 通知客户端开始接收音频
                await websocket.send(json.dumps({
                    "type": "tts_start",
                    "session_id": session_id,
                    "text": text,
                    "voice_type": voice_type
                }))
                
                # 接收并转发音频数据
                audio_received = False
                first_audio_time = None
                total_audio_chunks = 0
                
                while True:
                    try:
                        msg = await receive_message(volc_websocket)
                        
                        if msg.type == MsgType.AudioOnlyServer and msg.event == EventType.TTSResponse:
                            # 记录第一个音频包的时间
                            if first_audio_time is None:
                                first_audio_time = time.time()
                                first_audio_latency = (first_audio_time - task_start_time) * 1000
                                logger.info(f"🔊 [AUDIO] 首个音频包到达，延迟: {first_audio_latency:.0f}ms")
                            
                            # 发送音频数据
                            import base64
                            if isinstance(msg.payload, str):
                                payload_bytes = msg.payload.encode('utf-8')
                            else:
                                payload_bytes = msg.payload
                            audio_data = base64.b64encode(payload_bytes).decode('utf-8')
                            
                            await websocket.send(json.dumps({
                                "type": "audio_chunk",
                                "session_id": session_id,
                                "audio_data": audio_data,
                                "timestamp": int(time.time() * 1000)
                            }))
                            
                            audio_received = True
                            total_audio_chunks += 1
                            
                        elif msg.type == MsgType.FullServerResponse:
                            if msg.event == EventType.TTSSentenceEnd:
                                # 句子结束
                                await websocket.send(json.dumps({
                                    "type": "sentence_end",
                                    "session_id": session_id
                                }))
                                
                            elif msg.event == EventType.TTSEnded:
                                # TTS结束
                                await websocket.send(json.dumps({
                                    "type": "tts_complete",
                                    "session_id": session_id
                                }))
                                break
                                
                            elif msg.event == EventType.SessionFinished:
                                # 会话完成
                                await websocket.send(json.dumps({
                                    "type": "tts_complete",
                                    "session_id": session_id
                                }))
                                break
                                
                    except Exception as e:
                        logger.error(f"❌ [AUDIO] 接收音频异常: {e}")
                        break
                
                # 结束会话
                try:
                    await finish_session(volc_websocket, session_id)
                    await wait_for_event(volc_websocket, MsgType.FullServerResponse, EventType.SessionFinished)
                except Exception as e:
                    logger.warning(f"⚠️ [SESSION] 会话结束异常: {e}")
                
                if not audio_received:
                    await websocket.send(json.dumps({
                        "type": "error",
                        "message": "No audio data received"
                    }))
                else:
                    # 更新客户端统计
                    client_info["requests_count"] += 1
                    
                    # 计算性能指标
                    total_time = (time.time() - request_start_time) * 1000
                    self._update_performance_stats(total_time)
                    
                    logger.info(f"✅ [TTS] 请求完成: client={client_id}, 总耗时={total_time:.0f}ms, 音频块={total_audio_chunks}")
                
        except Exception as e:
            import traceback
            logger.error(f"❌ [TTS] 请求处理异常: {e}")
            logger.error(f"Traceback: {traceback.format_exc()}")
            await websocket.send(json.dumps({
                "type": "error",
                "message": f"TTS processing failed: {str(e)}"
            }))

    def _update_performance_stats(self, response_time: float):
        """更新性能统计"""
        self.performance_stats["total_requests"] += 1
        self.performance_stats["total_response_time"] += response_time
        self.performance_stats["avg_response_time"] = (
            self.performance_stats["total_response_time"] / self.performance_stats["total_requests"]
        )
        
        if response_time < self.performance_stats["fastest_response"]:
            self.performance_stats["fastest_response"] = response_time
        
        if response_time > self.performance_stats["slowest_response"]:
            self.performance_stats["slowest_response"] = response_time

    async def handle_stats_request(self, websocket: WebSocketServerProtocol):
        """处理统计信息请求"""
        try:
            pool_stats = self.connection_pool.get_stats()
            
            stats = {
                "type": "stats_response",
                "server_stats": self.performance_stats,
                "pool_stats": pool_stats,
                "active_clients": len(self.clients),
                "total_client_requests": sum(c["requests_count"] for c in self.clients.values())
            }
            
            await websocket.send(json.dumps(stats, indent=2))
            logger.info("📊 [STATS] 统计信息已发送")
            
        except Exception as e:
            logger.error(f"❌ [STATS] 获取统计异常: {e}")
            await websocket.send(json.dumps({
                "type": "error",
                "message": "Failed to get stats"
            }))

    async def handle_client_message(self, websocket: WebSocketServerProtocol, message: str):
        """处理客户端消息"""
        try:
            data = json.loads(message)
            msg_type = data.get("type")
            
            if msg_type == "tts_request":
                await self.handle_tts_request(websocket, data)
            elif msg_type == "ping":
                await websocket.send(json.dumps({"type": "pong"}))
            elif msg_type == "stats_request":
                await self.handle_stats_request(websocket)
            else:
                await websocket.send(json.dumps({
                    "type": "error",
                    "message": f"Unknown message type: {msg_type}"
                }))
                
        except json.JSONDecodeError:
            await websocket.send(json.dumps({
                "type": "error",
                "message": "Invalid JSON format"
            }))
        except Exception as e:
            logger.error(f"❌ [MESSAGE] 消息处理异常: {e}")
            await websocket.send(json.dumps({
                "type": "error",
                "message": "Message processing failed"
            }))

    async def handle_client(self, websocket: WebSocketServerProtocol, path: str):
        """处理客户端连接"""
        await self.register_client(websocket)
        
        try:
            # 发送欢迎消息
            await websocket.send(json.dumps({
                "type": "welcome",
                "message": "Connected to Optimized TTS WebSocket Server with Connection Pool",
                "client_id": self.clients[websocket]["id"],
                "features": ["connection_pool", "performance_stats", "session_reuse"]
            }))
            
            async for message in websocket:
                await self.handle_client_message(websocket, message)
                
        except websockets.exceptions.ConnectionClosed:
            logger.info("🔌 [CLIENT] 连接已关闭")
        except Exception as e:
            logger.error(f"❌ [CLIENT] 客户端处理异常: {e}")
        finally:
            await self.unregister_client(websocket)

    async def start_server(self):
        """启动WebSocket服务器"""
        logger.info("=" * 80)
        logger.info("🚀 启动优化版TTS WebSocket服务器")
        logger.info("=" * 80)
        logger.info(f"🌐 服务地址: ws://{self.host}:{self.port}")
        logger.info("🔥 优化功能:")
        logger.info("  • WebSocket连接池 - 减少连接建立时间")
        logger.info("  • 智能会话管理 - 提升响应速度")
        logger.info("  • 实时性能监控 - 优化效果可视化")
        logger.info("  • 连接复用策略 - 最大化资源利用")
        logger.info("=" * 80)
        
        try:
            async with websockets.serve(
                self.handle_client,
                self.host,
                self.port,
                ping_interval=30,
                ping_timeout=10,
                max_size=10**7,  # 10MB max message size
            ):
                logger.info(f"✅ [SERVER] 优化版TTS服务器运行中...")
                
                # 定期输出统计信息
                asyncio.create_task(self._periodic_stats_log())
                
                await asyncio.Future()  # Run forever
                
        except Exception as e:
            logger.error(f"❌ [SERVER] 服务器启动失败: {e}")
            await self.connection_pool.close_all()
            raise
    
    async def _periodic_stats_log(self):
        """定期输出统计信息"""
        while True:
            try:
                await asyncio.sleep(60)  # 每分钟输出一次
                
                if self.performance_stats["total_requests"] > 0:
                    pool_stats = self.connection_pool.get_stats()
                    
                    logger.info("📊 [STATS] ===== 性能统计 (最近1分钟) =====")
                    logger.info(f"📈 总请求数: {self.performance_stats['total_requests']}")
                    logger.info(f"⚡ 平均响应时间: {self.performance_stats['avg_response_time']:.0f}ms")
                    logger.info(f"🏃 最快响应: {self.performance_stats['fastest_response']:.0f}ms")
                    logger.info(f"🐌 最慢响应: {self.performance_stats['slowest_response']:.0f}ms")
                    logger.info(f"🔄 连接池命中率: {pool_stats['cache_hit_rate']}")
                    logger.info(f"🔌 活跃连接数: {pool_stats['total_active_connections']}")
                    logger.info(f"👥 在线客户端: {len(self.clients)}")
                    logger.info("=" * 50)
                    
            except Exception as e:
                logger.error(f"❌ [STATS] 统计日志异常: {e}")

    async def shutdown(self):
        """优雅关闭服务器"""
        logger.info("🔚 [SERVER] 开始关闭服务器...")
        await self.connection_pool.close_all()
        logger.info("✅ [SERVER] 服务器已关闭")


async def main():
    """主函数"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Optimized TTS WebSocket Server with Connection Pool")
    parser.add_argument("--host", default="0.0.0.0", help="Server host")
    parser.add_argument("--port", type=int, default=8765, help="Server port")
    
    args = parser.parse_args()
    
    server = OptimizedTTSWebSocketServer(args.host, args.port)
    
    try:
        await server.start_server()
    except KeyboardInterrupt:
        logger.info("🛑 [SERVER] 用户中断服务")
        await server.shutdown()
    except Exception as e:
        logger.error(f"❌ [SERVER] 服务器异常: {e}")
        await server.shutdown()


if __name__ == "__main__":
    asyncio.run(main()) 