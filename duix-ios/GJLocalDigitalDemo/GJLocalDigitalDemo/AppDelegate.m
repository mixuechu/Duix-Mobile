//
//  AppDelegate.m
//  GJLocalDigitalDemo
//
//  Created by guiji on 2023/12/12.
//

#import "AppDelegate.h"
#import "GJLPLAssetReader/GJLWebSocketManager.h"
#import "GJLConfig.h"

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.vc=[[ViewController alloc] init];
    UINavigationController * nav=[[UINavigationController alloc] initWithRootViewController:self.vc];
    self.window.rootViewController=nav;
    [self.window makeKeyAndVisible];
    
    // 🚀 App启动后延迟30秒预连接WebSocket作为备用（主要预热在点击开始按钮时）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSLog(@"🚀 [APP] 🔄 Backup WebSocket pre-connection (in case user hasn't clicked start yet)");
        [[GJLWebSocketManager sharedManager] preConnectToURL:[GJLConfig webSocketURL]];
    });
    
    return YES;
}





@end
