//
//  GJLWebSocketManager.h
//  GJLocalDigitalDemo
//
//  Created by Assistant on 2025/01/14.
//

#import <Foundation/Foundation.h>
#import "GJLConfig.h"

NS_ASSUME_NONNULL_BEGIN

@class GJLWebSocketManager;

// 连接状态枚举
typedef NS_ENUM(NSInteger, GJLWebSocketConnectionState) {
    GJLWebSocketConnectionStateDisconnected = 0,
    GJLWebSocketConnectionStateConnecting,
    GJLWebSocketConnectionStateConnected,
    GJLWebSocketConnectionStateError
};

// 状态变化回调
typedef void(^GJLWebSocketStateChangeHandler)(GJLWebSocketConnectionState state, NSError * _Nullable error);

typedef void(^GJLWebSocketConnectCompletion)(BOOL success, NSError * _Nullable error);
typedef void(^GJLWebSocketMessageHandler)(NSURLSessionWebSocketMessage *message);

@interface GJLWebSocketManager : NSObject

@property (nonatomic, strong, readonly) NSURLSessionWebSocketTask * _Nullable activeWebSocket;
@property (nonatomic, assign, readonly) GJLWebSocketConnectionState connectionState; // 🚀 新增状态属性
@property (nonatomic, copy) GJLWebSocketMessageHandler messageHandler; // 消息处理回调

+ (instancetype)sharedManager;

// 🚀 新增状态查询方法
+ (GJLWebSocketConnectionState)currentConnectionState;
+ (BOOL)isConnectionReady; // 快速检查连接是否可用

// 🚀 新增状态监听方法
+ (void)addStateChangeHandler:(GJLWebSocketStateChangeHandler)handler withIdentifier:(NSString *)identifier;
+ (void)removeStateChangeHandlerWithIdentifier:(NSString *)identifier;

// Configuration-based methods (使用GJLConfig中的URL)
+ (void)preConnectWithConfig;
+ (void)preConnectWithConfigCompletion:(GJLWebSocketConnectCompletion)completion; // 🚀 新增带回调的预连接
+ (void)ensureConnectionWithConfig:(GJLWebSocketConnectCompletion)completion;
+ (NSString *)currentWebSocketURL;

// Direct URL methods
- (void)preConnectToURL:(NSString *)urlString;
- (void)preConnectToURL:(NSString *)urlString completion:(GJLWebSocketConnectCompletion)completion;
- (void)ensureConnectionToURL:(NSString *)urlString completion:(GJLWebSocketConnectCompletion)completion;
- (void)sendMessage:(NSURLSessionWebSocketMessage *)message completion:(void (^)(NSError * _Nullable))completion;
- (void)startReceiveLoop;
- (void)disconnect;

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