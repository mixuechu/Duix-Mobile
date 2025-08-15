#!/usr/bin/env python3
"""
TTS连接池管理器
实现WebSocket连接复用和会话池，减少连接建立时间，提升性能
"""

import asyncio
import json
import logging
import time
import uuid
import websockets
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, field
from enum import Enum
from contextlib import asynccontextmanager

from protocols import (
    EventType,
    MsgType,
    start_connection,
    start_session,
    finish_session,
    wait_for_event,
)

logger = logging.getLogger(__name__)

class ConnectionState(Enum):
    """连接状态"""
    IDLE = "idle"
    BUSY = "busy"
    CONNECTING = "connecting"
    DISCONNECTED = "disconnected"

@dataclass
class TTSConnection:
    """TTS连接对象"""
    websocket: Optional[websockets.WebSocketServerProtocol] = None
    connection_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    voice_type: str = ""
    state: ConnectionState = ConnectionState.DISCONNECTED
    last_used: float = field(default_factory=time.time)
    created_at: float = field(default_factory=time.time)
    session_count: int = 0
    current_session_id: Optional[str] = None
    
    def is_expired(self, max_age: float = 300) -> bool:
        """检查连接是否过期 (5分钟)"""
        return (time.time() - self.created_at) > max_age
    
    def is_idle_too_long(self, max_idle: float = 60) -> bool:
        """检查连接是否空闲太久 (1分钟)"""
        return (time.time() - self.last_used) > max_idle

