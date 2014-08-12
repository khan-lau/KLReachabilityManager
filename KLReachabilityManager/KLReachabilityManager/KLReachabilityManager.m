//
//  ReachabilityManager.m
//  XQuest
//
//  Created by Khan.Lau on 14-6-9.
//  Copyright (c) 2014年 Khan.Lau. All rights reserved.
//

#import "KLReachabilityManager.h"


NSString * const KLReachabilityDidChangeNotification = @"com.khan.networking.reachability.change";
NSString * const KLReachabilityNotificationStatusItem = @"KLReachabilityNotificationStatusItem";

typedef void (^KLReachabilityStatusBlock)(KLReachabilityStatus status);

typedef NS_ENUM(NSUInteger, KLReachabilityAssociation) {
    KLReachabilityForAddress = 1,
    KLReachabilityForAddressPair = 2,
    KLReachabilityForName = 3,
};

NSString * KLStringFromNetworkReachabilityStatus(KLReachabilityStatus status) {
    switch (status) {
        case KLReachabilityStatusNotReachable:
            return NSLocalizedStringFromTable(@"Not Reachable", @"KLNetworking", nil);
        case KLReachabilityStatusReachableViaWWAN:
            return NSLocalizedStringFromTable(@"Reachable via WWAN", @"KLNetworking", nil);
        case KLReachabilityStatusReachableViaWiFi:
            return NSLocalizedStringFromTable(@"Reachable via WiFi", @"KLNetworking", nil);
        case KLReachabilityStatusUnknown:
        default:
            return NSLocalizedStringFromTable(@"Unknown", @"KLNetworking", nil);
    }
}

static KLReachabilityStatus KLReachabilityStatusForFlags(SCNetworkReachabilityFlags flags) {
    BOOL isReachable = ((flags & kSCNetworkReachabilityFlagsReachable) != 0);
    BOOL needsConnection = ((flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0);
    BOOL canConnectionAutomatically = (((flags & kSCNetworkReachabilityFlagsConnectionOnDemand ) != 0) || ((flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0));
    BOOL canConnectWithoutUserInteraction = (canConnectionAutomatically && (flags & kSCNetworkReachabilityFlagsInterventionRequired) == 0);
    BOOL isNetworkReachable = (isReachable && (!needsConnection || canConnectWithoutUserInteraction));
    
    KLReachabilityStatus status = KLReachabilityStatusUnknown;
    if (isNetworkReachable == NO) {
        status = KLReachabilityStatusNotReachable;
    }
#if	TARGET_OS_IPHONE
    else if ((flags & kSCNetworkReachabilityFlagsIsWWAN) != 0) {
        status = KLReachabilityStatusReachableViaWWAN;
    }
#endif
    else {
        status = KLReachabilityStatusReachableViaWiFi;
    }
    
    return status;
}

static void AFNetworkReachabilityCallback(SCNetworkReachabilityRef __unused target, SCNetworkReachabilityFlags flags, void *info) {
    KLReachabilityStatus status = KLReachabilityStatusForFlags(flags);
    KLReachabilityStatusBlock block = (__bridge KLReachabilityStatusBlock)info;
    if (block) {
        block(status);
    }
    
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter postNotificationName:KLReachabilityDidChangeNotification object:nil userInfo:@{ KLReachabilityNotificationStatusItem: @(status) }];
    });
}

static const void * AFNetworkReachabilityRetainCallback(const void *info) {
    return Block_copy(info);
}

static void AFNetworkReachabilityReleaseCallback(const void *info) {
    if (info) {
        Block_release(info);
    }
}

@interface KLReachabilityManager ()

@property (readwrite, nonatomic, assign) SCNetworkReachabilityRef networkReachability;
@property (readwrite, nonatomic, assign) KLReachabilityAssociation networkReachabilityAssociation;
@property (readwrite, nonatomic, assign) KLReachabilityStatus networkReachabilityStatus;
@property (readwrite, nonatomic, copy) KLReachabilityStatusBlock networkReachabilityStatusBlock;
@end

@implementation KLReachabilityManager

+ (instancetype)sharedManager {
    static KLReachabilityManager *_sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        struct sockaddr_in address;
        bzero(&address, sizeof(address));
        address.sin_len = sizeof(address);
        address.sin_family = AF_INET;
        
        _sharedManager = [self managerForAddress:&address];
    });
    
    return _sharedManager;
}

+ (instancetype)managerForDomain:(NSString *)domain {
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, [domain UTF8String]);
    
    KLReachabilityManager *manager = [[self alloc] initWithReachability:reachability];
    manager.networkReachabilityAssociation = KLReachabilityForName;
    
    return manager;
}

+ (instancetype)managerForAddress:(const struct sockaddr_in *)address {
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *)address);
    
    KLReachabilityManager *manager = [[self alloc] initWithReachability:reachability];
    manager.networkReachabilityAssociation = KLReachabilityForAddress;
    
    return manager;
}

- (instancetype)initWithReachability:(SCNetworkReachabilityRef)reachability {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    self.networkReachability = reachability;
    self.networkReachabilityStatus = KLReachabilityStatusUnknown;
    
    return self;
}

- (void)dealloc {
    [self stopMonitoring];
    
    if (_networkReachability) {
        CFRelease(_networkReachability);
        _networkReachability = NULL;
    }
}

#pragma mark -

