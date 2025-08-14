#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
	echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
	echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $1"
}

# 检查必要的工具
check_dependencies() {
	log_info "检查依赖工具..."
	
	if ! command -v python3 &> /dev/null; then
		log_error "Python3 未安装"
		exit 1
	fi
	
	if ! command -v cloudflared &> /dev/null; then
		log_error "cloudflared 未安装，请先安装: brew install cloudflared"
		exit 1
	fi
	
	# 检查Python依赖
	if ! python3 -c "import websockets, asyncio, base64, json, wave" &> /dev/null; then
		log_error "Python依赖不完整，请安装: pip install websockets volcengine"
		exit 1
	fi
	
	log_success "所有依赖工具已就绪"
}

# 检查端口是否被占用
check_port() {
	local port=$1
	if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null ; then
		log_warning "端口 $port 已被占用，尝试停止占用进程..."
		lsof -ti:$port | xargs kill -9 2>/dev/null || true
		sleep 2
		if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null ; then
			log_error "无法释放端口 $port"
			exit 1
		fi
		log_success "端口 $port 已释放"
	fi
}

# 启动TTS WebSocket服务器
start_tts_server() {
	log_info "启动TTS WebSocket服务器..."
	
	# 检查8765端口
	check_port 8765
	
	# 启动服务器
	python3 tts_websocket_server.py &
	TTS_PID=$!
	
	# 等待服务器启动
	log_info "等待TTS服务器启动..."
	local max_wait=30
	local count=0
	
	while [ $count -lt $max_wait ]; do
		if lsof -Pi :8765 -sTCP:LISTEN -t >/dev/null ; then
			log_success "TTS WebSocket服务器启动成功 (PID: $TTS_PID)"
			return 0
		fi
		sleep 1
		((count++))
		echo -n "."
	done
	
	log_error "TTS服务器启动超时"
	kill $TTS_PID 2>/dev/null || true
	exit 1
}

# 启动cloudflare隧道
start_cloudflare_tunnel() {
	log_info "启动Cloudflare隧道..."
	
	# 创建日志目录
	mkdir -p logs
	
	# 清空旧隧道日志，避免读到历史URL
	: > logs/cloudflared.log
	
	# 启动隧道（以 HTTP 回源，WS 会由 Cloudflare 自动升级转发）
	cloudflared tunnel --url http://localhost:8765 --logfile logs/cloudflared.log &
	TUNNEL_PID=$!
	
	# 等待隧道启动并获取URL
	log_info "等待Cloudflare隧道启动..."
	local max_wait=30
	local count=0
	
	while [ $count -lt $max_wait ]; do
		# 先尝试抓取URL，只要拿到URL且进程存活，就视为成功
		if [ -f logs/cloudflared.log ]; then
			TUNNEL_URL=$(grep -o 'https://[^[:space:]]*\.trycloudflare\.com' logs/cloudflared.log | head -1)
			if [ ! -z "$TUNNEL_URL" ] && kill -0 $TUNNEL_PID 2>/dev/null; then
				WSS_URL=$(echo $TUNNEL_URL | sed 's/https:/wss:/')
				log_success "Cloudflare隧道启动成功"
				log_success "HTTP URL: $TUNNEL_URL"
				log_success "WSS URL: $WSS_URL"
				return 0
			fi
		fi

		# 若进程已退出而未拿到URL，判定失败但不退出整个脚本
		if ! kill -0 $TUNNEL_PID 2>/dev/null; then
			# 输出一条最相关的错误提示（过滤掉可忽略的origin证书提示）
			if grep -q 'Error validating origin URL' logs/cloudflared.log 2>/dev/null; then
				log_error "Cloudflare隧道启动失败: 原点URL校验失败"
				grep -m1 -E 'Error validating origin URL' logs/cloudflared.log 2>/dev/null || true
			else
				log_warning "Cloudflare隧道进程已退出，未获取到URL"
			fi
			return 1
		fi
		
		# 检测明确致命错误（忽略 originCertPath 的提示）
		if [ -f logs/cloudflared.log ] && grep -q 'Error validating origin URL' logs/cloudflared.log; then
			log_error "Cloudflare隧道启动失败: 原点URL校验失败"
			kill $TUNNEL_PID 2>/dev/null || true
			return 1
		fi
		sleep 1
		((count++))
		echo -n "."
	done
	
	log_warning "Cloudflare隧道启动超时，未获取到URL"
	kill $TUNNEL_PID 2>/dev/null || true
	return 1
}

# 显示连接信息
show_connection_info() {
	echo
	log_success "🚀 TTS WebSocket服务启动完成！"
	echo
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo -e "${GREEN}📍 本地服务地址:${NC} ws://localhost:8765"
	if [ "$TUNNEL_AVAILABLE" -eq 1 ]; then
		echo -e "${GREEN}🌐 公网HTTP地址:${NC} $TUNNEL_URL"
		echo -e "${GREEN}🔗 公网WSS地址:${NC}  $WSS_URL"
	else
		echo -e "${YELLOW}🌐 公网HTTP地址:${NC} 未配置"
		echo -e "${YELLOW}🔗 公网WSS地址:${NC} 未配置"
	fi
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo
	echo -e "${BLUE}📱 iOS端配置:${NC}"
	if [ "$TUNNEL_AVAILABLE" -eq 1 ]; then
		echo "   将WebSocket URL设置为: $WSS_URL"
	else
		echo "   本地测试URL: ws://localhost:8765"
	fi
	echo
	echo -e "${BLUE}🎤 支持的消息类型:${NC}"
	echo "   • TTS请求: {\"type\": \"tts_request\", \"text\": \"要转换的文本\"}"
	echo "   • 心跳检测: {\"type\": \"ping\"}"
	echo
	echo -e "${BLUE}📊 监控信息:${NC}"
	echo "   服务器日志: 查看终端输出"
	if [ "$TUNNEL_AVAILABLE" -eq 1 ]; then
		echo "   隧道日志:   tail -f logs/cloudflared.log"
	fi
	echo
	if [ "$TUNNEL_AVAILABLE" -eq 1 ]; then
		echo -e "${YELLOW}⚠️  注意: 此隧道URL是临时的，重启后会变化${NC}"
	else
		echo -e "${YELLOW}⚠️  注意: 当前只提供本地连接，iOS设备需在同一网络${NC}"
	fi
	echo
	echo -e "${GREEN}🧪 测试命令:${NC}"
	echo "   python3 test_websocket_client.py"
	echo
}

# 清理函数
cleanup() {
	log_info "正在清理进程..."
	[ ! -z "$TUNNEL_PID" ] && kill $TUNNEL_PID 2>/dev/null || true
	[ ! -z "$TTS_PID" ] && kill $TTS_PID 2>/dev/null || true
	log_success "清理完成"
}

# 信号处理
trap cleanup EXIT INT TERM

# 主流程
main() {
	echo "🎵 启动TTS WebSocket服务和Cloudflare隧道"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	
	# 检查依赖
	check_dependencies
	
	# 启动TTS服务
	start_tts_server
	
	# 尝试启动Cloudflare隧道
	if start_cloudflare_tunnel; then
		TUNNEL_AVAILABLE=1
	else
		TUNNEL_AVAILABLE=0
		log_warning "未能创建Cloudflare隧道，将仅提供本地连接"
	fi
	
	# 显示连接信息
	show_connection_info
	
	# 保持运行
	log_info "按 Ctrl+C 停止服务"
	wait
}

# 运行主流程
main "$@" 