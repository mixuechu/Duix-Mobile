//
//  GJLPCMManager.m
//  GJLocalDigitalDemo
//
//  Created by guiji on 2025/5/12.
//

#import "GJLPCMManager.h"
#import "GJLPLAssetReader.h"
#import "GJLGCDNEWTimer.h"
#import <GJLocalDigitalSDK/GJLocalDigitalSDK.h>

#define MAXDATALENGHT 64000
// 🔄 切换到中转服务 (通过Cloudflare公网tunnel)
static NSString * const kVolcWSURL = @"wss://ash-heights-yard-mixed.trycloudflare.com";
static NSString * const kVolcAppId = @"3549748956"; // X-Api-App-Key
static NSString * const kVolcAccessToken = @"wwooHO7HA6pCVuHvRF6kLaOPB9NGUs1K"; // X-Api-Access-Key
static NSString * const kVolcClusterId = @"volcano_tts"; // Cluster/Resource hint if needed

@interface GJLPCMManager()
@property (nonatomic, strong) GJLPLAssetReader *assetReader;
@property (nonatomic, strong) GJLGCDNEWTimer *audioTimer;
@property (nonatomic, strong) dispatch_queue_t audio_timer_queue;


@property (nonatomic, strong) dispatch_queue_t playAudioQueue;

@property (nonatomic, strong) dispatch_semaphore_t semaphore;

@property (nonatomic, assign) BOOL isPlaying;


@property (nonatomic, strong)NSMutableArray * wavArr;
//是否正在处理音频
@property (nonatomic, assign)BOOL isWaving;

@property (nonatomic, strong) NSURLSession *volcSession;
@property (nonatomic, strong) NSURLSessionWebSocketTask *volcWS;
@property (nonatomic, strong) dispatch_queue_t volc_queue;
@property (nonatomic, copy) NSString *volcConnectionId;
@property (nonatomic, copy) NSString *volcSessionId;
@property (nonatomic, copy) NSString *volcPendingText;
@property (nonatomic, assign) BOOL volcRunning;

// 🔄 新增中转服务相关属性
@property (nonatomic, strong) NSMutableData *audioBuffer;
@property (nonatomic, assign) BOOL isUsingProxy; // 是否使用中转服务

@end
static GJLPCMManager * manager = nil;
@implementation GJLPCMManager

+ (GJLPCMManager *)manager
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        manager = [[GJLPCMManager alloc] init];
    });
    return manager;
}
-(id)init
{
    self=[super init];
    if(self)
    {

        
//        _pcmDataCache2 = [[NSMutableData alloc] init];
   
        self.audio_timer_queue=dispatch_queue_create("com.digitalsdk.audio_timer_queue", DISPATCH_QUEUE_SERIAL);
        self.playAudioQueue= dispatch_queue_create("com.digitalsdk.playAudioQueue", DISPATCH_QUEUE_SERIAL);
        self.wavArr=[[NSMutableArray alloc] init];
        self.volc_queue = dispatch_queue_create("com.digitalsdk.volc_queue", DISPATCH_QUEUE_SERIAL);
        
//        [self setupAudioSession];

        
    }
    return self;
}
- (void)speakWavPath:(NSString *)wavPath
{
   

    __weak typeof(self)weakSelf = self;

 
    AVAsset * asset;
   if([wavPath containsString:@"http"])
   {
       asset = [AVAsset assetWithURL:[NSURL URLWithString:wavPath]];
   }
    else
    {
        asset = [AVAsset assetWithURL:[NSURL fileURLWithPath:wavPath]];
    }

//    Float64 durationInSeconds = CMTimeGetSeconds(asset.duration);

  /*  NSLog(@"durationInSeconds:%f",durationInSeconds)*/;
    
    self.assetReader = [[GJLPLAssetReader alloc] initWithAVAsset:asset];
    self.assetReader.playStatus = ^(NSInteger status) {
        //开始
        if(status==1)
        {
  
            [weakSelf toStartAudioTimerAndPlaying];


        }
        
    };
    [self.assetReader seekTo:kCMTimeZero];

   
}

-(void)toStartAudioTimerAndPlaying
{
    __weak typeof(self)weakSelf = self;

    self.isPlaying=YES;

    

   
    
    
    [[GJLDigitalManager  manager] startPlaying];
    [self audioPushProc];

 
    self.audioTimer =[GJLGCDNEWTimer scheduledTimerWithTimeInterval:0.04 repeats:YES queue:self.audio_timer_queue block:^{
        
            [weakSelf audioPushProc];
        }];


}
-(void)toStopAudioTimer
{
    if(self.audioTimer!=nil)
    {
        [self.audioTimer invalidate];
        self.audioTimer=nil;
    }
   
}

