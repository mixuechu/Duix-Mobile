//
//  ViewController.m
//  GJLocalDigitalDemo
//
//  Created by guiji on 2023/12/12.
//

#import "ViewController.h"
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#import "HttpClient.h"
#import "SVProgressHUD.h"
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Security/Security.h>
#import <GJLocalDigitalSDK/GJLocalDigitalSDK.h>

//#import <CoreTelephony/CTCellularData.h>
#import "GJCheckNetwork.h"
#import "SSZipArchive.h"
#import "GJDownWavTool.h"
#import "GYAccess.h"
#import "GJLPCMManager.h"
#import "GJLGCDNEWTimer.h"
#import "OpenUDID.h"
#import "UIColor+Expanded.h"
#import "ReadWavPCMViewController.h"
#import "GJLPLAssetReader/GJLWebSocketManager.h"
#import "GJLConfig.h"
//
//基础模型 git 地址下载较慢，请下载后自己管理加速
#define BASEMODELURL   @"https://github.com/GuijiAI/duix.ai/releases/download/v1.0.0/gj_dh_res.zip"
//数字人模型 git 地址下载较慢，请下载后自己管理加速
#define DIGITALMODELURL @"https://github.com/GuijiAI/duix.ai/releases/download/v1.0.0/bendi3_20240518.zip"



@interface ViewController ()<GJDownWavToolDelegate,UITextViewDelegate>
@property(nonatomic,strong)UIView *showView;
@property(nonatomic,strong)NSString * basePath;
@property(nonatomic,strong)NSString * digitalPath;
@property (nonatomic, assign) BOOL isRequest;
//基础模型
@property (nonatomic, strong)UITextView * baseTextView;
//数字人模型
@property (nonatomic, strong)UITextView * digitalTextView;
// 🎨 开始按钮属性，用于控制加载状态
@property (nonatomic, strong) UIButton *startButton;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor=[UIColor whiteColor];
  
    UILabel *titleLabel=[[UILabel alloc] initWithFrame:CGRectMake(20, 150,self.view.frame.size.width-40,44)];
    titleLabel.text=@"Github地址可能下载失败，您可以考虑将文件存放到自己的存储服务";
    titleLabel.textColor=[UIColor blackColor];
    titleLabel.textAlignment=NSTextAlignmentLeft;
    titleLabel.numberOfLines=0;
    [self.view addSubview:titleLabel];
    
    UILabel *label1=[[UILabel alloc] initWithFrame:CGRectMake(20, CGRectGetMaxY(titleLabel.frame)+20,self.view.frame.size.width-40,44)];
    label1.text=@"基础模型url:";
    label1.textColor=[UIColor blackColor];
    label1.textAlignment=NSTextAlignmentLeft;
    [self.view addSubview:label1];
    
    self.baseTextView=[[UITextView alloc] init];
     self.baseTextView.frame=CGRectMake(20,CGRectGetMaxY(label1.frame)+10, self.view.frame.size.width-40, 44);
    self.baseTextView.backgroundColor = [UIColor clearColor];
 //        _phoneTextField.layer.borderColor=[UIColor colorWithHexString:@"#FFFFFF" alpha:0.29].CGColor;
 //        _phoneTextField.layer.borderWidth=1;
     self.baseTextView.layer.masksToBounds = YES;
     self.baseTextView.delegate = self;
     self.baseTextView.layer.cornerRadius = 10;
     self.baseTextView.layer.borderColor = [UIColor redColor].CGColor;
     self.baseTextView.layer.borderWidth = 1;
     self.baseTextView.returnKeyType=UIReturnKeyDone;
    [self.view addSubview:self.baseTextView];
    

    
    UILabel *label4=[[UILabel alloc] initWithFrame:CGRectMake(20, CGRectGetMaxY(  self.baseTextView.frame)+20,self.view.frame.size.width-40,44)];
    label4.text=@"数字人模型url:";
    label4.textColor=[UIColor blackColor];
    label4.textAlignment=NSTextAlignmentLeft;
    [self.view addSubview:label4];
    
    self.digitalTextView=[[UITextView alloc] init];
     self.digitalTextView.frame=CGRectMake(20,CGRectGetMaxY(label4.frame)+10, self.view.frame.size.width-40, 44);
    self.digitalTextView.backgroundColor = [UIColor clearColor];
 //        _phoneTextField.layer.borderColor=[UIColor colorWithHexString:@"#FFFFFF" alpha:0.29].CGColor;
 //        _phoneTextField.layer.borderWidth=1;
     self.digitalTextView.layer.masksToBounds = YES;
     self.digitalTextView.delegate = self;
     self.digitalTextView.layer.cornerRadius = 10;
     self.digitalTextView.layer.borderColor = [UIColor redColor].CGColor;
     self.digitalTextView.layer.borderWidth = 1;
     self.digitalTextView.returnKeyType=UIReturnKeyDone;

    [self.view addSubview:self.digitalTextView];

    
    self.startButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.startButton.frame = CGRectMake(40, self.view.frame.size.height-200, self.view.frame.size.width-80, 40);
    [self.startButton setTitle:@"开始体验数字人" forState:UIControlStateNormal];
    [self.startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.startButton setBackgroundColor:[UIColor systemBlueColor]];
    self.startButton.layer.cornerRadius = 8;
    self.startButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.startButton addTarget:self action:@selector(toStartWav) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.startButton];
    
    NSUserDefaults * defaults=[NSUserDefaults standardUserDefaults];
    self.baseTextView.text=[defaults objectForKey:@"BASEMODELURL"]?:BASEMODELURL;
    NSLog(@"DIGITALMODELURLKEY:%@",[defaults objectForKey:@"DIGITALMODELURLKEY"]);
    self.digitalTextView.text=[defaults objectForKey:@"DIGITALMODELURLKEY"]?:DIGITALMODELURL;



 


    [[GJCheckNetwork manager] getWifiState];
    __weak typeof(self)weakSelf = self;
    [GJCheckNetwork manager].on_net = ^(NetType state) {
        if (state == Net_WWAN
            || state == Net_WiFi) {
            if (!weakSelf.isRequest) {
                weakSelf.isRequest = YES;
   
                [weakSelf isDownModel];
            }
        }
    };
   



 
    

}

