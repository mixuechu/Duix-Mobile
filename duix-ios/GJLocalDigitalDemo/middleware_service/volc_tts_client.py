#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
火山TTS WebSocket客户端
实现与iOS端相同的连接逻辑
"""

import asyncio
import json
import struct
import logging
import time
from typing import Optional, Dict, Any, Callable
import websockets
from websockets.exceptions import WebSocketException

# 配置日志
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class VolcTTSClient:
    """火山TTS WebSocket客户端"""
    
    def __init__(self, app_id: str = None, access_token: str = None, resource_id: str = "volc.megatts.default"):
        """
        初始化TTS客户端
        
        Args:
            app_id: 火山引擎APP ID，如果不提供则使用iOS项目中的默认值
            access_token: 火山引擎Access Token，如果不提供则使用iOS项目中的默认值
            resource_id: 资源ID，默认为大模型语音合成
        """
        # 使用iOS项目中的鉴权信息作为默认值
        if not app_id:
            app_id = "3549748956"
        if not access_token:
            access_token = "wwooHO7HA6pCVuHvRF6kLaOPB9NGUs1K"
            
        self.app_id = app_id
        self.access_token = access_token
        self.resource_id = resource_id
        self.ws_url = "wss://openspeech.bytedance.com/api/v3/tts/bidirection"
        
        # 连接状态
        self.websocket: Optional[websockets.WebSocketServerProtocol] = None
        self.is_connected = False
        self.connection_id: Optional[str] = None
        self.session_id: Optional[str] = None
        
        # 回调函数
        self.on_audio_received: Optional[Callable[[bytes], None]] = None
        self.on_connection_status: Optional[Callable[[str, str], None]] = None
        
        # 性能计时
        self.request_start_time: Optional[float] = None
        self.ws_connected_time: Optional[float] = None
        self.session_start_time: Optional[float] = None
        self.first_audio_time: Optional[float] = None
    
    async def connect(self) -> bool:
        """
        建立WebSocket连接
        
        Returns:
            bool: 连接是否成功
        """
        try:
            logger.info("🔥 [TTS] 开始建立WebSocket连接...")
            self.request_start_time = time.time()
            
            # 构建请求头
            headers = {
                "X-Api-App-Key": self.app_id,
                "X-Api-Access-Key": self.access_token,
                "X-Api-Resource-Id": self.resource_id,
                "X-Api-Connect-Id": self._generate_uuid()
            }
            
            logger.info(f"🔥 [TTS] 连接URL: {self.ws_url}")
            logger.info(f"🔥 [TTS] 鉴权头: App-Key={self.app_id}, Access-Key={self.access_token}")
            
            # 建立WebSocket连接
            self.websocket = await websockets.connect(
                self.ws_url,
                extra_headers=headers,
                ping_interval=30,
                ping_timeout=10
            )
            
            self.is_connected = True
            self.ws_connected_time = time.time()
            
            if self.request_start_time:
                connection_latency = (self.ws_connected_time - self.request_start_time) * 1000
                logger.info(f"🚀 [PERF] 🌐 WebSocket连接成功，耗时: {connection_latency:.0f} ms")
            
            # 等待连接稳定
            await asyncio.sleep(0.1)
            
            # 开始接收消息
            asyncio.create_task(self._receive_loop())
            
            # 发送StartConnection
            logger.info("🔥 [TTS] 发送StartConnection...")
            start_connection_frame = self._build_binary_frame(
                message_type=0x14,  # Full-client request with event number
                serialization=0x10,  # JSON, no compression (根据你同事的脚本)
                event=1,  # StartConnection
                payload={}
            )
            await self.websocket.send(start_connection_frame)
            
            # 等待ConnectionStarted响应
            logger.info("🔥 [TTS] 等待ConnectionStarted...")
            await asyncio.sleep(1)
            
            return True
            
        except Exception as e:
            logger.error(f"❌ [TTS] WebSocket连接失败: {str(e)}")
            self.is_connected = False
            return False
    
    async def disconnect(self):
        """断开WebSocket连接"""
        if self.websocket:
            try:
                await self.websocket.close()
                logger.info("🔥 [TTS] WebSocket连接已断开")
            except Exception as e:
                logger.error(f"❌ [TTS] 断开连接时出错: {str(e)}")
            finally:
                self.websocket = None
                self.is_connected = False
    
    async def synthesize_text(self, text: str, speaker: str = "zh_female_cancan_mars_bigtts") -> bool:
        """
        合成文本为语音
        
        Args:
            text: 要合成的文本
            speaker: 发音人ID
            
        Returns:
            bool: 是否成功开始合成
        """
        if not self.is_connected or not self.websocket:
            logger.error("❌ [TTS] WebSocket未连接")
            return False
        
        try:
            logger.info(f"🔥 [TTS] 开始合成文本: {text[:50]}...")
            
            # 生成会话ID
            self.session_id = self._generate_uuid()
            
            # 发送StartSession
            await self._send_start_session(text, speaker)
            
            # 等待SessionStarted响应
            await asyncio.sleep(2)
            
            # 然后逐字符发送文本（像同事脚本一样）
            await self._send_text_char_by_char(text)
            
            return True
            
        except Exception as e:
            logger.error(f"❌ [TTS] 开始合成失败: {str(e)}")
            return False
    
    async def _send_start_session(self, text: str, speaker: str):
        """发送StartSession事件"""
        try:
            # 构造请求参数（根据同事脚本，StartSession不包含具体参数）
            payload = {
                "user": {"uid": "python_demo_user"},
                "namespace": "BidirectionalTTS"
            }
            
            # 构造二进制帧 - 使用同事脚本的参数
            frame = self._build_binary_frame(
                message_type=0x14,  # Full-client request with event number
                serialization=0x10,  # JSON, no compression
                event=100,  # StartSession (改回100)
                session_id=self.session_id,
                payload=payload
            )
            
            await self.websocket.send(frame)
            logger.info(f"🔥 [TTS] ✅ 已发送StartSession，会话ID: {self.session_id}")
            
        except Exception as e:
            logger.error(f"❌ [TTS] 发送StartSession失败: {str(e)}")
    
    async def _send_text_char_by_char(self, text: str):
        """逐字符发送文本（根据同事脚本的实现）"""
        try:
            logger.info(f"🔥 [TTS] 开始逐字符发送文本: {text}")
            
            for char in text:
                payload = {
                    "user": {"uid": "python_demo_user"},
                    "namespace": "BidirectionalTTS",
                    "req_params": {
                        "speaker": "",
                        "audio_params": {
                            "format": "pcm",
                            "sample_rate": 16000,
                            "bit_rate": 16000,
                            "format": "pcm",
                            "enable_timestamp": True,
                        },
                        "additions": json.dumps({
                            "disable_markdown_filter": False,
                        })
                    },
                    "text": char
                }
                
                # 构造二进制帧
                frame = self._build_binary_frame(
                    message_type=0x14,  # Full-client request with event number
                    serialization=0x10,  # JSON, no compression
                    event=300,  # TextRequest（文本请求用不同的事件编号）
                    session_id=self.session_id,
                    payload=payload
                )
                
                await self.websocket.send(frame)
                await asyncio.sleep(0.01)  # 小延迟，像同事脚本一样
            
            logger.info(f"🔥 [TTS] ✅ 文本发送完成")
            
        except Exception as e:
            logger.error(f"❌ [TTS] 逐字符发送失败: {str(e)}")
    
    async def _receive_loop(self):
        """接收消息循环"""
        try:
            while self.is_connected and self.websocket:
                try:
                    message = await self.websocket.recv()
                    await self._handle_message(message)
                except websockets.exceptions.ConnectionClosed:
                    logger.info("🔥 [TTS] WebSocket连接已关闭")
                    break
                except Exception as e:
                    logger.error(f"❌ [TTS] 接收消息时出错: {str(e)}")
                    break
        except Exception as e:
            logger.error(f"❌ [TTS] 接收循环出错: {str(e)}")
        finally:
            self.is_connected = False
    
    async def _handle_message(self, message):
        """处理接收到的消息"""
        try:
            if isinstance(message, bytes):
                if len(message) == 0:
                    logger.debug("🔥 [TTS] 收到空消息")
                    return
                logger.info(f"🔥 [TTS] 收到二进制消息，长度: {len(message)}")
                logger.info(f"🔥 [TTS] 消息前16字节: {message[:16].hex()}")
                
                # 添加详细的消息分析
                if len(message) >= 4:
                    header = message[:4]
                    protocol_version = (header[0] >> 4) & 0x0F
                    header_size = header[0] & 0x0F
                    message_type = (header[1] >> 4) & 0x0F
                    message_flags = header[1] & 0x0F
                    serialization = (header[2] >> 4) & 0x0F
                    compression = header[2] & 0x0F
                    logger.info(f"🔥 [TTS] 详细解析 - 协议版本: {protocol_version}, 头大小: {header_size}, "
                              f"消息类型: 0x{message_type:02x}, 序列化: 0x{serialization:02x}")
                
                await self._handle_binary_message(message)
            else:
                if not message or message.strip() == "":
                    logger.debug("🔥 [TTS] 收到空文本消息")
                    return
                logger.info(f"🔥 [TTS] 收到文本消息: {message}")
                
        except Exception as e:
            logger.error(f"❌ [TTS] 处理消息时出错: {str(e)}")
    
    async def _handle_binary_message(self, data: bytes):
        """处理二进制消息"""
        try:
            if len(data) < 4:
                return
            
            # 检查是否有4字节header（客户端消息格式）
            header = data[:4]
            protocol_version = (header[0] >> 4) & 0x0F
            header_size = header[0] & 0x0F
            
            # 如果有header，按客户端消息格式解析
            if protocol_version == 1 and header_size == 1 and len(data) >= 8:
                # 检查是否是服务器响应（有event number）
                event = struct.unpack('>I', data[4:8])[0]
                logger.info(f"🔥 [TTS] 收到事件编号: {event}")
                
                if event in [50, 150]:  # ConnectionStarted, SessionStarted
                    await self._handle_server_response(data)
                else:
                    message_type = (header[1] >> 4) & 0x0F
                    message_flags = header[1] & 0x0F
                    serialization = (header[2] >> 4) & 0x0F
                    compression = header[2] & 0x0F
                    
                    logger.debug(f"🔥 [TTS] 客户端消息 - 类型: 0x{message_type:02x}, 序列化: 0x{serialization:02x}")
                    
                    # 处理音频数据
                    if message_type == 0x0B or message_type == 0x09:  # Audio-only response 或者服务器响应
                        if len(data) >= 8:
                            event = struct.unpack('>I', data[4:8])[0]
                            logger.info(f"🔥 [TTS] 音频事件编号: {event}")
                            audio_data = data[8:]
                            
                            # 如果有实际音频数据（不只是状态消息）
                            if len(audio_data) > 0:
                                logger.info(f"🔥 [TTS] 发现音频数据: {len(audio_data)} bytes")
                                await self._handle_audio_data(audio_data)
                            else:
                                logger.info(f"🔥 [TTS] 收到状态消息，事件: {event}")
                    
                    # 处理JSON消息
                    elif serialization == 0x01 or serialization == 0x10:  # JSON
                        await self._handle_json_message(data)
            else:
                # 服务器响应格式: [session_id_length][session_id][payload_length][payload]
                await self._handle_server_response(data)
                
        except Exception as e:
            logger.error(f"❌ [TTS] 处理二进制消息时出错: {str(e)}")
    
    async def _handle_server_response(self, data: bytes):
        """处理服务器响应消息"""
        try:
            # 服务器响应格式: [session_id_length][session_id][payload_length][payload]
            offset = 0
            
            # 解析session_id
            if len(data) >= offset + 4:
                session_id_len = struct.unpack('>I', data[offset:offset+4])[0]
                offset += 4
                
                if len(data) >= offset + session_id_len:
                    session_id = data[offset:offset+session_id_len].decode('utf-8')
                    offset += session_id_len
                    logger.info(f"🔥 [TTS] 服务器会话ID: {session_id}")
                    
                    # 解析payload
                    if len(data) >= offset + 4:
                        payload_len = struct.unpack('>I', data[offset:offset+4])[0]
                        offset += 4
                        
                        if len(data) >= offset + payload_len:
                            payload_data = data[offset:offset+payload_len]
                            logger.info(f"🔥 [TTS] 服务器payload长度: {payload_len}")
                            
                            # 尝试解析JSON
                            try:
                                payload = json.loads(payload_data.decode('utf-8'))
                                logger.info(f"🔥 [TTS] 服务器payload: {payload}")
                                
                                # 根据session_id判断事件类型
                                if session_id == self.session_id:
                                    logger.info("🔥 [TTS] ✅ SessionStarted 收到")
                                    self.session_start_time = time.time()
                                    if self.ws_connected_time:
                                        session_latency = (self.session_start_time - self.ws_connected_time) * 1000
                                        logger.info(f"🚀 [PERF] 🎬 会话开始，延迟: {session_latency:.0f} ms")
                                else:
                                    logger.info("🔥 [TTS] ✅ ConnectionStarted 收到")
                                    if self.on_connection_status:
                                        self.on_connection_status("connected", "连接已建立")
                                        
                            except json.JSONDecodeError:
                                logger.info(f"🔥 [TTS] 非JSON payload: {payload_data}")
                                
        except Exception as e:
            logger.error(f"❌ [TTS] 处理服务器响应时出错: {str(e)}")
    
    async def _handle_audio_data(self, audio_data: bytes):
        """处理音频数据"""
        try:
            if not self.first_audio_time:
                self.first_audio_time = time.time()
                if self.request_start_time:
                    total_latency = (self.first_audio_time - self.request_start_time) * 1000
                    logger.info(f"🚀 [PERF] 🎵 首次收到音频，总延迟: {total_latency:.0f} ms")
            
            logger.info(f"🔥 [TTS] 收到音频数据: {len(audio_data)} bytes")
            
            # 调用音频回调函数
            if self.on_audio_received:
                self.on_audio_received(audio_data)
                
        except Exception as e:
            logger.error(f"❌ [TTS] 处理音频数据时出错: {str(e)}")
    
    async def _handle_json_message(self, data: bytes):
        """处理JSON消息"""
        try:
            # 解析事件编号
            if len(data) >= 8:
                event = struct.unpack('>I', data[4:8])[0]
                logger.debug(f"🔥 [TTS] 事件编号: {event}")
                
                # 解析JSON payload
                payload_start = 8
                if len(data) > payload_start:
                    json_data = data[payload_start:]
                    logger.debug(f"🔥 [TTS] JSON数据长度: {len(json_data)}")
                    logger.debug(f"🔥 [TTS] JSON数据: {json_data[:100]}...")  # 只显示前100字节
                    
                    try:
                        payload = json.loads(json_data.decode('utf-8'))
                        await self._handle_json_payload(event, payload)
                    except json.JSONDecodeError as e:
                        logger.warning(f"🔥 [TTS] JSON解析失败: {e}")
                        logger.info(f"🔥 [TTS] 原始数据: {json_data}")
                        logger.info(f"🔥 [TTS] 原始数据hex: {json_data.hex()}")
                        
        except Exception as e:
            logger.error(f"❌ [TTS] 处理JSON消息时出错: {str(e)}")
    
    async def _handle_json_payload(self, event: int, payload: Dict[str, Any]):
        """处理JSON payload"""
        try:
            if event == 50:  # ConnectionStarted
                logger.info("🔥 [TTS] ✅ ConnectionStarted 收到")
                if self.on_connection_status:
                    self.on_connection_status("connected", "连接已建立")
                
            elif event == 150:  # SessionStarted
                logger.info("🔥 [TTS] ✅ SessionStarted 收到")
                self.session_start_time = time.time()
                if self.ws_connected_time:
                    session_latency = (self.session_start_time - self.ws_connected_time) * 1000
                    logger.info(f"🚀 [PERF] 🎬 会话开始，延迟: {session_latency:.0f} ms")
                
            elif event == 251 or event == 201:  # TaskRequest confirmation
                logger.info(f"🔥 [TTS] ✅ TaskRequest确认 (Event={event})")
                
            elif event == 152:  # SessionFinished
                logger.info("🔥 [TTS] ✅ SessionFinished 收到")
                if self.on_connection_status:
                    self.on_connection_status("session_finished", "会话已结束")
                    
        except Exception as e:
            logger.error(f"❌ [TTS] 处理JSON payload时出错: {str(e)}")
    
    def _build_binary_frame(self, message_type: int, serialization: int, event: int, 
                           session_id: Optional[str] = None, payload: Dict[str, Any] = None) -> bytes:
        """
        构建二进制帧
        
        Args:
            message_type: 消息类型
            serialization: 序列化方式
            event: 事件编号
            session_id: 会话ID
            payload: 负载数据
            
        Returns:
            bytes: 二进制帧数据
        """
        try:
            # 构建帧头
            frame = bytearray()
            
            # Header (4 bytes)
            header = bytearray(4)
            header[0] = 0x11  # protocol v1, header size 4
            header[1] = message_type
            header[2] = serialization
            header[3] = 0x00  # no compression (根据你同事的脚本)
            frame.extend(header)
            
            # Event (4 bytes, big-endian)
            frame.extend(struct.pack('>I', event))
            
            # Session ID (optional)
            if session_id:
                session_id_bytes = session_id.encode('utf-8')
                frame.extend(struct.pack('>I', len(session_id_bytes)))
                frame.extend(session_id_bytes)
            
            # Payload
            if payload:
                payload_json = json.dumps(payload, ensure_ascii=False)
                payload_bytes = payload_json.encode('utf-8')
                frame.extend(struct.pack('>I', len(payload_bytes)))
                frame.extend(payload_bytes)
            else:
                # 空payload
                empty_json = b'{}'
                frame.extend(struct.pack('>I', len(empty_json)))
                frame.extend(empty_json)
            
            return bytes(frame)
            
        except Exception as e:
            logger.error(f"❌ [TTS] 构建二进制帧时出错: {str(e)}")
            return b''
    
    def _generate_uuid(self) -> str:
        """生成UUID"""
        import uuid
        return str(uuid.uuid4()).lower()
    
    def set_audio_callback(self, callback: Callable[[bytes], None]):
        """设置音频接收回调函数"""
        self.on_audio_received = callback
    
    def set_connection_status_callback(self, callback: Callable[[str, str], None]):
        """设置连接状态回调函数"""
        self.on_connection_status = callback 