// 音频数据
- (void)audioPushProc {

    @autoreleasepool {

        if(self.isPlaying)
        {
            if([self.assetReader hasAudio])
            {
                CMSampleBufferRef sample = [self.assetReader readAudioSampleBuffer];
          
                if (sample) {
                    
                    
                    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sample);
                    size_t totolLength;
                    char *dataPointer = NULL;
                    CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &totolLength, &dataPointer);
                    //                   NSLog(@"totolLength:%ld",totolLength);
                    if (totolLength == 0 || !dataPointer) {
                        return;
                    }
                    
    //
                    NSData * data=[NSData dataWithBytes:dataPointer length:totolLength];
                    
                    [[GJLDigitalManager manager] toWavPcmData:data];
          


                    CFRelease(sample);
                }
                else
                {
                    //推流结束调用finishSession
                    NSLog(@"推流结束");
                    [self toStop];
                    [[GJLDigitalManager manager] finishSession];
//
//                    NSString * filepath=[[NSBundle mainBundle] pathForResource:@"3.wav" ofType:nil];
//                    [self speakWavPath:filepath];
                }
        }
        
            
  
        }
        
        

  }
}


-(void)toStop
{
    self.isPlaying=NO;
    [self toStopAudioTimer];
//    [self toStopAudioTimer2];
    if(self.assetReader!=nil)
    {
        [self.assetReader toCancelRead];
    }

    // 关闭火山WS
    if (self.volcWS) {
        [self.volcWS cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
        self.volcWS = nil;
    }
    self.volcRunning = NO;

}

#pragma mark-----------播放本地音频或url网络音频----------------------
-(void)toSpeakWithPath:(NSString*)wavPath
{
   

    __weak typeof(self)weakSelf = self;
//    [[GJLDigitalManager manager] toMute:NO];
    [self toStop];

    dispatch_async(self.playAudioQueue, ^{

//
         NSString *localPath = [wavPath stringByReplacingOccurrencesOfString:@"file://" withString:@""];
        dispatch_async(dispatch_get_main_queue(), ^{
            //一个动作区间来回震荡，1 支持随机动作 0 不支持随机动作
//            NSInteger rst= [[GJLDigitalManager manager] toActRangeMinAndMax];
            [weakSelf speakWavPath:localPath];
      
            
//            
        });


    });
  
    
}


#pragma mark-----------火山TTS流式合成（通过中转服务）----------------------
- (void)toSpeakTextWithVolc:(NSString *)text
{
    NSLog(@"🔥 [TTS] toSpeakTextWithVolc called with text: %@", text);
    
    // 🚀 重置所有计时变量
    self.requestStartTime = nil;
    self.wsConnectedTime = nil;
    self.sessionStartTime = nil;
    self.firstAudioTime = nil;
    
    // 🚀 【计时开始】记录请求发起时间
    self.requestStartTime = [NSDate date];
    NSLog(@"🚀 [PERF] ⏱️ REQUEST START: %@", self.requestStartTime);
    
    if (text.length == 0) { 
        NSLog(@"❌ [TTS] Text is empty, returning");
        return; 
    }
    
    // 🔄 标记使用中转服务
    self.isUsingProxy = YES;
    self.audioBuffer = [[NSMutableData alloc] init];
    
    __weak typeof(self) weakSelf = self;
    // 🚀 使用高优先级队列加速处理
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSLog(@"🔥 [TTS] ⚡ Starting TTS process via PROXY on HIGH PRIORITY queue");
        [weakSelf _proxyStartIfNeeded];
        [weakSelf _proxyReceiveLoop];
        
        // 🔄 使用简化协议发送TTS请求
        [weakSelf _proxySendTTSRequest:text];
    });
}

- (void)_volcStartIfNeeded
{
    NSLog(@"🔥 [TTS] _volcStartIfNeeded called");
    if (self.volcSession && self.volcWS) { 
        NSLog(@"🔥 [TTS] WebSocket already exists, skipping initialization");
        return; 
    }
    NSLog(@"🔥 [TTS] ⚡ Creating OPTIMIZED WebSocket connection to: %@", kVolcWSURL);
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    // 🚀 网络优化配置
    cfg.timeoutIntervalForRequest = 10; // 减少请求超时
    cfg.timeoutIntervalForResource = 15; // 减少资源超时  
    cfg.allowsCellularAccess = YES;
    cfg.waitsForConnectivity = NO; // 不等待网络，立即失败
    // 鉴权请求头
    cfg.HTTPAdditionalHeaders = @{ @"X-Api-App-Key": kVolcAppId,
                                   @"X-Api-Access-Key": kVolcAccessToken,
                                   @"X-Api-Resource-Id": @"volc.service_type.10029",
                                   @"X-Api-Connect-Id": [[NSUUID UUID] UUIDString].lowercaseString };
    NSLog(@"🔥 [TTS] Auth headers: App-Key=%@, Access-Key=%@", kVolcAppId, kVolcAccessToken);
    self.volcSession = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
    self.volcWS = [self.volcSession webSocketTaskWithURL:[NSURL URLWithString:kVolcWSURL]];
    [self.volcWS resume];
    self.volcRunning = YES;
    NSLog(@"🔥 [TTS] WebSocket started, volcRunning = YES");
    
    // 开启数字人播放
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"🔥 [TTS] Starting digital human on main queue");
        [[GJLDigitalManager manager] newSession];
        [[GJLDigitalManager manager] startPlaying];
    });
}