-(void)toStartWav
{
    if(![self isFileExit])
    {
        return;
    }
    
    // 🚀 检查连接状态，如果已经准备好，直接跳转
    if ([GJLWebSocketManager isConnectionReady]) {
        NSLog(@"🚀 [USER] Connection already ready, jumping directly");
        [self _showPlayViewController];
        return;
    }
    
    // 🔥 用户点击开始时立即预热WebSocket连接，并提供状态反馈
    NSLog(@"🚀 [USER] Start button clicked, pre-warming WebSocket for TTS");
    
    // 🎨 按钮状态控制 - 防止重复点击
    self.startButton.enabled = NO;
    [self.startButton setTitle:@"正在连接..." forState:UIControlStateNormal];
    [self.startButton setBackgroundColor:[UIColor systemGrayColor]];
    
    // 🎨 显示优雅的加载动画
    [SVProgressHUD showWithStatus:@"正在连接数字人服务..."];
    [SVProgressHUD setDefaultMaskType:SVProgressHUDMaskTypeBlack]; // 防止用户多次点击
    
    // 🚀 使用带回调的预连接方法
    [GJLWebSocketManager preConnectWithConfigCompletion:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // 🎨 恢复按钮状态
            self.startButton.enabled = YES;
            [self.startButton setTitle:@"开始体验数字人" forState:UIControlStateNormal];
            [self.startButton setBackgroundColor:[UIColor systemBlueColor]];
            
            // 🎨 隐藏加载动画
            [SVProgressHUD dismiss];
            
            if (success) {
                NSLog(@"🚀 [USER] ✅ WebSocket pre-warming completed successfully!");
                // 🎨 显示成功提示（短暂显示）
                [SVProgressHUD showSuccessWithStatus:@"连接成功！"];
                
                // 延迟一点点让用户看到成功状态
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [SVProgressHUD dismiss];
                    [self _showPlayViewController];
                });
            } else {
                NSLog(@"❌ [USER] WebSocket pre-warming failed: %@", error.localizedDescription);
                // 🎨 显示连接失败但仍继续的提示
                [SVProgressHUD showInfoWithStatus:@"连接异常，但仍可使用"];
                
                // 延迟后进入播放界面
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [SVProgressHUD dismiss];
                    // 即使预热失败，也继续进入播放界面，运行时再尝试连接
                    [self _showPlayViewController];
                });
            }
        });
    }];
}

