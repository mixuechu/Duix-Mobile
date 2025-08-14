//
//  ReadWavPCMViewController.m
//  GJLocalDigitalDemo
//
//  Created by guiji on 2025/5/20.
//

#import "ReadWavPCMViewController.h"
#import <GJLocalDigitalSDK/GJLocalDigitalSDK.h>
#import "HttpClient.h"
#import "SVProgressHUD.h"
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "GJLPCMManager.h"
@interface ReadWavPCMViewController ()
@property(nonatomic,strong)UIView *showView;
@property (nonatomic, strong) UIImageView * imageView;
@property (nonatomic, assign)BOOL isMute;

@property (nonatomic, assign)BOOL isPause;
@end

@implementation ReadWavPCMViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self.view addSubview:self.imageView];
 
    [self.view addSubview:self.showView];
    
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord withOptions: AVAudioSessionCategoryOptionDefaultToSpeaker|AVAudioSessionCategoryOptionAllowBluetooth error:nil];
    [audioSession setPreferredIOBufferDuration:0.02 error:nil];
    [audioSession setActive:YES error:nil];
    

//    UIButton * startbtn=[UIButton buttonWithType:UIButtonTypeCustom];
//    startbtn.frame=CGRectMake(40, self.view.frame.size.height-100, 40, 40);
//    [startbtn setTitle:@"开始" forState:UIControlStateNormal];
//    [startbtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
//    [startbtn addTarget:self action:@selector(toStart) forControlEvents:UIControlEventTouchDown];
//    [self.view addSubview:startbtn];
    
    [self toDigitalBlock];
    [self toStart];
    
    
    UIButton * playbtn=[UIButton buttonWithType:UIButtonTypeCustom];
    playbtn.frame=CGRectMake(self.view.frame.size.width/2-120, self.view.frame.size.height-100, 40, 40);
    [playbtn setTitle:@"播放" forState:UIControlStateNormal];
    [playbtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [playbtn addTarget:self action:@selector(toRecord) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:playbtn];
    
    
//    UIButton * stopPlaybtn=[UIButton buttonWithType:UIButtonTypeCustom];
//    stopPlaybtn.frame=CGRectMake(CGRectGetMaxX(playbtn.frame)+20, self.view.frame.size.height-100, 40, 40);
//    [stopPlaybtn setTitle:@"停止" forState:UIControlStateNormal];
//    [stopPlaybtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
//    [stopPlaybtn addTarget:self action:@selector(toPlay) forControlEvents:UIControlEventTouchDown];
//    [self.view addSubview:stopPlaybtn];


    
    UIButton * pausebtn=[UIButton buttonWithType:UIButtonTypeCustom];
    pausebtn.frame=CGRectMake(CGRectGetMaxX(playbtn.frame)+20, self.view.frame.size.height-100, 40, 40);
    [pausebtn setTitle:@"暂停" forState:UIControlStateNormal];
    [pausebtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [pausebtn addTarget:self action:@selector(toPause) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:pausebtn];
    
    UIButton * resumebtn=[UIButton buttonWithType:UIButtonTypeCustom];
    resumebtn.frame=CGRectMake(CGRectGetMaxX(pausebtn.frame)+20, self.view.frame.size.height-100, 40, 40);
    [resumebtn setTitle:@"恢复" forState:UIControlStateNormal];
    [resumebtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [resumebtn addTarget:self action:@selector(toResume) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:resumebtn];
    
    UIButton * stopbtn=[UIButton buttonWithType:UIButtonTypeCustom];
    stopbtn.frame=CGRectMake(CGRectGetMaxX(resumebtn.frame)+20, self.view.frame.size.height-100, 40, 40);
    [stopbtn setTitle:@"结束" forState:UIControlStateNormal];
    [stopbtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [stopbtn addTarget:self action:@selector(toStop) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:stopbtn];
    // Do any additional setup after loading the view.
    
    UILabel*aiLabel=[[UILabel alloc] init];
    aiLabel.frame=CGRectMake(20, self.view.frame.size.height-40, self.view.frame.size.width-40, 20);
    aiLabel.text=@"本内容由AI生成，仅供参考";
    aiLabel.textColor=[UIColor redColor];
    aiLabel.textAlignment=NSTextAlignmentCenter;
    [self.view addSubview:aiLabel];
    

    
    // 注册中断通知
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleInterruption:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:[AVAudioSession sharedInstance]];
}

// 中断处理回调
- (void)handleInterruption:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    AVAudioSessionInterruptionType type = [userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    
    if (type == AVAudioSessionInterruptionTypeBegan) {
        // 中断开始：停止AudioUnit
        [[GJLDigitalManager manager] toStopRunning];
    } else {
        // 中断结束：检查是否需要恢复
        AVAudioSessionInterruptionOptions options = [userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
        if (options == AVAudioSessionInterruptionOptionShouldResume) {
            [[GJLDigitalManager manager] toStartRuning];
       
        }
    }
}
-(UIView*)showView
{
    if(nil==_showView)
    {
        _showView=[[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height)];
        _showView.backgroundColor=[UIColor clearColor];
    }
    return _showView;
}
-(UIImageView*)imageView
{
    if(nil==_imageView)
    {
        _imageView=[[UIImageView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height)];
        NSString *bgpath =[NSString stringWithFormat:@"%@/%@",[[NSBundle mainBundle] bundlePath],@"bg2.jpg"];
        _imageView.contentMode=UIViewContentModeScaleAspectFill;
        _imageView.image=[UIImage imageWithContentsOfFile:bgpath];
        
    }
    return _imageView;
}

-(void)toStart
{
    __weak typeof(self)weakSelf = self;
    //授权
//    [[GJLDigitalManager manager] toEnableRecord:NO];
//    [GJLDigitalManager manager].backType=1;

            NSInteger result=   [[GJLDigitalManager manager] initBaseModel:weakSelf.basePath digitalModel:self.digitalPath showView:weakSelf.showView];
             if(result==1)
             {
                //开始
 //                NSString *bgpath =[NSString stringWithFormat:@"%@/%@",[[NSBundle mainBundle] bundlePath],@"bg2.jpg"];
 //                [[GJLDigitalManager manager] toChangeBBGWithPath:bgpath];
                 [[GJLDigitalManager manager] toStart:^(BOOL isSuccess, NSString *errorMsg) {
                     if(isSuccess)
                     {
//                         [[GJLDigitalManager manager] toSetVolume:0];
                         [[GJLDigitalManager manager] toStartRuning];
              
                     }
                     else
                     {
                         [SVProgressHUD showInfoWithStatus:errorMsg];
                   
                     }
                 }];
             }
  
  
}


//播放音频
-(void)toRecord
{

//    [[GJLDigitalManager manager] toRandomMotion];
//    [[GJLDigitalManager manager] toStartMotion];
    //清空累计的buffer ，initSession里面已经调用，根据业务调整调用clearAudioBuffer
    [[GJLPCMManager manager] toStop];
    [[GJLDigitalManager manager]  finishSession];
    [[GJLDigitalManager manager] newSession];
    //如果点击暂停播放音频流，请调用toResume恢复播放音频流
    if(self.isPause){ [self toResume];}
    
    // 使用火山TTS流式发送文本并播放返回的音频
    NSLog(@"🎯 [MAIN] Calling TTS from toRecord method");
    [[GJLPCMManager manager] toSpeakTextWithVolc:@"开始我会盯盘，到现在感觉看那个东西非常无聊。亏损了就放着。赚了就体现。现在就这样。爱涨不涨。妨碍我干正事。"]; 
    
//    self.showView.backgroundColor=[UIColor redColor];
//    self.showView.frame=CGRectMake(20, 20, 270, 480);

    
}

#pragma mark ------------回调----------------
-(void)toDigitalBlock
{
    
    __weak typeof(self)weakSelf = self;
    [GJLDigitalManager manager].playFailed = ^(NSInteger code, NSString *errorMsg) {

            [SVProgressHUD showInfoWithStatus:errorMsg];

      
    };
    [GJLDigitalManager manager].audioPlayEnd = ^{
//        [weakSelf moviePlayDidEnd];
        NSLog(@"播放结束");
      
//        [[GJLPCMManager manager] toStopAudioTimer2];
//
//        NSString * filepath=[[NSBundle mainBundle] pathForResource:@"1.wav" ofType:nil];
//        [[GJLDigitalManager manager] newSession];
//        [[GJLPCMManager manager] toSpeakWithPath:filepath];
     
    };
    
    [GJLDigitalManager manager].audioPlayProgress = ^(float current, float total) {
        
    };
    
    [GJLDigitalManager manager].onRenderReportBlock = ^(int resultCode, BOOL isLip, float useTime) {
//        NSLog(@"resultCode:%d,isLip:%d,useTime:%f",resultCode,isLip,useTime);
    };
 
}

#pragma mark ------------结束所有----------------
-(void)toStop
{

    [[GJLPCMManager manager] toStop];
    //停止绘制
    [[GJLDigitalManager manager] toStop];
    
    [self dismissViewControllerAnimated:YES completion:^{
        
    }];
}
-(void)toPause
{
    self.isPause=YES;
    [[GJLDigitalManager manager] toPause];
}
-(void)toResume
{
    self.isPause=NO;
    [[GJLDigitalManager manager] toPlay];
}
/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
