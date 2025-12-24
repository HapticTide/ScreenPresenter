//
//  FBDeviceControlBridge.mm
//  FBDeviceControlKit
//
//  Created by Sun on 2025/12/24.
//
//  FBDeviceControl 桥接层实现
//  封装 FBDeviceControl 的调用，输出纯 Swift 可用的字典
//

#import "FBDeviceControlBridge.h"

// SPM 包中，FB_DEVICE_CONTROL_SOURCES_COMPILED 通过 cSettings 定义
#ifndef FB_DEVICE_CONTROL_SOURCES_COMPILED
    #define FB_DEVICE_CONTROL_SOURCES_COMPILED 0
#endif

#if FB_DEVICE_CONTROL_SOURCES_COMPILED
    // FBControlCore
    #import "FBFuture.h"
    #import "FBFuture+Sync.h"
    #import "FBiOSTarget.h"
    #import "FBiOSTargetConstants.h"
    #import "FBiOSTargetSet.h"
    #import "FBControlCoreError.h"
    #import "FBControlCoreLogger.h"
    // FBDeviceControl
    #import "FBDeviceSet.h"
    #import "FBDevice.h"
    #import "FBAMDevice.h"
    #import "FBDeviceControlError.h"

    #define FB_DEVICE_CONTROL_AVAILABLE 1
#else
    #define FB_DEVICE_CONTROL_AVAILABLE 0
#endif

#pragma mark - 键定义

NSString *const kFBDeviceInfoUDID = @"udid";
NSString *const kFBDeviceInfoDeviceName = @"deviceName";
NSString *const kFBDeviceInfoProductVersion = @"productVersion";
NSString *const kFBDeviceInfoProductType = @"productType";
NSString *const kFBDeviceInfoBuildVersion = @"buildVersion";
NSString *const kFBDeviceInfoSerialNumber = @"serialNumber";
NSString *const kFBDeviceInfoModelNumber = @"modelNumber";
NSString *const kFBDeviceInfoHardwareModel = @"hardwareModel";
NSString *const kFBDeviceInfoConnectionType = @"connectionType";
NSString *const kFBDeviceInfoArchitecture = @"architecture";
NSString *const kFBDeviceInfoRawState = @"rawState";
NSString *const kFBDeviceInfoRawErrorDomain = @"rawErrorDomain";
NSString *const kFBDeviceInfoRawErrorCode = @"rawErrorCode";
NSString *const kFBDeviceInfoRawStatusHint = @"rawStatusHint";

NSString *const kFBDeviceStateUDID = @"udid";
NSString *const kFBDeviceStateEventType = @"eventType";
NSString *const kFBDeviceStateTimestamp = @"timestamp";
NSString *const kFBDeviceStateInfo = @"info";

NSString *const kFBDeviceEventConnected = @"connected";
NSString *const kFBDeviceEventDisconnected = @"disconnected";
NSString *const kFBDeviceEventStateChanged = @"stateChanged";

#pragma mark - FBDeviceControlBridge

#if FB_DEVICE_CONTROL_AVAILABLE

@interface FBDeviceControlBridge () <FBiOSTargetSetDelegate>
@property (nonatomic, strong) FBDeviceSet *deviceSet;
@property (nonatomic, copy) FBDeviceChangeCallback changeCallback;
@property (nonatomic, strong) dispatch_queue_t workQueue;
@end

#else

@interface FBDeviceControlBridge ()
@property (nonatomic, copy) FBDeviceChangeCallback changeCallback;
@end

#endif

@implementation FBDeviceControlBridge

#pragma mark - 单例

+ (FBDeviceControlBridge *)shared {
    static FBDeviceControlBridge *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[FBDeviceControlBridge alloc] init];
    });
    return instance;
}

