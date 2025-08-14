//
//  GJLConfig.h
//  GJLocalDigitalDemo
//
//  Created by System on 2024/01/01.
//  Copyright © 2024 GJLocalDigitalDemo. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 统一配置文件
 * 在这里修改所有的Cloudflare URL，只需要修改一个地方
 */
@interface GJLConfig : NSObject

#pragma mark - Cloudflare URLs
// 在这里修改您的Cloudflare URL
// 请将下面的URL替换为您的实际Cloudflare URL
+ (NSString *)cloudflareBaseURL;

#pragma mark - WebSocket Configuration
+ (NSString *)webSocketURL;
+ (NSString *)httpURL;
+ (NSString *)httpsURL;

@end

NS_ASSUME_NONNULL_END 