- (void)_showPlayViewController {
    ReadWavPCMViewController * vc=[[ReadWavPCMViewController alloc] init];
    vc.basePath=self.basePath;
    vc.digitalPath=self.digitalPath;
 
    vc.modalPresentationStyle=UIModalPresentationFullScreen;
    [self presentViewController:vc animated:YES completion:^{
        NSLog(@"🎯 [UI] Switched to PlayViewController, connection state: %s", 
              [GJLWebSocketManager isConnectionReady] ? "READY" : "NOT_READY");
    }];
}

-(BOOL)isFileExit
{
    if(![[NSFileManager defaultManager] fileExistsAtPath:self.basePath]||self.baseTextView.text.length==0)
    {
        NSLog(@"基础模型不存在");
        [SVProgressHUD showInfoWithStatus:@"基础模型不存在"];
        return NO;
    }
    
    if(![[NSFileManager defaultManager] fileExistsAtPath:self.digitalPath]||self.digitalTextView.text.length==0)
    {
        NSLog(@"模版不存在");
        [SVProgressHUD showInfoWithStatus:@"模版不存在"];
        return NO;
    }
//    if(self.appIDTextField.text.length==0)
//    {
//        return NO;
//    }
//    if(self.appkeyTextField.text.length==0)
//    {
//        return NO;
//    }
    
    return YES;
}


