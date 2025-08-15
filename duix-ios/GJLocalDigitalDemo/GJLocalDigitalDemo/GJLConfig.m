//
//  GJLConfig.m
//  GJLocalDigitalDemo
//
//  Created by System on 2024/01/01.
//  Copyright © 2024 GJLocalDigitalDemo. All rights reserved.
//

#import "GJLConfig.h"

@implementation GJLConfig

#pragma mark - Cloudflare URLs

+ (NSString *)cloudflareBaseURL {
    // ==========================================
    // 重要：在这里修改您的Cloudflare URL
    // 只需要修改这一个地方，其他URL会自动更新
    // ==========================================
    return @"https://intimate-with-howto-keeping.trycloudflare.com";
    
    // 示例：
    // return @"https://your-app.cloudflare.com";
    // return @"https://your-domain.com";
}

#pragma mark - WebSocket Configuration

+ (NSString *)webSocketURL {
    NSString *baseURL = [self cloudflareBaseURL];
    // 将 https:// 替换为 wss:// 用于WebSocket
    NSString *wsURL = [baseURL stringByReplacingOccurrencesOfString:@"https://" withString:@"wss://"];
    return [NSString stringWithFormat:@"%@/ws", wsURL];
}

+ (NSString *)httpURL {
    NSString *baseURL = [self cloudflareBaseURL];
    // 将 https:// 替换为 http://
    return [baseURL stringByReplacingOccurrencesOfString:@"https://" withString:@"http://"];
}

+ (NSString *)httpsURL {
    return [self cloudflareBaseURL];
}

@end 