- (void)_volcReceiveLoop
{
    if (!self.volcWS || !self.volcRunning) { 
        NSLog(@"❌ [TTS] _volcReceiveLoop: WebSocket not ready (WS=%@, Running=%d)", self.volcWS ? @"YES" : @"NO", self.volcRunning);
        return; 
    }
    NSLog(@"🔥 [TTS] Starting receive loop");
    __weak typeof(self) weakSelf = self;
    [self.volcWS receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage * _Nullable message, NSError * _Nullable error) {
        if (error) {
            NSLog(@"❌ [TTS] WebSocket error: %@", error.localizedDescription);
            weakSelf.volcRunning = NO;
            [[GJLDigitalManager manager] finishSession];
            return;
        }
        if (message) {
            NSLog(@"🔥 [TTS] Received message type: %ld", (long)message.type);
            if (message.type == NSURLSessionWebSocketMessageTypeData) {
                NSLog(@"🔥 [TTS] Message data length: %lu bytes", (unsigned long)message.data.length);
                
                // 输出前16字节的十六进制调试信息
                if (message.data.length > 0) {
                    const uint8_t *bytes = (const uint8_t *)message.data.bytes;
                    NSMutableString *hexString = [NSMutableString string];
                    NSUInteger maxBytes = MIN(16, message.data.length);
                    for (NSUInteger i = 0; i < maxBytes; i++) {
                        [hexString appendFormat:@"%02x ", bytes[i]];
                    }
                    NSLog(@"🔥 [TTS] First %lu bytes (hex): %@", (unsigned long)maxBytes, hexString);
                }
            }
            [weakSelf _volcHandleMessage:message];
        }
        [weakSelf _volcReceiveLoop];
    }];
}

- (void)_volcHandleMessage:(NSURLSessionWebSocketMessage *)message
{
    NSLog(@"🔥 [TTS] _volcHandleMessage called with message type: %ld", (long)message.type);
    // 火山V3为二进制自定义帧。这里简化处理：
    // - 类型为二进制且Serialization=Raw、MessageType=Audio-only response时，payload即为音频PCM片段。
    // 文档里帧头4字节后可能包含event/session等可选字段，这里做一个保守提取：
    if (message.type == NSURLSessionWebSocketMessageTypeData) {
        [self _volcHandleBinaryData:message.data];
    } else if (message.type == NSURLSessionWebSocketMessageTypeString) {
        NSLog(@"🔥 [TTS] Received string message: %@", message.string);
    }
}