-(void)isDownModel
{
    NSString *unzipPath = [self getHistoryCachePath:@"unZipCache"];
    NSString * baseName=[[self.baseTextView.text lastPathComponent] stringByDeletingPathExtension];
    self.basePath=[NSString stringWithFormat:@"%@/%@",unzipPath,baseName];
    
    NSString * digitalName=[[self.digitalTextView.text lastPathComponent] stringByDeletingPathExtension];
    self.digitalPath=[NSString stringWithFormat:@"%@/%@",unzipPath,digitalName];

    NSFileManager * fileManger=[NSFileManager defaultManager];
    if((![fileManger fileExistsAtPath:self.basePath])&&(![fileManger fileExistsAtPath:self.digitalPath]))
    {
        //下载基础模型和数字人模型
        [self toDownBaseModelAndDigital];

    }
   else if (![fileManger fileExistsAtPath:self.digitalPath])
    {
        //数字人模型
        [SVProgressHUD show];
        [SVProgressHUD setDefaultMaskType:SVProgressHUDMaskTypeBlack];
        [self toDownDigitalModel];
    }
    

}
//下载基础模型----不同的数字人模型使用同一个基础模型
-(void)toDownBaseModelAndDigital
{
    [SVProgressHUD show];
    [SVProgressHUD setDefaultMaskType:SVProgressHUDMaskTypeBlack];
    __weak typeof(self)weakSelf = self;
    NSString *zipPath = [self getHistoryCachePath:@"ZipCache"];
    //下载基础模型
    [[HttpClient manager] downloadWithURL:self.baseTextView.text savePathURL:[NSURL fileURLWithPath:zipPath] pathExtension:nil progress:^(NSProgress * progress) {
        double down_progress=(double)progress.completedUnitCount/(double)progress.totalUnitCount*0.5;
        [SVProgressHUD showProgress:down_progress status:@"正在下载基础模型"];
    } success:^(NSURLResponse *response, NSURL *filePath) {
        NSLog(@"filePath:%@",filePath);
        
        [weakSelf toUnzip:filePath.absoluteString];
        //下载数字人模型
        [weakSelf  toDownDigitalModel];
  
    } fail:^(NSError *error) {
        [SVProgressHUD showErrorWithStatus:error.localizedDescription];
    }];
}
-(void)toUnzip:(NSString*)filePath
{
    filePath=[filePath stringByReplacingOccurrencesOfString:@"file://" withString:@""];
    NSString *unzipPath = [self getHistoryCachePath:@"unZipCache"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),^{
        [SSZipArchive unzipFileAtPath:filePath toDestination:unzipPath progressHandler:^(NSString * _Nonnull entry, unz_file_info zipInfo, long entryNumber, long total) {
            
        } completionHandler:^(NSString * _Nonnull path, BOOL succeeded, NSError * _Nullable error) {
            NSLog(@"path:%@,%d",path,succeeded);
        
        }];
    });
 
 
}
//下载数字人模型
-(void)toDownDigitalModel
{
    __weak typeof(self)weakSelf = self;
    NSString *zipPath = [self getHistoryCachePath:@"ZipCache"];
    [[HttpClient manager] downloadWithURL:self.digitalTextView.text savePathURL:[NSURL fileURLWithPath:zipPath] pathExtension:nil progress:^(NSProgress * progress) {
        double down_progress=0.5+(double)progress.completedUnitCount/(double)progress.totalUnitCount*0.5;
        [SVProgressHUD showProgress:down_progress status:@"正在下载数字人模型"];
    } success:^(NSURLResponse *response, NSURL *filePath) {
        NSLog(@"filePath:%@",filePath);
        [weakSelf toUnzip:filePath.absoluteString];
        [SVProgressHUD showSuccessWithStatus:@"下载成功"];
    } fail:^(NSError *error) {
        [SVProgressHUD showErrorWithStatus:error.localizedDescription];
    }];
}



-(NSString *)getHistoryCachePath:(NSString*)pathName
{
    NSString* folderPath =[[self getFInalPath] stringByAppendingPathComponent:pathName];
    //创建文件管理器
    NSFileManager *fileManager = [NSFileManager defaultManager];
    //判断temp文件夹是否存在
    BOOL fileExists = [fileManager fileExistsAtPath:folderPath];
    //如果不存在说创建,因为下载时,不会自动创建文件夹
    if (!fileExists)
    {
        [fileManager createDirectoryAtPath:folderPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return folderPath;
}

- (NSString *)getFInalPath
{
    NSString* folderPath =[[NSHomeDirectory() stringByAppendingPathComponent:@"Library"] stringByAppendingPathComponent:@"GJCache"];
    //创建文件管理器
    NSFileManager *fileManager = [NSFileManager defaultManager];
    //判断temp文件夹是否存在
    BOOL fileExists = [fileManager fileExistsAtPath:folderPath];
    //如果不存在说创建,因为下载时,不会自动创建文件夹
    if (!fileExists) {
        [fileManager createDirectoryAtPath:folderPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    return folderPath;
}


- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    if ([text isEqualToString:@"\n"]) {
        NSUserDefaults * defaults=[NSUserDefaults standardUserDefaults];
        // 如果你想在按下 return 后不换行，可以返回 NO
        // return NO;
         if(textView==self.baseTextView)
        {
            [defaults setObject:textView.text forKey:@"BASEMODELURL"];
        }
        else if(textView==self.digitalTextView)
        {
            [defaults setObject:textView.text forKey:@"DIGITALMODELURLKEY"];
        }
        [defaults synchronize];
        [textView resignFirstResponder];
        [self isDownModel];
    }
    return YES; // 允许其他文本更改
}

@end