class TTSConnectionPool:
    """TTS连接池管理器"""
    
    def __init__(self, 
                 appid: str = "3549748956",
                 access_token: str = "wwooHO7HA6pCVuHvRF6kLaOPB9NGUs1K",
                 endpoint: str = "wss://openspeech.bytedance.com/api/v3/tts/bidirection",
                 max_connections_per_voice: int = 3,
                 max_total_connections: int = 10):
        """
        初始化连接池
        
        Args:
            max_connections_per_voice: 每种声音类型的最大连接数
            max_total_connections: 总的最大连接数
        """
        self.appid = appid
        self.access_token = access_token
        self.endpoint = endpoint
        self.max_connections_per_voice = max_connections_per_voice
        self.max_total_connections = max_total_connections
        
        # 连接池：voice_type -> List[TTSConnection]
        self.connections: Dict[str, List[TTSConnection]] = {}
        
        # 连接使用锁
        self._locks: Dict[str, asyncio.Lock] = {}
        
        # 清理任务
        self._cleanup_task: Optional[asyncio.Task] = None
        
        # 统计信息
        self.stats = {
            "total_requests": 0,
            "cache_hits": 0,
            "cache_misses": 0,
            "connections_created": 0,
            "connections_reused": 0,
            "avg_connection_time": 0,
            "avg_session_time": 0
        }
        
        # 启动清理任务
        self._start_cleanup_task()
    
    def _start_cleanup_task(self):
        """启动后台清理任务"""
        if self._cleanup_task is None or self._cleanup_task.done():
            self._cleanup_task = asyncio.create_task(self._cleanup_connections())
    
    async def _cleanup_connections(self):
        """定期清理过期和空闲连接"""
        while True:
            try:
                await asyncio.sleep(30)  # 每30秒清理一次
                
                current_time = time.time()
                total_cleaned = 0
                
                for voice_type, connections in list(self.connections.items()):
                    # 获取锁
                    if voice_type not in self._locks:
                        self._locks[voice_type] = asyncio.Lock()
                    
                    async with self._locks[voice_type]:
                        # 清理过期和空闲连接
                        to_remove = []
                        for i, conn in enumerate(connections):
                            should_remove = False
                            
                            if conn.is_expired():
                                logger.info(f"清理过期连接: {conn.connection_id} (voice: {voice_type})")
                                should_remove = True
                            elif conn.state == ConnectionState.IDLE and conn.is_idle_too_long():
                                logger.info(f"清理空闲连接: {conn.connection_id} (voice: {voice_type})")
                                should_remove = True
                            elif conn.state == ConnectionState.DISCONNECTED:
                                logger.info(f"清理断开连接: {conn.connection_id} (voice: {voice_type})")
                                should_remove = True
                            
                            if should_remove:
                                to_remove.append(i)
                                if conn.websocket:
                                    try:
                                        await conn.websocket.close()
                                    except:
                                        pass
                        
                        # 从后往前删除，避免索引变化
                        for i in reversed(to_remove):
                            connections.pop(i)
                            total_cleaned += 1
                        
                        # 如果某个voice_type没有连接了，清理空列表
                        if not connections:
                            del self.connections[voice_type]
                
                if total_cleaned > 0:
                    logger.info(f"连接池清理完成，清理了 {total_cleaned} 个连接")
                    
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"连接池清理异常: {e}")
    
    def get_resource_id(self, voice: str) -> str:
        """根据声音类型获取资源ID"""
        if voice.startswith("S_"):
            return "volc.megatts.default"
        return "volc.service_type.10029"
    
    async def _create_connection(self, voice_type: str) -> Optional[TTSConnection]:
        """创建新的WebSocket连接"""
        start_time = time.time()
        
        try:
            logger.info(f"🔧 [POOL] 为声音类型 {voice_type} 创建新连接...")
            
            # 构建连接头
            headers = {
                "X-Api-App-Key": self.appid,
                "X-Api-Access-Key": self.access_token,
                "X-Api-Resource-Id": self.get_resource_id(voice_type),
                "X-Api-Connect-Id": str(uuid.uuid4()),
            }
            
            # 建立WebSocket连接
            websocket = await websockets.connect(
                self.endpoint,
                extra_headers=headers,
                max_size=10 * 1024 * 1024,
                ping_interval=None,
                ping_timeout=None,
            )
            
            # 启动连接
            await start_connection(websocket)
            
            # 等待连接建立
            await wait_for_event(websocket, MsgType.FullServerResponse, EventType.ConnectionStarted)
            
            connection = TTSConnection(
                websocket=websocket,
                voice_type=voice_type,
                state=ConnectionState.IDLE,
                last_used=time.time(),
            )
            
            connection_time = (time.time() - start_time) * 1000
            logger.info(f"🚀 [POOL] ✅ 连接创建成功: {connection.connection_id} (耗时: {connection_time:.0f}ms)")
            
            # 更新统计
            self.stats["connections_created"] += 1
            self.stats["avg_connection_time"] = (
                (self.stats["avg_connection_time"] * (self.stats["connections_created"] - 1) + connection_time) /
                self.stats["connections_created"]
            )
            
            return connection
            
        except Exception as e:
            logger.error(f"❌ [POOL] 连接创建失败: {e}")
            return None
    
    @asynccontextmanager
    async def get_connection(self, voice_type: str):
        """
        获取可用连接的上下文管理器
        
        使用方式:
        async with pool.get_connection("zh_female_cancan_mars_bigtts") as conn:
            # 使用连接
            pass
        """
        start_time = time.time()
        connection = None
        
        try:
            # 获取或创建锁
            if voice_type not in self._locks:
                self._locks[voice_type] = asyncio.Lock()
            
            async with self._locks[voice_type]:
                # 尝试从池中获取空闲连接
                if voice_type in self.connections:
                    for conn in self.connections[voice_type]:
                        if conn.state == ConnectionState.IDLE and conn.websocket and not conn.websocket.closed:
                            conn.state = ConnectionState.BUSY
                            conn.last_used = time.time()
                            connection = conn
                            
                            self.stats["cache_hits"] += 1
                            self.stats["connections_reused"] += 1
                            
                            logger.info(f"🔄 [POOL] 复用连接: {conn.connection_id} (voice: {voice_type})")
                            break
                
                # 如果没有可用连接，创建新连接
                if connection is None:
                    self.stats["cache_misses"] += 1
                    
                    # 检查是否达到连接上限
                    current_voice_connections = len(self.connections.get(voice_type, []))
                    total_connections = sum(len(conns) for conns in self.connections.values())
                    
                    if (current_voice_connections >= self.max_connections_per_voice or 
                        total_connections >= self.max_total_connections):
                        # 尝试清理一个最旧的空闲连接
                        await self._cleanup_oldest_idle_connection(voice_type)
                    
                    # 创建新连接
                    connection = await self._create_connection(voice_type)
                    if connection:
                        connection.state = ConnectionState.BUSY
                        
                        # 添加到池中
                        if voice_type not in self.connections:
                            self.connections[voice_type] = []
                        self.connections[voice_type].append(connection)
            
            if connection is None:
                raise Exception("无法获取可用连接")
            
            self.stats["total_requests"] += 1
            
            # 返回连接
            yield connection
            
        except Exception as e:
            logger.error(f"❌ [POOL] 获取连接失败: {e}")
            raise
        finally:
            # 归还连接到池中
            if connection:
                connection.state = ConnectionState.IDLE
                connection.last_used = time.time()
                
                get_time = (time.time() - start_time) * 1000
                logger.info(f"⚡ [POOL] 连接获取完成，耗时: {get_time:.0f}ms")
    
    async def _cleanup_oldest_idle_connection(self, voice_type: str):
        """清理最旧的空闲连接为新连接腾出空间"""
        if voice_type not in self.connections:
            return
        
        # 找到最旧的空闲连接
        oldest_idle = None
        oldest_time = float('inf')
        
        for conn in self.connections[voice_type]:
            if conn.state == ConnectionState.IDLE and conn.last_used < oldest_time:
                oldest_idle = conn
                oldest_time = conn.last_used
        
        if oldest_idle:
            logger.info(f"🧹 [POOL] 清理最旧空闲连接: {oldest_idle.connection_id}")
            self.connections[voice_type].remove(oldest_idle)
            if oldest_idle.websocket:
                try:
                    await oldest_idle.websocket.close()
                except:
                    pass
    
    async def close_all(self):
        """关闭所有连接"""
        logger.info("🔒 [POOL] 关闭所有连接...")
        
        # 停止清理任务
        if self._cleanup_task:
            self._cleanup_task.cancel()
            try:
                await self._cleanup_task
            except asyncio.CancelledError:
                pass
        
        # 关闭所有连接
        for voice_type, connections in self.connections.items():
            for conn in connections:
                if conn.websocket:
                    try:
                        await conn.websocket.close()
                    except:
                        pass
        
        self.connections.clear()
        self._locks.clear()
        
        logger.info("✅ [POOL] 所有连接已关闭")
    
    def get_stats(self) -> Dict[str, Any]:
        """获取连接池统计信息"""
        cache_hit_rate = 0
        if self.stats["total_requests"] > 0:
            cache_hit_rate = (self.stats["cache_hits"] / self.stats["total_requests"]) * 100
        
        total_connections = sum(len(conns) for conns in self.connections.values())
        active_connections = sum(
            len([c for c in conns if c.state == ConnectionState.BUSY])
            for conns in self.connections.values()
        )
        
        return {
            **self.stats,
            "cache_hit_rate": f"{cache_hit_rate:.1f}%",
            "total_active_connections": total_connections,
            "busy_connections": active_connections,
            "voice_types": list(self.connections.keys()),
            "connections_per_voice": {
                voice: len(conns) for voice, conns in self.connections.items()
            }
        } 