- (void)_volcHandleBinaryData:(NSData *)data
{
    NSLog(@"🔥 [TTS] _volcHandleMessage called with data length: %lu", (unsigned long)data.length);
    if (data.length < 12) { 
        NSLog(@"❌ [TTS] Binary message too short: %lu bytes, need at least 12", (unsigned long)data.length);
        return; 
    }
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    // header 4字节：
    uint8_t messageType = bytes[1];
    uint8_t serialization = (bytes[2] >> 4) & 0x0F; // 0 raw, 1 json
    NSLog(@"🔥 [TTS] Binary message - messageType: 0x%02x, serialization: %u", messageType, serialization);
    
    // 处理JSON格式的消息 (serialization = 1)
    if (serialization == 1) {
        NSLog(@"🔥 [TTS] Processing JSON message, total length: %lu", (unsigned long)data.length);
        
        // 分析消息结构：从原始字节可以看出这是一个复合消息
        // 格式似乎是: [header] [session_id_length] [session_id] [json_length] [json_data]
        size_t offset = 8; // 跳过消息头
        
        // 读取第一个长度字段 (session_id 长度)
            if (data.length >= offset + 4) {
                uint32_t sessionIdLength = (bytes[offset] << 24) | (bytes[offset+1] << 16) | (bytes[offset+2] << 8) | (bytes[offset+3]);
                offset += 4;
                NSLog(@"🔥 [TTS] Session ID length: %u", sessionIdLength);
                
                // 读取 session_id
                if (sessionIdLength > 0 && data.length >= offset + sessionIdLength) {
                    NSData *sessionIdData = [data subdataWithRange:NSMakeRange(offset, sessionIdLength)];
                    NSString *sessionId = [[NSString alloc] initWithData:sessionIdData encoding:NSUTF8StringEncoding];
                    NSLog(@"🔥 [TTS] Session ID: %@", sessionId);
                    offset += sessionIdLength;
                    
                    // 读取第二个长度字段 (JSON 长度)
                    if (data.length >= offset + 4) {
                        uint32_t jsonLength = (bytes[offset] << 24) | (bytes[offset+1] << 16) | (bytes[offset+2] << 8) | (bytes[offset+3]);
                        offset += 4;
                        NSLog(@"🔥 [TTS] JSON length: %u", jsonLength);
                        
                        // 读取 JSON 数据
                        if (jsonLength > 0 && data.length >= offset + jsonLength) {
                            NSData *jsonData = [data subdataWithRange:NSMakeRange(offset, jsonLength)];
                            NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                            NSLog(@"🔥 [TTS] JSON Response: %@", jsonString);
                            
                            // 尝试解析JSON
                            NSError *error;
                            id jsonObj = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
                            if (jsonObj) {
                                NSLog(@"🔥 [TTS] ✅ Parsed JSON: %@", jsonObj);
                                
                                // 检查是否有错误信息
                                if ([jsonObj isKindOfClass:[NSDictionary class]]) {
                                    NSDictionary *dict = (NSDictionary *)jsonObj;
                                    if (dict[@"error"]) {
                                        NSLog(@"❌ [TTS] Server Error: %@", dict[@"error"]);
                                    }
                                    if (dict[@"status"]) {
                                        NSLog(@"🔥 [TTS] Status: %@", dict[@"status"]);
                                    }
                                    
                                    // 如果是空的JSON，说明这是确认消息
                                    if ([dict count] == 0) {
                                        // 检查事件类型 - 需要从二进制消息头读取事件编号
                                        uint32_t event = 0;
                                        if (data.length >= 8) {
                                            event = (bytes[4] << 24) | (bytes[5] << 16) | (bytes[6] << 8) | (bytes[7]);
                                        }
                                        
                                        if (event == 50) { // ConnectionStarted
                                            NSLog(@"🔥 [TTS] ✅ ConnectionStarted received! Server session ID: %@", sessionId);
                                            // 使用服务器返回的session ID
                                            self.volcSessionId = sessionId;
                                            [self _volcSendStartSessionWithText:self.volcPendingText ?: @"开始我会盯盘，到现在感觉看那个东西非常无聊。亏损了就放着。赚了就体现。现在就这样。爱涨不涨。妨碍我干正事。"];
                                                } else if (event == 150) { // SessionStarted
            NSLog(@"🔥 [TTS] ✅ SessionStarted for session: %@", sessionId);
            
            // 🚀 记录会话开始时间
            self.sessionStartTime = [NSDate date];
            if (self.wsConnectedTime) {
                NSTimeInterval sessionStartLatency = [self.sessionStartTime timeIntervalSinceDate:self.wsConnectedTime];
                NSLog(@"🚀 [PERF] 🎬 Session started in: %.0f ms", sessionStartLatency * 1000);
            }
            if (self.requestStartTime) {
                NSTimeInterval totalLatency = [self.sessionStartTime timeIntervalSinceDate:self.requestStartTime];
                NSLog(@"🚀 [PERF] 📊 Total session start time: %.0f ms", totalLatency * 1000);
            }
                                            // 确保使用服务器确认的session ID
                                            self.volcSessionId = sessionId;
                                            // 现在发送TaskRequest
                                            NSLog(@"🔥 [TTS] Sending TaskRequest for session: %@", self.volcSessionId);
                                            [self _volcSendTaskRequestForSession:self.volcSessionId];
                                            NSLog(@"🔥 [TTS] 🕐 Waiting for audio data (messageType=0x0b)...");
                                            NSLog(@"🔥 [TTS] WebSocket state after TaskRequest: %ld", (long)self.volcWS.state);
                                        } else if (event == 251 || event == 201) { // TaskRequest confirmation
                                            NSLog(@"🔥 [TTS] ✅ TaskRequest confirmed (Event=%u) for session: %@", event, sessionId);
                                            NSLog(@"🔥 [TTS] 🎵 Now expecting audio data...");
                                        } else if (event >= 200 && event <= 299) { // TaskRequest related events
                                            NSLog(@"🔥 [TTS] 📝 TaskRequest related event: %u for session: %@", event, sessionId);
                                        } else {
                                            NSLog(@"🔥 [TTS] ✅ Received acknowledgment (Event=%u) for session: %@", event, sessionId);
                                        }
                                    }
                                }
                            } else {
                                NSLog(@"❌ [TTS] JSON parse error: %@", error.localizedDescription);
                            }
                        }
                    }
                }
            }
            return;
        }
        
        if ((messageType == 0x0B || messageType == 0xB4) && serialization == 0) {
            NSLog(@"🔥 [TTS] ✅ AUDIO MESSAGE DETECTED! messageType=0x%02x, serialization=%d", messageType, serialization);
            // 解析 event
            uint32_t event = (bytes[4] << 24) | (bytes[5] << 16) | (bytes[6] << 8) | (bytes[7]);
            // 跳过可选 session_id: 如果后续4字节值较小(<=64)且后续该长度范围内多为可见ASCII，则认为存在session_id
            size_t offset = 8;
            if (data.length >= offset + 4) {
                uint32_t possibleLen = (bytes[offset] << 24) | (bytes[offset+1] << 16) | (bytes[offset+2] << 8) | (bytes[offset+3]);
                BOOL looksASCII = NO;
                if (possibleLen > 0 && possibleLen <= 64 && data.length >= offset + 4 + possibleLen) {
                    looksASCII = YES;
                    for (uint32_t i = 0; i < possibleLen; i++) {
                        uint8_t ch = bytes[offset + 4 + i];
                        if (!(ch == '-' || (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z'))) {
                            looksASCII = NO; break;
                        }
                    }
                }
                if (looksASCII) {
                    offset += 4 + possibleLen;
                }
            }
            if (data.length >= offset + 4) {
                uint32_t payloadSize = (bytes[offset] << 24) | (bytes[offset+1] << 16) | (bytes[offset+2] << 8) | (bytes[offset+3]);
                offset += 4;
                if (payloadSize > 0 && data.length >= offset + payloadSize) {
                    NSData *pcm = [data subdataWithRange:NSMakeRange(offset, payloadSize)];
                    if (pcm.length > 0) {
                        // 🚀 【计时结束】记录首次收到音频的时间
                        if (!self.firstAudioTime) {
                            self.firstAudioTime = [NSDate date];
                            
                            NSLog(@"🚀 [PERF] 🎯 FIRST AUDIO RECEIVED!");
                            NSLog(@"🚀 [PERF] ⏱️ Request start:  %@", self.requestStartTime);
                            NSLog(@"🚀 [PERF] ⏱️ WS connected:   %@", self.wsConnectedTime);
                            NSLog(@"🚀 [PERF] ⏱️ Session start:  %@", self.sessionStartTime);
                            NSLog(@"🚀 [PERF] ⏱️ First audio:    %@", self.firstAudioTime);
                            NSLog(@"🚀 [PERF] 📊 === DETAILED LATENCY BREAKDOWN ===");
                            
                            if (self.requestStartTime) {
                                NSTimeInterval totalLatency = [self.firstAudioTime timeIntervalSinceDate:self.requestStartTime];
                                NSLog(@"🚀 [PERF] 📊 🎯 TOTAL (Request → Audio): %.0f ms", totalLatency * 1000);
                            }
                            
                            if (self.wsConnectedTime && self.requestStartTime) {
                                NSTimeInterval connectionTime = [self.wsConnectedTime timeIntervalSinceDate:self.requestStartTime];
                                NSLog(@"🚀 [PERF] 📊 🌐 Connection Time: %.0f ms", connectionTime * 1000);
                            }
                            
                            if (self.sessionStartTime && self.wsConnectedTime) {
                                NSTimeInterval sessionSetupTime = [self.sessionStartTime timeIntervalSinceDate:self.wsConnectedTime];
                                NSLog(@"🚀 [PERF] 📊 🎬 Session Setup: %.0f ms", sessionSetupTime * 1000);
                            }
                            
                            if (self.firstAudioTime && self.sessionStartTime) {
                                NSTimeInterval audioProcessTime = [self.firstAudioTime timeIntervalSinceDate:self.sessionStartTime];
                                NSLog(@"🚀 [PERF] 📊 🎵 Audio Processing: %.0f ms", audioProcessTime * 1000);
                            }
                        }
                        
                        NSLog(@"🔥 [TTS] 🎵 STREAMING PCM: %lu bytes - PLAYING IMMEDIATELY!", (unsigned long)pcm.length);
                        // 🚀 流式优化：立即播放，不等待缓冲
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[GJLDigitalManager manager] toWavPcmData:pcm];
                        });
                    }
                } else {
                    NSLog(@"❌ [TTS] Invalid PCM data: payloadSize=%u, expected offset+size=%lu, actual data.length=%lu", 
                          payloadSize, (unsigned long)(offset + payloadSize), (unsigned long)data.length);
                }
            }
        } else {
            NSLog(@"🔥 [TTS] ❓ NON-AUDIO MESSAGE: messageType=0x%02x (binary: 0b%08b), serialization=%u", messageType, messageType, serialization);
            
            // 解析event类型
            uint32_t event = 0;
            if (data.length >= 8) {
                event = (bytes[4] << 24) | (bytes[5] << 16) | (bytes[6] << 8) | (bytes[7]);
                NSLog(@"🔥 [TTS] Event ID: %u", event);
            }
            
            // 如果有payload，尝试显示内容
            if (data.length > 8) {
                size_t offset = 8;
                // 检查是否有session_id
                if (data.length >= offset + 4) {
                    uint32_t possibleLen = (bytes[offset] << 24) | (bytes[offset+1] << 16) | (bytes[offset+2] << 8) | (bytes[offset+3]);
                    if (possibleLen > 0 && possibleLen <= 64 && data.length >= offset + 4 + possibleLen) {
                        NSData *sessionData = [data subdataWithRange:NSMakeRange(offset + 4, possibleLen)];
                        NSString *sessionId = [[NSString alloc] initWithData:sessionData encoding:NSUTF8StringEncoding];
                        if (sessionId) {
                            NSLog(@"🔥 [TTS] Session ID in message: %@", sessionId);
                            offset += 4 + possibleLen;
                        }
                    }
                }
                
                // 尝试读取剩余的payload
                if (data.length >= offset + 4) {
                    uint32_t payloadLen = (bytes[offset] << 24) | (bytes[offset+1] << 16) | (bytes[offset+2] << 8) | (bytes[offset+3]);
                    offset += 4;
                    NSLog(@"🔥 [TTS] Payload length: %u", payloadLen);
                    
                    if (payloadLen > 0 && data.length >= offset + payloadLen && payloadLen <= 1000) {
                        NSData *payloadData = [data subdataWithRange:NSMakeRange(offset, payloadLen)];
                        NSString *payloadStr = [[NSString alloc] initWithData:payloadData encoding:NSUTF8StringEncoding];
                        if (payloadStr) {
                            NSLog(@"🔥 [TTS] Payload content: %@", payloadStr);
                        } else {
                            NSLog(@"🔥 [TTS] Payload is binary, length: %u", payloadLen);
                        }
                    }
                }
            }
        }
    }


