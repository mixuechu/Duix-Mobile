//
//  GJLWebSocketManager.m
//  GJLocalDigitalDemo
//
//  Created by Assistant on 2025/01/14.
//

#import "GJLWebSocketManager.h"
#import "GJLConfig.h"

@interface GJLWebSocketManager () <NSURLSessionWebSocketDelegate>

@property (nonatomic, strong) NSURLSessionWebSocketTask *activeWebSocket;
@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, assign) BOOL isConnecting;
@property (nonatomic, assign) GJLWebSocketConnectionState connectionState; // 🚀 新增状态属性
@property (nonatomic, strong) NSURLSession *urlSession;
@property (nonatomic, strong) NSString *currentURL;
@property (nonatomic, strong) NSMutableArray<GJLWebSocketConnectCompletion> *pendingCompletions;
@property (nonatomic, strong) NSTimer *heartbeatTimer;
@property (nonatomic, strong) NSDate *connectionStartTime;
@property (nonatomic, strong) dispatch_queue_t wsQueue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, GJLWebSocketStateChangeHandler> *stateChangeHandlers; // 🚀 状态监听

@end

@implementation GJLWebSocketManager

+ (instancetype)sharedManager {
    static GJLWebSocketManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[GJLWebSocketManager alloc] init];
    });
    return instance;
}

#pragma mark - Configuration Methods

// 使用配置文件中的WebSocket URL进行预连接
+ (void)preConnectWithConfig {
    NSString *wsURL = [GJLConfig webSocketURL];
    [[self sharedManager] preConnectToURL:wsURL];
}

// 使用配置文件中的WebSocket URL确保连接
+ (void)ensureConnectionWithConfig:(GJLWebSocketConnectCompletion)completion {
    NSString *wsURL = [GJLConfig webSocketURL];
    [[self sharedManager] ensureConnectionToURL:wsURL completion:completion];
}

// 获取当前配置的WebSocket URL
+ (NSString *)currentWebSocketURL {
    return [GJLConfig webSocketURL];
}

// 🚀 新增状态查询方法
+ (GJLWebSocketConnectionState)currentConnectionState {
    return [[self sharedManager] connectionState];
}

+ (BOOL)isConnectionReady {
    GJLWebSocketManager *manager = [self sharedManager];
    return manager.isConnected && manager.connectionState == GJLWebSocketConnectionStateConnected;
}

// 🚀 新增带回调的预连接
+ (void)preConnectWithConfigCompletion:(GJLWebSocketConnectCompletion)completion {
    NSString *wsURL = [GJLConfig webSocketURL];
    [[self sharedManager] preConnectToURL:wsURL completion:completion];
}

// 🚀 新增状态监听方法
+ (void)addStateChangeHandler:(GJLWebSocketStateChangeHandler)handler withIdentifier:(NSString *)identifier {
    GJLWebSocketManager *manager = [self sharedManager];
    dispatch_async(manager.wsQueue, ^{
        manager.stateChangeHandlers[identifier] = [handler copy];
    });
}

+ (void)removeStateChangeHandlerWithIdentifier:(NSString *)identifier {
    GJLWebSocketManager *manager = [self sharedManager];
    dispatch_async(manager.wsQueue, ^{
        [manager.stateChangeHandlers removeObjectForKey:identifier];
    });
}

#pragma mark - State Management

// 🚀 状态变化通知方法
- (void)_notifyStateChange:(GJLWebSocketConnectionState)newState error:(NSError *)error {
    self.connectionState = newState;
    
    // 通知所有监听者
    for (NSString *identifier in self.stateChangeHandlers) {
        GJLWebSocketStateChangeHandler handler = self.stateChangeHandlers[identifier];
        if (handler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                handler(newState, error);
            });
        }
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _pendingCompletions = [NSMutableArray array];
        _stateChangeHandlers = [NSMutableDictionary dictionary]; // 🚀 初始化状态监听字典
        _connectionState = GJLWebSocketConnectionStateDisconnected; // 🚀 初始化连接状态
        _wsQueue = dispatch_queue_create("com.gjl.websocket", DISPATCH_QUEUE_SERIAL);
        
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 30.0;
        config.timeoutIntervalForResource = 60.0;
        _urlSession = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    }
    return self;
}

