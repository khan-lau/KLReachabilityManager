KLReachabilityManager
=====================

Reachability 修复, 新增同步接口, 基于 afn 修改


[code]
//代码改良于 afn
//使用方法很简单

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    // Override point for customization after application launch.
    self.window.backgroundColor = [UIColor whiteColor];
    
    [self.window makeKeyAndVisible];
    [self demo];
    return YES;
}


- (void) demo {

    NSLog(@" history update");
    KLReachabilityStatus stat = [KLReachabilityManager netWorkReachable];
    if (KLReachabilityStatusReachableViaWWAN == stat) {
        NSLog(@"wwan  sync");
        
    } else if(KLReachabilityStatusReachableViaWiFi == stat)  {
        NSLog(@"wifi  sync");
    }
}
[/code]