- (void)_volcSendStartSessionWithText:(NSString *)text
{
    NSLog(@"🔥 [TTS] _volcSendStartSessionWithText: %@", text);
    NSDictionary *reqParams = @{ @"text": text,
                                 // 🚀 移除model参数，使用默认更快的模型
                                 @"speaker": @"zh_female_cancan_mars_bigtts", // 🚀 使用更简单的发音人
                                 @"streaming": @YES, // 🚀 启用流式模式，最关键的优化！
                                 @"audio_params": @{ @"format": @"pcm",
                                                      @"sample_rate": @16000, 
                                                      @"bit_rate": @16000,
                                                      @"buffer_size": @512 } }; // 🚀 减小缓冲区，更快开始播放
    NSDictionary *payload = @{ @"user": @{ @"uid": @"ios_demo_user" },
                               @"req_params": reqParams };
    NSLog(@"🔥 [TTS] Sending StartSession with payload: %@", payload);
    [self _volcSendEventJSON:100 connectionId:nil sessionId:self.volcSessionId payload:payload];
    
    // 🚀 流式模式下更频繁的状态检查
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"🔥 [TTS] ⚡ 1s check - STREAMING MODE: Expecting rapid audio chunks...");
        NSLog(@"🔥 [TTS] WebSocket state: %ld", (long)self.volcWS.state);
    });
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"🔥 [TTS] ⚡ 3s check - STREAMING: Should have audio by now...");
        NSLog(@"🔥 [TTS] WebSocket state: %ld", (long)self.volcWS.state);
    });
}