- (void)preConnectToURL:(NSString *)urlString {
    dispatch_async(self.wsQueue, ^{
        if (self.isConnected || self.isConnecting) {
            NSLog(@"🔄 [WS] PreConnect skipped: already connected/connecting");
            return;
        }
        
        NSLog(@"🚀 [WS] 🔥 PreConnect starting to: %@", urlString);
        [self _connectToURL:urlString completion:^(BOOL success, NSError *error) {
            if (success) {
                NSLog(@"🚀 [WS] ✅ PreConnect SUCCESS!");
            } else {
                NSLog(@"❌ [WS] PreConnect FAILED: %@", error.localizedDescription);
            }
        }];
    });
}

// 🚀 新增带完成回调的预连接方法
- (void)preConnectToURL:(NSString *)urlString completion:(GJLWebSocketConnectCompletion)completion {
    dispatch_async(self.wsQueue, ^{
        if (self.isConnected || self.isConnecting) {
            NSLog(@"🔄 [WS] PreConnect skipped: already connected/connecting");
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(self.isConnected, nil);
                });
            }
            return;
        }
        
        NSLog(@"🚀 [WS] 🔥 PreConnect starting to: %@", urlString);
        [self _connectToURL:urlString completion:^(BOOL success, NSError *error) {
            if (success) {
                NSLog(@"🚀 [WS] ✅ PreConnect SUCCESS!");
            } else {
                NSLog(@"❌ [WS] PreConnect FAILED: %@", error.localizedDescription);
            }
            
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(success, error);
                });
            }
        }];
    });
}

- (void)ensureConnectionToURL:(NSString *)urlString completion:(GJLWebSocketConnectCompletion)completion {
    dispatch_async(self.wsQueue, ^{
        // 如果已经连接到同一个URL，直接返回成功
        if (self.isConnected && [self.currentURL isEqualToString:urlString]) {
            NSLog(@"🚀 [WS] ✅ Connection REUSED! No delay needed.");
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(YES, nil);
            });
            return;
        }
        
        // 添加到等待队列
        [self.pendingCompletions addObject:[completion copy]];
        
        // 如果正在连接到同一个URL，直接等待
        if (self.isConnecting && [self.currentURL isEqualToString:urlString]) {
            NSLog(@"🔄 [WS] Connection in progress, waiting...");
            return;
        }
        
        // 需要新建连接
        if (self.isConnected || self.isConnecting) {
            NSLog(@"🔄 [WS] Disconnecting old connection");
            [self _disconnect];
        }
        
        NSLog(@"🚀 [WS] 🔗 EnsureConnection starting to: %@", urlString);
        [self _connectToURL:urlString completion:nil];
    });
}

- (void)_connectToURL:(NSString *)urlString completion:(GJLWebSocketConnectCompletion)completion {
    if (completion) {
        [self.pendingCompletions addObject:[completion copy]];
    }
    
    self.isConnecting = YES;
    self.currentURL = urlString;
    self.connectionStartTime = [NSDate date];
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    
    self.activeWebSocket = [self.urlSession webSocketTaskWithRequest:request];
    [self.activeWebSocket resume];
    
    NSLog(@"🔄 [WS] WebSocket task started");
}

- (void)sendMessage:(NSURLSessionWebSocketMessage *)message completion:(void (^)(NSError * _Nullable))completion {
    dispatch_async(self.wsQueue, ^{
        if (!self.isConnected || !self.activeWebSocket) {
            NSError *error = [NSError errorWithDomain:@"GJLWebSocketManager" 
                                                 code:-1 
                                             userInfo:@{NSLocalizedDescriptionKey: @"WebSocket not connected"}];
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(error);
                });
            }
            return;
        }
        
        [self.activeWebSocket sendMessage:message completionHandler:^(NSError *error) {
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(error);
                });
            }
        }];
    });
}

