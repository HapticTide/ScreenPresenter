//
//  FBDeviceControlBridge.h
//  FBDeviceControlKit
//
//  Created by Sun on 2025/12/24.
//
//  FBDeviceControl 桥接层头文件
//  暴露 Swift 可调用的最小 API
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 设备信息字典键

/// 设备信息字典的键定义
extern NSString *const kFBDeviceInfoUDID;
extern NSString *const kFBDeviceInfoDeviceName;
extern NSString *const kFBDeviceInfoProductVersion;
extern NSString *const kFBDeviceInfoProductType;
extern NSString *const kFBDeviceInfoBuildVersion;
extern NSString *const kFBDeviceInfoSerialNumber;
extern NSString *const kFBDeviceInfoModelNumber;
extern NSString *const kFBDeviceInfoHardwareModel;
extern NSString *const kFBDeviceInfoConnectionType;
extern NSString *const kFBDeviceInfoArchitecture;
extern NSString *const kFBDeviceInfoRawState;
extern NSString *const kFBDeviceInfoRawErrorDomain;
extern NSString *const kFBDeviceInfoRawErrorCode;
extern NSString *const kFBDeviceInfoRawStatusHint;

#pragma mark - 设备状态字典键

/// 设备状态事件字典的键定义
extern NSString *const kFBDeviceStateUDID;
extern NSString *const kFBDeviceStateEventType;
extern NSString *const kFBDeviceStateTimestamp;
extern NSString *const kFBDeviceStateInfo;

/// 事件类型值
extern NSString *const kFBDeviceEventConnected;
extern NSString *const kFBDeviceEventDisconnected;
extern NSString *const kFBDeviceEventStateChanged;

#pragma mark - 设备变化回调

/// 设备变化回调 Block 类型
/// @param devices 当前所有设备的信息字典数组
typedef void (^FBDeviceChangeCallback)(NSArray<NSDictionary *> *devices);

#pragma mark - FBDeviceControlBridge

/// FBDeviceControl 桥接类
/// 封装 FBDeviceControl 的 ObjC API，暴露给 Swift 使用
@interface FBDeviceControlBridge : NSObject

/// 单例实例
@property (class, nonatomic, readonly) FBDeviceControlBridge *shared;

/// FBDeviceControl 是否可用
@property (nonatomic, readonly) BOOL isAvailable;

/// 初始化错误信息（如果不可用）
@property (nonatomic, readonly, nullable) NSString *initializationError;

#pragma mark - 设备列表

/// 获取当前所有设备列表
/// @return 设备信息字典数组，每个字典包含 kFBDeviceInfo* 键
- (NSArray<NSDictionary *> *)listDevices;

/// 获取指定设备的详细信息
/// @param udid 设备 UDID
/// @return 设备信息字典，如果设备不存在返回 nil
- (nullable NSDictionary *)fetchDeviceInfo:(NSString *)udid;

#pragma mark - 设备观察

/// 开始观察设备变化
/// @param callback 设备变化回调，在主线程调用
- (void)startObservingWithCallback:(FBDeviceChangeCallback)callback;

/// 停止观察设备变化
- (void)stopObserving;

/// 是否正在观察设备变化
@property (nonatomic, readonly) BOOL isObserving;

#pragma mark - 刷新

/// 手动刷新设备列表
/// @return 刷新后的设备信息字典数组
- (NSArray<NSDictionary *> *)refresh;

@end

NS_ASSUME_NONNULL_END