- (void)_volcSendTaskRequestForSession:(NSString *)sessionId
{
    // TaskRequest需要包含完整的参数，类似StartSession
    NSString *text = self.volcPendingText ?: @"开始我会盯盘，到现在感觉看那个东西非常无聊。亏损了就放着。赚了就体现。现在就这样。爱涨不涨。妨碍我干正事。";
    NSDictionary *reqParams = @{ 
        @"text": text,
        // 🚀 移除model参数，使用默认更快的模型
        @"speaker": @"zh_female_cancan_mars_bigtts", // 🚀 使用更简单的发音人
        @"streaming": @YES, // 🚀 启用流式模式，最关键的优化！
        @"audio_params": @{ 
            @"format": @"pcm",
            @"sample_rate": @16000, 
            @"bit_rate": @16000,
            @"buffer_size": @512 // 🚀 减小缓冲区，更快开始播放
        } 
    };
    NSDictionary *payload = @{ 
        @"user": @{ @"uid": @"ios_demo_user" },
        @"req_params": reqParams 
    };
    NSLog(@"🔥 [TTS] TaskRequest payload: %@", payload);
    [self _volcSendEventJSON:201 connectionId:nil sessionId:sessionId payload:payload];
}

- (void)_volcSendStartConnection
{
    NSLog(@"🔥 [TTS] Sending StartConnection (Event=1)");
    NSDictionary *payload = @{}; // StartConnection使用空payload
    [self _volcSendEventJSON:1 connectionId:nil sessionId:nil payload:payload];
}