- (BOOL)isReachable {
    return [self isReachableViaWWAN] || [self isReachableViaWiFi];
}

- (BOOL)isReachableViaWWAN {
    return self.networkReachabilityStatus == KLReachabilityStatusReachableViaWWAN;
}

- (BOOL)isReachableViaWiFi {
    return self.networkReachabilityStatus == KLReachabilityStatusReachableViaWiFi;
}

#pragma mark -

- (void)startMonitoringInMainQueue {
    [self stopMonitoring];
    
    if (!self.networkReachability) {
        return;
    }
    
    __weak __typeof(self)weakSelf = self;
    KLReachabilityStatusBlock callback = ^(KLReachabilityStatus status) {
        __strong __typeof(weakSelf)strongSelf = weakSelf;
        
        strongSelf.networkReachabilityStatus = status;
        if (strongSelf.networkReachabilityStatusBlock) {
            strongSelf.networkReachabilityStatusBlock(status);
        }
    };
    
    SCNetworkReachabilityContext context = {0, (__bridge void *)callback, AFNetworkReachabilityRetainCallback, AFNetworkReachabilityReleaseCallback, NULL};
    SCNetworkReachabilitySetCallback(self.networkReachability, AFNetworkReachabilityCallback, &context);
    SCNetworkReachabilityScheduleWithRunLoop(self.networkReachability, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    
    switch (self.networkReachabilityAssociation) {
        case KLReachabilityForName:
            break;
        case KLReachabilityForAddress:
        case KLReachabilityForAddressPair:
        default: {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
                SCNetworkReachabilityFlags flags;
                SCNetworkReachabilityGetFlags(self.networkReachability, &flags);
                KLReachabilityStatus status = KLReachabilityStatusForFlags(flags);
                callback(status);
            });
        }
            break;
    }
}


- (void)startMonitoring {
    [self stopMonitoring];
    
    if (!self.networkReachability) {
        return;
    }
    
    __weak __typeof(self)weakSelf = self;
    KLReachabilityStatusBlock callback = ^(KLReachabilityStatus status) {
        __strong __typeof(weakSelf)strongSelf = weakSelf;
        
        strongSelf.networkReachabilityStatus = status;
        if (strongSelf.networkReachabilityStatusBlock) {
            strongSelf.networkReachabilityStatusBlock(status);
        }
    };
    
    SCNetworkReachabilityContext context = {0, (__bridge void *)callback, AFNetworkReachabilityRetainCallback, AFNetworkReachabilityReleaseCallback, NULL};
    SCNetworkReachabilitySetCallback(self.networkReachability, AFNetworkReachabilityCallback, &context);
    SCNetworkReachabilityScheduleWithRunLoop(self.networkReachability, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    
    switch (self.networkReachabilityAssociation) {
        case KLReachabilityForName:
            break;
        case KLReachabilityForAddress:
        case KLReachabilityForAddressPair:
        default: {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
                SCNetworkReachabilityFlags flags;
                SCNetworkReachabilityGetFlags(self.networkReachability, &flags);
                KLReachabilityStatus status = KLReachabilityStatusForFlags(flags);
                dispatch_async(dispatch_get_main_queue(), ^{
//                    DLog(@" callback excute");
                    callback(status);
                });
            });
        }
            break;
    }
}


- (void)stopMonitoring {
    if (!self.networkReachability) {
        return;
    }
    
    SCNetworkReachabilityUnscheduleFromRunLoop(self.networkReachability, CFRunLoopGetMain(), kCFRunLoopCommonModes);
}

#pragma mark -

- (NSString *)localizedNetworkReachabilityStatusString {
    return KLStringFromNetworkReachabilityStatus(self.networkReachabilityStatus);
}

#pragma mark -

- (void)setReachabilityStatusChangeBlock:(void (^)(KLReachabilityStatus status))block {
    self.networkReachabilityStatusBlock = block;
}

#pragma mark - NSKeyValueObserving

+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key {
    if ([key isEqualToString:@"reachable"] || [key isEqualToString:@"reachableViaWWAN"] || [key isEqualToString:@"reachableViaWiFi"]) {
        return [NSSet setWithObject:@"networkReachabilityStatus"];
    }
    
    return [super keyPathsForValuesAffectingValueForKey:key];
}



+ (KLReachabilityStatus)netWorkReachable{
    KLReachabilityManager *klReachabilityManager = [KLReachabilityManager sharedManager];
    
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [klReachabilityManager startMonitoringInMainQueue];  //开启网络监视器；
    [klReachabilityManager setReachabilityStatusChangeBlock:^(KLReachabilityStatus status) {
        
        switch (status) {
            case KLReachabilityStatusNotReachable:{
                break;
            }
            case KLReachabilityStatusReachableViaWiFi:{
                break;
            }
                
            case KLReachabilityStatusReachableViaWWAN:{
                break;
            }
            default:
                break;
        }
        dispatch_semaphore_signal(sema);
        NSLog(@"网络状态返回: %@", KLStringFromNetworkReachabilityStatus(status));
    }];
    
    dispatch_time_t time = dispatch_time ( DISPATCH_TIME_NOW , 100ull * USEC_PER_SEC ) ;
    dispatch_semaphore_wait(sema, time);
    
#if __has_feature(objc_arc)
#else
	dispatch_release(sema);
#endif
    return klReachabilityManager.networkReachabilityStatus;
}



@end