#pragma mark - 初始化

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)setup {
#if FB_DEVICE_CONTROL_AVAILABLE
    _workQueue = dispatch_queue_create("com.fbdevicecontrolkit.bridge", DISPATCH_QUEUE_SERIAL);
    
    // 创建系统日志器
    id<FBControlCoreLogger> logger = [FBControlCoreLoggerFactory systemLoggerWritingToStderr:NO withDebugLogging:NO];
    
    NSError *error = nil;
    _deviceSet = [FBDeviceSet setWithLogger:logger
                                   delegate:self
                                 ecidFilter:nil
                                      error:&error];
    
    if (_deviceSet == nil) {
        _isAvailable = NO;
        _initializationError = error.localizedDescription ?: @"Failed to initialize FBDeviceSet";
        NSLog(@"[FBDeviceControlBridge] 初始化失败: %@", _initializationError);
    } else {
        _isAvailable = YES;
        _initializationError = nil;
        NSLog(@"[FBDeviceControlBridge] 初始化成功，当前设备数: %lu", (unsigned long)_deviceSet.allDevices.count);
    }
#else
    _isAvailable = NO;
    _initializationError = @"FBDeviceControl framework not compiled. FB_DEVICE_CONTROL_SOURCES_COMPILED is not defined.";
    NSLog(@"[FBDeviceControlBridge] FBDeviceControl 不可用");
#endif
}

#pragma mark - 设备列表

- (NSArray<NSDictionary *> *)listDevices {
#if FB_DEVICE_CONTROL_AVAILABLE
    if (!_isAvailable || _deviceSet == nil) {
        return @[];
    }
    
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (FBDevice *device in _deviceSet.allDevices) {
        NSDictionary *info = [self deviceInfoDictionary:device];
        if (info) {
            [result addObject:info];
        }
    }
    return [result copy];
#else
    return @[];
#endif
}

- (nullable NSDictionary *)fetchDeviceInfo:(NSString *)udid {
#if FB_DEVICE_CONTROL_AVAILABLE
    if (!_isAvailable || _deviceSet == nil || udid == nil) {
        return nil;
    }
    
    FBDevice *device = [_deviceSet deviceWithUDID:udid];
    if (device == nil) {
        return nil;
    }
    
    return [self deviceInfoDictionary:device];
#else
    return nil;
#endif
}

#pragma mark - 设备观察

- (void)startObservingWithCallback:(FBDeviceChangeCallback)callback {
    self.changeCallback = callback;
    _isObserving = YES;
    
#if FB_DEVICE_CONTROL_AVAILABLE
    // FBDeviceSet 使用 delegate 模式通知变化
    // 在 targetDidUpdate: 中会调用 callback
    NSLog(@"[FBDeviceControlBridge] 开始观察设备变化");
    
    // 立即回调当前设备列表
    if (callback) {
        dispatch_async(dispatch_get_main_queue(), ^{
            callback([self listDevices]);
        });
    }
#else
    NSLog(@"[FBDeviceControlBridge] FBDeviceControl 不可用，无法观察设备变化");
#endif
}

- (void)stopObserving {
    self.changeCallback = nil;
    _isObserving = NO;
    NSLog(@"[FBDeviceControlBridge] 停止观察设备变化");
}

#pragma mark - 刷新

- (NSArray<NSDictionary *> *)refresh {
    return [self listDevices];
}

#pragma mark - FBiOSTargetSetDelegate

#if FB_DEVICE_CONTROL_AVAILABLE

- (void)targetAdded:(id<FBiOSTargetInfo>)targetInfo inTargetSet:(id<FBiOSTargetSet>)targetSet {
    NSLog(@"[FBDeviceControlBridge] 设备已添加: %@", targetInfo.udid);
    [self notifyDeviceChange];
}

- (void)targetRemoved:(id<FBiOSTargetInfo>)targetInfo inTargetSet:(id<FBiOSTargetSet>)targetSet {
    NSLog(@"[FBDeviceControlBridge] 设备已移除: %@", targetInfo.udid);
    [self notifyDeviceChange];
}

- (void)targetUpdated:(id<FBiOSTargetInfo>)targetInfo inTargetSet:(id<FBiOSTargetSet>)targetSet {
    NSLog(@"[FBDeviceControlBridge] 设备状态更新: %@", targetInfo.udid);
    [self notifyDeviceChange];
}