- (void)_volcSendEventJSON:(int)event connectionId:(NSString *)connectionId sessionId:(NSString *)sessionId payload:(NSDictionary *)payload
{
    if (!self.volcWS) { 
        NSLog(@"🔥 [TTS] ❌ Cannot send message: WebSocket is nil");
        return; 
    }
    if (self.volcWS.state != NSURLSessionTaskStateRunning) {
        NSLog(@"🔥 [TTS] ❌ Cannot send message: WebSocket state is %ld (not running)", (long)self.volcWS.state);
        return;
    }
    // 构造二进制帧：header(4) + event(4) + [session_id_len(4)+session_id] + payload_len(4) + payload_json
    // Header:
    // byte0: 0x11 (protocol v1, header size 4)
    // byte1: 0x14 (Full-client request with event number)
    // byte2: 0x10 (JSON, no compression)
    // byte3: 0x00 (reserved)
    NSMutableData *frame = [NSMutableData dataWithCapacity:256];
    uint8_t header[4] = {0x11, 0x14, 0x10, 0x00};
    [frame appendBytes:header length:4];

    // event (int32 big-endian)
    uint32_t ev = (uint32_t)event;
    uint8_t evBE[4] = { (uint8_t)((ev >> 24) & 0xFF), (uint8_t)((ev >> 16) & 0xFF), (uint8_t)((ev >> 8) & 0xFF), (uint8_t)(ev & 0xFF) };
    [frame appendBytes:evBE length:4];

    // optional: session id
    if (sessionId.length > 0) {
        NSData *sidData = [sessionId dataUsingEncoding:NSUTF8StringEncoding];
        uint32_t sidLen = (uint32_t)sidData.length;
        uint8_t lenBE[4] = { (uint8_t)((sidLen >> 24) & 0xFF), (uint8_t)((sidLen >> 16) & 0xFF), (uint8_t)((sidLen >> 8) & 0xFF), (uint8_t)(sidLen & 0xFF) };
        [frame appendBytes:lenBE length:4];
        [frame appendData:sidData];
    }

    // payload JSON
    NSMutableDictionary *json = [NSMutableDictionary dictionary];
    if (payload) { [json addEntriesFromDictionary:payload]; }
    NSError *err = nil;
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:json options:0 error:&err];
    if (err || !payloadData) { return; }
    uint32_t pLen = (uint32_t)payloadData.length;
    uint8_t pLenBE[4] = { (uint8_t)((pLen >> 24) & 0xFF), (uint8_t)((pLen >> 16) & 0xFF), (uint8_t)((pLen >> 8) & 0xFF), (uint8_t)(pLen & 0xFF) };
    [frame appendBytes:pLenBE length:4];
    [frame appendData:payloadData];

    NSURLSessionWebSocketMessage *msg = [[NSURLSessionWebSocketMessage alloc] initWithData:frame];
    [self.volcWS sendMessage:msg completionHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"🔥 [TTS] ❌ Failed to send WebSocket message: %@", error.localizedDescription);
        } else {
            NSLog(@"🔥 [TTS] ✅ Successfully sent WebSocket message (Event=%d)", event);
        }
    }];
}

#pragma mark - NSURLSessionWebSocketDelegate

- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask didOpenWithProtocol:(NSString *)protocol {
    NSLog(@"🔥 [TTS] ✅ WebSocket connection established with protocol: %@", protocol ?: @"(none)");
    
    // 🚀 记录WebSocket连接成功时间
    self.wsConnectedTime = [NSDate date];
    if (self.requestStartTime) {
        NSTimeInterval connectionLatency = [self.wsConnectedTime timeIntervalSinceDate:self.requestStartTime];
        NSLog(@"🚀 [PERF] 🌐 WebSocket connected in: %.0f ms", connectionLatency * 1000);
    }
}

- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask didCloseWithCode:(NSURLSessionWebSocketCloseCode)closeCode reason:(NSData *)reason {
    NSString *reasonString = reason ? [[NSString alloc] initWithData:reason encoding:NSUTF8StringEncoding] : @"(none)";
    NSLog(@"🔥 [TTS] ❌ WebSocket connection closed with code: %ld, reason: %@", (long)closeCode, reasonString);
    
    self.volcRunning = NO;
    self.volcWS = nil;
    self.volcSession = nil;
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) {
        NSLog(@"🔥 [TTS] ❌ WebSocket task completed with error: %@", error.localizedDescription);
        self.volcRunning = NO;
    }
}

#pragma mark - 🔄 中转服务简化处理方法

- (void)_proxyStartIfNeeded
{
    NSLog(@"🔄 [PROXY] _proxyStartIfNeeded called");
    if (self.volcSession && self.volcWS) { 
        NSLog(@"🔄 [PROXY] WebSocket already exists, skipping initialization");
        return; 
    }
    NSLog(@"🔄 [PROXY] ⚡ Creating WebSocket connection to proxy: %@", kVolcWSURL);
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest = 10;
    cfg.timeoutIntervalForResource = 15;
    cfg.allowsCellularAccess = YES;
    cfg.waitsForConnectivity = NO;
    
    self.volcSession = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
    self.volcWS = [self.volcSession webSocketTaskWithURL:[NSURL URLWithString:kVolcWSURL]];
    [self.volcWS resume];
    self.volcRunning = YES;
    NSLog(@"🔄 [PROXY] WebSocket started, volcRunning = YES");
    
    // 开启数字人播放
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"🔄 [PROXY] Starting digital human on main queue");
        [[GJLDigitalManager manager] newSession];
        [[GJLDigitalManager manager] startPlaying];
    });
}

- (void)_proxyReceiveLoop
{
    if (!self.volcWS || !self.volcRunning) { 
        NSLog(@"❌ [PROXY] _proxyReceiveLoop: WebSocket not ready (WS=%@, Running=%d)", self.volcWS ? @"YES" : @"NO", self.volcRunning);
        return; 
    }
    NSLog(@"🔄 [PROXY] Starting receive loop");
    __weak typeof(self) weakSelf = self;
    [self.volcWS receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage * _Nullable message, NSError * _Nullable error) {
        if (error) {
            NSLog(@"❌ [PROXY] WebSocket error: %@", error.localizedDescription);
            weakSelf.volcRunning = NO;
            [[GJLDigitalManager manager] finishSession];
            return;
        }
        if (message) {
            [weakSelf _proxyHandleMessage:message];
        }
        [weakSelf _proxyReceiveLoop];
    }];
}

