//
//  GJLPCMManager.h
//  GJLocalDigitalDemo
//
//  Created by guiji on 2025/5/12.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GJLPCMManager : NSObject <NSURLSessionWebSocketDelegate>
+ (GJLPCMManager *)manager;

// 🚀 性能计时属性
@property (nonatomic, strong) NSDate *requestStartTime;    // 请求开始时间
@property (nonatomic, strong) NSDate *wsConnectedTime;     // WebSocket连接成功时间
@property (nonatomic, strong) NSDate *sessionStartTime;    // 会话开始时间
@property (nonatomic, strong) NSDate *firstAudioTime;      // 首次收到音频时间
/*
 wavPath 音频的本地路径
 *1通道 16位深 16000采样率的wav本地文件和在线音频wav文件
 */
-(void)toSpeakWithPath:(NSString*)wavPath;

- (void)toStop;

-(void)toStopAudioTimer2;
// 通过火山TTS双向流式按文本合成并推流到数字人口型
- (void)toSpeakTextWithVolc:(NSString *)text;
@end

NS_ASSUME_NONNULL_END
