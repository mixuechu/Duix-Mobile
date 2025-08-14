//
//  GJLWebSocketManager.h
//  GJLocalDigitalDemo
//
//  Created by Assistant on 2025/01/14.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^GJLWebSocketConnectCompletion)(BOOL success, NSError * _Nullable error);
typedef void(^GJLWebSocketMessageHandler)(NSURLSessionWebSocketMessage *message);

@interface GJLWebSocketManager : NSObject

@property (nonatomic, strong, readonly) NSURLSessionWebSocketTask * _Nullable activeWebSocket;
@property (nonatomic, assign, readonly) BOOL isConnected;
@property (nonatomic, assign, readonly) BOOL isConnecting;
@property (nonatomic, copy) GJLWebSocketMessageHandler messageHandler;

+ (instancetype)sharedManager;

// 预连接
- (void)preConnectToURL:(NSString *)urlString;

// 确保连接可用
- (void)ensureConnectionToURL:(NSString *)urlString completion:(GJLWebSocketConnectCompletion)completion;

// 发送消息
- (void)sendMessage:(NSURLSessionWebSocketMessage *)message completion:(void (^)(NSError * _Nullable))completion;

// 断开连接
- (void)disconnect;

// 开始接收消息循环
- (void)startReceiveLoop;

@end

NS_ASSUME_NONNULL_END 