- (void)_proxySendTTSRequest:(NSString *)text
{
    NSLog(@"🔄 [PROXY] Sending TTS request: %@", text);
    NSDictionary *request = @{
        @"type": @"tts_request",
        @"text": text
    };
    
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:request options:0 error:&error];
    if (error) {
        NSLog(@"❌ [PROXY] JSON serialization error: %@", error.localizedDescription);
        return;
    }
    
    NSURLSessionWebSocketMessage *message = [[NSURLSessionWebSocketMessage alloc] initWithData:jsonData];
    [self.volcWS sendMessage:message completionHandler:^(NSError * _Nullable sendError) {
        if (sendError) {
            NSLog(@"❌ [PROXY] Failed to send TTS request: %@", sendError.localizedDescription);
        } else {
            NSLog(@"✅ [PROXY] TTS request sent successfully");
        }
    }];
}

- (void)_proxyHandleMessage:(NSURLSessionWebSocketMessage *)message
{
    NSLog(@"🔄 [PROXY] Received message type: %ld", (long)message.type);
    
    if (message.type == NSURLSessionWebSocketMessageTypeString) {
        NSLog(@"🔄 [PROXY] String message: %@", message.string);
        
        NSError *error;
        NSData *jsonData = [message.string dataUsingEncoding:NSUTF8StringEncoding];
        id jsonObj = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
        
        if (error) {
            NSLog(@"❌ [PROXY] JSON parse error: %@", error.localizedDescription);
            return;
        }
        
        if ([jsonObj isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)jsonObj;
            NSString *type = dict[@"type"];
            
            if ([@"welcome" isEqualToString:type]) {
                NSLog(@"🔄 [PROXY] ✅ Welcome received, client_id: %@", dict[@"client_id"]);
                
                // 🚀 记录WebSocket连接成功时间
                self.wsConnectedTime = [NSDate date];
                if (self.requestStartTime) {
                    NSTimeInterval connectionLatency = [self.wsConnectedTime timeIntervalSinceDate:self.requestStartTime];
                    NSLog(@"🚀 [PERF] 🌐 Proxy connected in: %.0f ms", connectionLatency * 1000);
                }
            }
            else if ([@"tts_start" isEqualToString:type]) {
                NSLog(@"🔄 [PROXY] ✅ TTS started, session_id: %@", dict[@"session_id"]);
                
                // 🚀 记录会话开始时间
                self.sessionStartTime = [NSDate date];
                if (self.wsConnectedTime) {
                    NSTimeInterval sessionStartLatency = [self.sessionStartTime timeIntervalSinceDate:self.wsConnectedTime];
                    NSLog(@"🚀 [PERF] 🎬 Session started in: %.0f ms", sessionStartLatency * 1000);
                }
            }
            else if ([@"audio_chunk" isEqualToString:type]) {
                NSString *base64Audio = dict[@"audio_data"];
                if (base64Audio) {
                    NSData *audioData = [[NSData alloc] initWithBase64EncodedString:base64Audio options:0];
                    if (audioData) {
                        // 🚀 【计时结束】记录首次收到音频的时间
                        if (!self.firstAudioTime) {
                            self.firstAudioTime = [NSDate date];
                            NSLog(@"🚀 [PERF] 🎯 FIRST AUDIO RECEIVED via PROXY!");
                            
                            if (self.requestStartTime) {
                                NSTimeInterval totalLatency = [self.firstAudioTime timeIntervalSinceDate:self.requestStartTime];
                                NSLog(@"🚀 [PERF] 📊 🎯 TOTAL (Request → Audio): %.0f ms", totalLatency * 1000);
                            }
                        }
                        
                        NSLog(@"🔄 [PROXY] 🎵 Received audio: %lu bytes - PLAYING!", (unsigned long)audioData.length);
                        
                        // 立即播放音频
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[GJLDigitalManager manager] toWavPcmData:audioData];
                        });
                    }
                }
            }
            else if ([@"tts_end" isEqualToString:type]) {
                NSLog(@"🔄 [PROXY] ✅ TTS completed");
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[GJLDigitalManager manager] finishSession];
                });
            }
            else if ([@"error" isEqualToString:type]) {
                NSLog(@"❌ [PROXY] Server error: %@", dict[@"message"]);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[GJLDigitalManager manager] finishSession];
                });
            }
        }
    }
    else if (message.type == NSURLSessionWebSocketMessageTypeData) {
        NSLog(@"🔄 [PROXY] Binary message received: %lu bytes", (unsigned long)message.data.length);
        // 中转服务应该只发送JSON，不应该有二进制消息
    }
}

@end