- (void)notifyDeviceChange {
    if (self.changeCallback) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.changeCallback([self listDevices]);
        });
    }
}

#endif

#pragma mark - 私有方法

#if FB_DEVICE_CONTROL_AVAILABLE

- (NSDictionary *)deviceInfoDictionary:(FBDevice *)device {
    if (device == nil) {
        return nil;
    }
    
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    
    // 基本信息
    info[kFBDeviceInfoUDID] = device.udid ?: @"";
    info[kFBDeviceInfoDeviceName] = device.name ?: @"iOS Device";
    
    // 设备类型信息
    FBDeviceType *deviceType = device.deviceType;
    if (deviceType) {
        info[kFBDeviceInfoProductType] = deviceType.model ?: [NSNull null];
    }
    
    // 系统版本信息
    FBOSVersion *osVersion = device.osVersion;
    if (osVersion) {
        info[kFBDeviceInfoProductVersion] = osVersion.versionString ?: [NSNull null];
    }
    
    // 架构信息
    NSArray<NSString *> *architectures = device.architectures;
    if (architectures.count > 0) {
        info[kFBDeviceInfoArchitecture] = architectures.firstObject;
    }
    
    // 扩展信息（包含更详细的设备信息）
    NSDictionary *extendedInfo = device.extendedInformation;
    NSDictionary *deviceValues = extendedInfo[@"device"];
    
    if (deviceValues && [deviceValues isKindOfClass:[NSDictionary class]]) {
        // buildVersion
        id buildVersion = deviceValues[@"BuildVersion"];
        if (buildVersion && buildVersion != [NSNull null]) {
            info[kFBDeviceInfoBuildVersion] = buildVersion;
        }
        
        // serialNumber
        id serialNumber = deviceValues[@"SerialNumber"];
        if (serialNumber && serialNumber != [NSNull null]) {
            info[kFBDeviceInfoSerialNumber] = serialNumber;
        }
        
        // modelNumber
        id modelNumber = deviceValues[@"ModelNumber"];
        if (modelNumber && modelNumber != [NSNull null]) {
            info[kFBDeviceInfoModelNumber] = modelNumber;
        }
        
        // hardwareModel
        id hardwareModel = deviceValues[@"HardwareModel"];
        if (hardwareModel && hardwareModel != [NSNull null]) {
            info[kFBDeviceInfoHardwareModel] = hardwareModel;
        }
        
        // 激活状态（用于判断设备是否已激活）
        id activationState = deviceValues[@"ActivationState"];
        if (activationState && activationState != [NSNull null]) {
            NSString *activationStr = [activationState description];
            // 如果设备未激活，设置错误提示
            if (![activationStr isEqualToString:@"Activated"]) {
                info[kFBDeviceInfoRawErrorDomain] = @"FBDeviceControl";
                info[kFBDeviceInfoRawErrorCode] = @(-1001); // 自定义错误码：未激活
                info[kFBDeviceInfoRawStatusHint] = [NSString stringWithFormat:@"ActivationState=%@", activationStr];
            }
        }
        
        // 配对状态（用于判断设备是否已信任）
        id isPaired = deviceValues[@"IsPaired"];
        if (isPaired != nil && isPaired != [NSNull null]) {
            BOOL paired = [isPaired boolValue];
            if (!paired) {
                info[kFBDeviceInfoRawErrorDomain] = @"FBDeviceControl";
                info[kFBDeviceInfoRawErrorCode] = @(-1002); // 自定义错误码：未配对
                info[kFBDeviceInfoRawStatusHint] = @"Device not paired/trusted";
            }
        }
    }
    
    // 状态信息
    info[kFBDeviceInfoRawState] = @(device.state);
    info[kFBDeviceInfoConnectionType] = @"USB"; // TODO: 从 extendedInfo 判断连接类型
    
    return [info copy];
}

#endif

@end