- (void)startReceiveLoop {
    dispatch_async(self.wsQueue, ^{
        [self _receiveNextMessage];
    });
}

- (void)_receiveNextMessage {
    if (!self.activeWebSocket || !self.isConnected) {
        return;
    }
    
    __weak typeof(self) weakSelf = self;
    [self.activeWebSocket receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (error) {
            NSLog(@"❌ [WS] Receive error: %@", error.localizedDescription);
            dispatch_async(strongSelf.wsQueue, ^{
                [strongSelf _handleDisconnection];
            });
            return;
        }
        
        if (message && strongSelf.messageHandler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                strongSelf.messageHandler(message);
            });
        }
        
        // 继续接收下一条消息
        dispatch_async(strongSelf.wsQueue, ^{
            [strongSelf _receiveNextMessage];
        });
    }];
}

- (void)disconnect {
    dispatch_async(self.wsQueue, ^{
        [self _disconnect];
    });
}

- (void)_disconnect {
    [self _stopHeartbeat];
    
    if (self.activeWebSocket) {
        [self.activeWebSocket cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
        self.activeWebSocket = nil;
    }
    
    self.isConnected = NO;
    self.isConnecting = NO;
    self.currentURL = nil;
}

- (void)_handleDisconnection {
    NSLog(@"🔄 [WS] Handling disconnection");
    [self _disconnect];
    
    // 通知所有等待的completion
    NSArray *completions = [self.pendingCompletions copy];
    [self.pendingCompletions removeAllObjects];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        for (GJLWebSocketConnectCompletion completion in completions) {
            NSError *error = [NSError errorWithDomain:@"GJLWebSocketManager" 
                                                 code:-2 
                                             userInfo:@{NSLocalizedDescriptionKey: @"Connection lost"}];
            completion(NO, error);
        }
    });
}

- (void)_startHeartbeat {
    [self _stopHeartbeat];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 
                                                               target:self 
                                                             selector:@selector(_sendPing) 
                                                             userInfo:nil 
                                                              repeats:YES];
    });
}

- (void)_stopHeartbeat {
    if (self.heartbeatTimer) {
        [self.heartbeatTimer invalidate];
        self.heartbeatTimer = nil;
    }
}

- (void)_sendPing {
    dispatch_async(self.wsQueue, ^{
        if (self.isConnected && self.activeWebSocket) {
            [self.activeWebSocket sendPingWithPongReceiveHandler:^(NSError *error) {
                if (error) {
                    NSLog(@"❌ [WS] Ping failed: %@", error.localizedDescription);
                    [self _handleDisconnection];
                }
            }];
        }
    });
}

#pragma mark - NSURLSessionWebSocketDelegate

- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask didOpenWithProtocol:(NSString *)protocol {
    dispatch_async(self.wsQueue, ^{
        NSTimeInterval connectionTime = [[NSDate date] timeIntervalSinceDate:self.connectionStartTime] * 1000;
        
        self.isConnected = YES;
        self.isConnecting = NO;
        
        NSLog(@"🔥 [WS] ✅ WebSocket connection established with protocol: %@", protocol ?: @"(none)");
        NSLog(@"🚀 [PERF] 🌐 WebSocket connected in: %.0f ms", connectionTime);
        
        // 启动心跳
        [self _startHeartbeat];
        
        // 通知所有等待的completion
        NSArray *completions = [self.pendingCompletions copy];
        [self.pendingCompletions removeAllObjects];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            for (GJLWebSocketConnectCompletion completion in completions) {
                completion(YES, nil);
            }
        });
    });
}

- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask didCloseWithCode:(NSURLSessionWebSocketCloseCode)closeCode reason:(NSData *)reason {
    dispatch_async(self.wsQueue, ^{
        NSLog(@"🔄 [WS] WebSocket closed with code: %ld", (long)closeCode);
        [self _handleDisconnection];
    });
}

- (void)dealloc {
    [self _disconnect];
}

@end 