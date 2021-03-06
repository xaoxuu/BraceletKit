//
//  BKDevice.m
//  BraceletKit
//
//  Created by xaoxuu on 20/01/2018.
//  Copyright © 2018 xaoxuu. All rights reserved.
//

#import "BKDevice.h"
#import "_BKHeader.h"
#import "BKServices.h"
#import <AXKit/StatusKit.h>

#import "BKUser.h"
#import "BKDevice.h"
#import "BKPreferences.h"
#import "BKDataIndex.h"
#import "BKDayData.h"
#import "BKSportData.h"
#import "BKHeartRateData.h"
#import "BKHeartRateHourData.h"
#import "BKSleepData.h"
#import "BKSportList.h"


static inline void bk_ble_option(void (^option)(void), void(^completion)(void), void (^error)(NSError * __nullable)){
    CBCentralManagerState state = (CBCentralManagerState)[BKServices sharedInstance].connector.central.state;
    BOOL ble = state == CBCentralManagerStatePoweredOn;
    if (!ble) {
        NSError *err = [NSError ax_errorWithMaker:^(NSErrorMaker * _Nonnull error) {
            if (state == CBCentralManagerStatePoweredOff) {
                error.localizedDescription = @"蓝牙未打开";
            } else if (state == CBCentralManagerStateUnauthorized) {
                error.localizedDescription = @"蓝牙未授权";
            } else if (state == CBCentralManagerStateUnsupported) {
                error.localizedDescription = @"设备不支持蓝牙4.0";
            } else {
                error.localizedDescription = @"未能打开蓝牙，原因未知。";
            }
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            [AXStatusBar showStatusBarMessage:err.localizedDescription textColor:[UIColor whiteColor] backgroundColor:[UIColor md_red] duration:5];
        });
        if (error) {
            error(err);
        }
        return;
    }
    
    BOOL device = [BKDevice currentDevice];
    if (!device) {
        NSError *err = [NSError ax_errorWithMaker:^(NSErrorMaker * _Nonnull error) {
            error.localizedDescription = @"未连接任何设备";
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            [AXStatusBar showStatusBarMessage:err.localizedDescription textColor:[UIColor whiteColor] backgroundColor:[UIColor md_red] duration:5];
        });
        if (error) {
            error(err);
        }
        return;
    }
    
    BOOL connected = [BKServices sharedInstance].connector.state == BKConnectStateConnected;
    if (!connected) {
        NSError *err = [NSError ax_errorWithMaker:^(NSErrorMaker * _Nonnull error) {
            error.localizedDescription = @"与设备的连接已经断开";
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            [AXStatusBar showStatusBarMessage:err.localizedDescription textColor:[UIColor whiteColor] backgroundColor:[UIColor md_red] duration:5];
        });
        if (error) {
            error(err);
        }
        return;
    }
    
    if (option) {
        option();
        if (completion) {
            completion();
        }
    }
    
}

@interface BKServices() <BKDeviceDelegate>

@end

@interface BKDevice() <BLELib3Delegate, BKConnectDelegate, BKDataObserver>

@property (strong, nonatomic) ZeronerDeviceInfo *deviceInfo;

@property (strong, nonatomic) ZeronerHWOption *hwOption;

@property (assign, nonatomic) CGFloat progress;

@end

@implementation BKDevice

#pragma mark - life circle


+ (instancetype)currentDevice{
    return [BKServices sharedInstance].connector.device;
}

- (instancetype)init{
    if (self = [super init]) {
        _languages = [NSMutableArray array];
        _functions = [NSMutableArray array];
        _delegate = [BKServices sharedInstance];
        
    }
    return self;
}


#pragma mark - db delegate

+ (NSString *)tableName{
    return @"devices";
}
+ (NSString *)tableColumns{
    static NSString *columnName;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableString *column = [NSMutableString string];
        [column appendVarcharColumn:@"device_id" comma:YES];
        [column appendVarcharColumn:@"mac" comma:YES];
        [column appendVarcharColumn:@"uuid" comma:YES];
        [column appendVarcharColumn:@"name" comma:YES];
        [column appendVarcharColumn:@"model" comma:YES];
        [column appendIntegerColumn:@"type" comma:YES];
        [column appendVarcharColumn:@"version" comma:YES];
        [column appendIntegerColumn:@"battery" comma:YES];
        [column appendVarcharColumn:@"languages" comma:YES];
        [column appendVarcharColumn:@"functions" comma:YES];
        
        [column appendVarcharColumn:@"lastmodified" comma:NO];
        columnName = column;
    });
    return columnName;
}
+ (NSString *)tablePrimaryKey{
    return @"device_id, uuid, model, version";
}

+ (instancetype)modelWithSet:(FMResultSet *)set{
    int i = 0;
    BKDevice *model = [[BKDevice alloc] init];
    i++;// device_id
    model.mac = [set stringForColumnIndex:i++];
    model.uuid = [set stringForColumnIndex:i++];
    model.name = [set stringForColumnIndex:i++];
    model.model = [set stringForColumnIndex:i++];
    model.type = [set longForColumnIndex:i++];
    model.version = [set stringForColumnIndex:i++];
    model.battery = [set intForColumnIndex:i++];
    
    NSString *dataString = [set stringForColumnIndex:i++];
    NSData *data = [dataString dataUsingEncoding:NSUTF8StringEncoding];
    if (data) {
        model.languages = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    }
    
    dataString = [set stringForColumnIndex:i++];
    data = [dataString dataUsingEncoding:NSUTF8StringEncoding];
    if (data) {
        model.functions = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    }

//    NSString *tmp = [set stringForColumnIndex:i++];
//    NSArray<NSString *> *tmpArr = [tmp componentsSeparatedByString:@","];
//    [tmpArr enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
//        if (obj.length) {
//            [model.languages addObject:@(obj.integerValue)];
//        }
//    }];
//    tmp = [set stringForColumnIndex:i++];
//    tmpArr = [tmp componentsSeparatedByString:@","];
//    [tmpArr enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
//        if (obj.length) {
//            [model.functions addObject:@(obj.integerValue)];
//        }
//    }];
    return model;
}

- (NSString *)valueString{
    NSMutableString *value = [NSMutableString string];
    [value appendVarcharValue:self.mac comma:YES]; // device_id = mac
    [value appendVarcharValue:self.mac comma:YES];
    [value appendVarcharValue:self.uuid comma:YES];
    [value appendVarcharValue:self.name comma:YES];
    [value appendVarcharValue:self.model comma:YES];
    [value appendIntegerValue:self.type comma:YES];
    [value appendVarcharValue:self.version comma:YES];
    [value appendIntegerValue:self.battery comma:YES];
    
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.languages options:NSJSONWritingPrettyPrinted error:nil];
    NSString *jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [value appendVarcharValue:jsonStr comma:YES];
    
    data = [NSJSONSerialization dataWithJSONObject:self.functions options:NSJSONWritingPrettyPrinted error:nil];
    jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [value appendVarcharValue:jsonStr comma:YES];
    
    
//    NSMutableString *languages = [NSMutableString string];
//    [self.languages enumerateObjectsUsingBlock:^(NSNumber * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
//        [languages appendFormat:@"%ld,", obj.integerValue];
//    }];
//    NSString *str = @"";
//    if (languages.length) {
//        str = [languages substringToIndex:languages.length-1];
//    }
//    [value appendVarcharValue:str comma:YES];
//    NSMutableString *functions = [NSMutableString string];
//    [self.functions enumerateObjectsUsingBlock:^(NSNumber * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
//        [functions appendFormat:@"%ld,", obj.integerValue];
//    }];
//    str = @"";
//    if (functions.length) {
//        str = [functions substringToIndex:functions.length-1];
//    }
//    [value appendVarcharValue:str comma:YES];
    
    [value appendVarcharValue:bk_date_string(bk_today()) comma:NO];
    return value;
}

- (BOOL)cacheable{
    return self.mac.length && ![self.mac isEqualToString:@"advertisementData.length is less than 6"] && self.model.length && self.version.length;
}

- (NSString *)whereExists{
    return [NSString stringWithFormat:@"device = '%@'", self.mac];
}

+ (instancetype)lastConnectedDevice{
    __block BKDevice *cachedDevice;
    databaseTransaction(^(FMDatabase * _Nonnull db, BOOL * _Nonnull rollback) {
        [db ax_select:@"*" from:self.tableName where:^NSString * _Nonnull{
            return @"";
        } orderBy:@"lastmodified DESC LIMIT 1" result:^(FMResultSet * _Nonnull set) {
            cachedDevice = [self modelWithSet:set];
        }];
    });
    return cachedDevice;
}

+ (NSMutableArray<BKDevice *> *)allMyDevices{
    NSMutableArray<BKDevice *> *devices = [NSMutableArray array];
    databaseTransaction(^(FMDatabase * _Nonnull db, BOOL * _Nonnull rollback) {
        [db ax_select:@"*" from:self.tableName where:^NSString * _Nonnull{
            return @"";
        } orderBy:@"lastmodified DESC" result:^(FMResultSet * _Nonnull set) {
            [devices addObject:[self modelWithSet:set]];
        }];
    });
    return devices;
}

- (NSString *)restoreMac{
    __block NSString *mac;
    databaseTransaction(^(FMDatabase * _Nonnull db, BOOL * _Nonnull rollback) {
        [db ax_select:@"mac" from:self.class.tableName where:^NSString * _Nonnull{
            return [NSString stringWithFormat:@"uuid = '%@'", self.uuid];
        } orderBy:@"lastmodified DESC LIMIT 1" result:^(FMResultSet * _Nonnull set) {
            mac = [set stringForColumnIndex:0];
        }];
        if (!mac.length) { // 如果根据UUID找不到，可尝试根据设备name恢复
            [db ax_select:@"mac" from:self.class.tableName where:^NSString * _Nonnull{
                return [NSString stringWithFormat:@"name = '%@'", self.name];
            } orderBy:@"lastmodified DESC LIMIT 1" result:^(FMResultSet * _Nonnull set) {
                mac = [set stringForColumnIndex:0];
            }];
        }
        if (!mac.length) { // 如果根据name找不到，可尝试根据设备model恢复
            [db ax_select:@"mac" from:self.class.tableName where:^NSString * _Nonnull{
                return [NSString stringWithFormat:@"model = '%@'", self.model];
            } orderBy:@"lastmodified DESC LIMIT 1" result:^(FMResultSet * _Nonnull set) {
                mac = [set stringForColumnIndex:0];
            }];
        }
    });
    return mac;
}


+ (NSString *)defaultWhereString{
    return [NSString stringWithFormat:@"device_id = '%@'",bk_device_id()];
}

#pragma mark - priv

/**
 第一次连接设备的时候进行初始化
 */
- (void)initializeDeviceWhenFirstConnected{
    BKDevice *cachedDevice = [self.class selectWhere:[NSString stringWithFormat:@"model = '%@' and version = '%@'", self.model, self.version]].lastObject;
    if (!cachedDevice) {
        // 获取支持的语言列表
        [self.languages addObject:@(BKLanguageSimpleMarkings)]; // icon
        [self.languages addObject:@(BKLanguageDefault)]; // English
        [self.languages addObject:@(BKLanguageSimpleChinese)];
        // 获取支持的功能列表
        if ([BLELib3 shareInstance].hasLanguageSelectFunction) {
            [self.functions addObject:@(BKDeviceFunctionLanguageSelection)];
        }
        if ([BLELib3 shareInstance].hasBackgroundLightFunction) {
            [self.functions addObject:@(BKDeviceFunctionBackgroundLight)];
        }
        if ([BLELib3 shareInstance].hasLedLightFunction) {
            [self.functions addObject:@(BKDeviceFunctionLedLight)];
        }
        if ([BLELib3 shareInstance].hasWristBlightFunction) {
            [self.functions addObject:@(BKDeviceFunctionWristBlight)];
        }
        if ([BLELib3 shareInstance].hasScheduleFunction) {
            [self.functions addObject:@(BKDeviceFunctionSchedule)];
        }
        if ([BLELib3 shareInstance].hasMotorControlFunction) {
            [self.functions addObject:@(BKDeviceFunctionMotorControl)];
        }
        if ([BLELib3 shareInstance].hasWeatherFunction) {
            [self.functions addObject:@(BKDeviceFunctionWeather)];
        }
        if ([BLELib3 shareInstance].hasHeartFunction) {
            [self.functions addObject:@(BKDeviceFunctionHeartRate)];
        }
        if ([BLELib3 shareInstance].hasAutoHeartRateFunction) {
            [self.functions addObject:@(BKDeviceFunctionAutoHeartRate)];
        }
        if ([BLELib3 shareInstance].hasExerciseHRWarningFunction) {
            [self.functions addObject:@(BKDeviceFunctionExerciseHRWarning)];
        }
        AXCachedLogOBJ(self);
    } else {
        // 恢复
        self.languages = cachedDevice.languages;
        self.functions = cachedDevice.functions;
    }
}


- (void)refreshPreferences{
    [[BLELib3 shareInstance] readFirmwareOption];
}

- (void)changeSyncState:(BOOL)sync{
    if (self.isSynchronizing ^ sync) {
        static NSTimer *timer;
        [timer ax_pause];
        timer = nil;
        if (sync) {
            self.progress = 0;
            __weak typeof(self) weakSelf = self;
            timer = [NSTimer ax_scheduledTimerWithTimeInterval:0.2 repeats:YES usingBlock:^(NSTimer * _Nonnull timer) {
                NSInteger pro = [BLELib3 shareInstance].dataSyncProgress;
                if (pro >= 0) {
                    weakSelf.progress = AXMakeNumberInRange(@((CGFloat)[BLELib3 shareInstance].dataSyncProgress / 100.0), @0, @1).doubleValue;
                } else {
                    if (self.progress) {
                        weakSelf.progress = 1;
                    }
                }
                if ([self.delegate respondsToSelector:@selector(deviceDidUpdateSynchronizeProgress:)]) {
                    [self.delegate deviceDidUpdateSynchronizeProgress:self.progress];
                }
            }];
        } else {
            self.progress = 1;
            if ([self.delegate respondsToSelector:@selector(deviceDidUpdateSynchronizeProgress:)]) {
                [self.delegate deviceDidUpdateSynchronizeProgress:self.progress];
            }
        }
    }
    if (self.isSynchronizing == !sync) {
        self.isSynchronizing = sync;
        if ([self.delegate respondsToSelector:@selector(deviceDidSynchronizing:)]) {
            [self.delegate deviceDidSynchronizing:self.isSynchronizing];
        }
    }
}

#pragma mark - function

/**
 请求同步用户数据

 @param completion 指令已发送到设备
 @param error 指令发送失败及其原因
 */
- (void)requestUpdateUserCompletion:(void (^)(void))completion error:(void (^)(NSError * _Nonnull))error{
    bk_ble_option(^{
        [[BLELib3 shareInstance] setPersonalInfo:[BKUser currentUser].transformToZeronerPersonal];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[BLELib3 shareInstance] readPersonalInfo];
        });
    }, completion, error);
}

/**
 请求更新偏好设置
 
 @param completion 指令已发送到设备
 @param error 指令发送失败及其原因
 */
- (void)requestUpdatePreferencesCompletion:(void (^)(void))completion error:(void (^)(NSError * _Nonnull))error{
    bk_ble_option(^{
        [[BLELib3 shareInstance] setFirmwareOption:self.preferences.transformToZeronerHWOption];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[BLELib3 shareInstance] readFirmwareOption];
        });
    }, completion, error);
}
/**
 请求立即同步时间
 
 @param completion 指令已发送到设备
 @param error 指令发送失败及其原因
 */
- (void)requestSyncTimeAtOnceCompletion:(void (^)(void))completion error:(void (^)(NSError * _Nonnull))error{
    bk_ble_option(^{
        [[BLELib3 shareInstance] syscTimeAtOnce];
    }, completion, error);
}

/**
 请求进入或退出拍照模式
 
 @param cameraMode 进入或退出
 @param completion 指令已发送到设备
 @param error 操作失败
 */
- (void)requestCameraMode:(BOOL)cameraMode completion:(void(^)(void))completion error:(void (^)(NSError * _Nonnull))error{
    bk_ble_option(^{
        [[BLELib3 shareInstance] setKeyNotify:cameraMode];
    }, completion, error);
}

/**
 请求向手环推送消息（不要超过手环一屏内容，否则显示不全）
 
 @param message 消息内容
 @param completion 指令已发送到设备
 @param error 指令发送失败及其原因
 */
- (void)requestPushMessage:(NSString *)message completion:(void (^)(void))completion error:(void (^)(NSError * _Nonnull))error{
    bk_ble_option(^{
        [[BLELib3 shareInstance] pushStr:message];
    }, completion, error);
}

/**
 请求更新电池电量信息
 
 @param completion 指令已发送到设备
 @param error 指令发送失败及其原因
 */
- (void)requestUpdateBatteryCompletion:(void(^)(void))completion error:(void (^)(NSError *error))error{
    bk_ble_option(^{
        [[BLELib3 shareInstance] readDeviceBattery];
    }, completion, error);
}

/**
 请求更新所有健康数据
 
 @param completion 指令已发送到设备
 @param error 指令发送失败及其原因
 */
- (void)requestUpdateAllHealthDataCompletion:(void(^ _Nullable)(void))completion error:(void (^ _Nullable)(NSError *error))error{
    bk_ble_option(^{
        [[BLELib3 shareInstance] syncData];
    }, completion, error);
}

/**
 请求立即停止更新所有健康数据
 
 @param completion 指令已发送到设备
 @param error 指令发送失败及其原因
 */
- (void)requestStopUpdateAllHealthDataCompletion:(void(^ _Nullable)(void))completion error:(void (^ _Nullable)(NSError *error))error{
    bk_ble_option(^{
        [[BLELib3 shareInstance] stopSyncData];
    }, completion, error);
}

/**
 请求更新天气信息
 
 @param completion 指令已发送到设备
 @param error 指令发送失败及其原因
 */
- (void)requestUpdateWeatherInfo:(void (^)(BKWeather *weather))weatherInfo completion:(void(^ _Nullable)(void))completion error:(void (^ _Nullable)(NSError *error))error{
    if (weatherInfo) {
        bk_ble_option(^{
            BKWeather *weather = [[BKWeather alloc] init];
            weatherInfo(weather);
            [[BLELib3 shareInstance] setWeather:weather.transformToZeronerWeather];
        }, completion, error);
    }
}




#pragma mark - connect delegate -> device setting


- (void)connectorDidUnconnectedDevice:(BKDevice *)device{
    [self changeSyncState:NO];
}

#pragma mark - data observer

- (void)userDidUpdated:(BKUser *)user{
    [self requestUpdateUserCompletion:nil error:nil];
}

- (void)preferencesDidUpdated:(BKPreferences *)preferences{
    [self requestUpdatePreferencesCompletion:nil error:nil];
}

#pragma mark - ble delegate -> device setting

#pragma mark required
/*
 *  Set bracelet parameter after connect with app.
 *  like ZeronerHWOption, ZeronerPersonal
 */
- (void)setBLEParameterAfterConnect{
    AXCachedLogOBJ(@"setBLEParameterAfterConnect");
    [self requestUpdateUserCompletion:nil error:nil];
    [self refreshPreferences];
    
}


#pragma mark optional
/*
 * Implement this method and return YES if you are not want sysc data automaticlly.
 * Or SDK will call @method{syncData} after a little.
 * NOTE: You should set bracelet parameter in method @CODE{setBLEParameterAfterConnect} ,if you need lot of setting in there. You will be suggested return YES in finally.
 */
- (BOOL)doNotSyscHealthAtTimes{
    AXCachedLogOBJ(@"doNotSyscHealthAtTimes = NO");
    return NO;
}

/**
 * Invoked when sppcial cmd sent to device.
 * error equal nil mean successful.
 */
//- (BOOL)writeCmdResponse:(BLECmdResponse)type andError:(NSError *)error{
//
//}
/**
 * 声明：蓝牙日志的解读需要zeroner蓝牙协议的文档，如果你没有阅读文档的权限，身边也没有可以阅读此文档的人，那么写日志对你来说不是必要的。
 * 传一个地址，如果你需要蓝牙的日志的话，最好是txt格式的。
 * Return a file path for BLE log, you are expected return a file path type txt. like this
 * @code NSString *documentsPath =[NSString stringWithFormat:@"%@/Documents", NSHomeDirectory()];
 NSString *testPath = [documentsPath stringByAppendingPathComponent:@"BLE.txt"]; @/code
 */
//- (NSString *)bleLogPath{
//    NSString *path = [@"com.xaoxuu.AXKit" stringByAppendingPathComponent:@"log"];
//    path = [path stringByAppendingPathComponent:@"ZeronerBleLog.txt"].cachePath;
//    return path;
//}

- (NSString *)currentUserUid{
    if ([BKUser currentUser].email.length) {
        return [BKUser currentUser].email;
    } else {
        return @"123456";
    }
}

/*!
 * 描述: APP主动call setKeyNotify:1，让手环进入到拍照模式，手环上出现拍照按钮，
 *      按键或点击按钮手环SDK会通过 notifyToTakePicture 通知App拍照。
 * 注意: setKeyNotify 进入App智拍模式后设置1. 退出拍照界面设置0
 *      需要做拍照保护，拍照在未保存完成前不要开启第二次拍照。
 */
- (void)notifyToTakePicture{
    AXCachedLogOBJ(@"notifyToTakePicture");
    if ([self.delegate respondsToSelector:@selector(deviceDidTappedTakePicture)]) {
        [self.delegate deviceDidTappedTakePicture];
    }
}

/*!
 * 描述: 长按手环按钮或者点击触屏选择找手机按钮，手环SDK会通过 notifyToSearchPhone告诉App，手环需要找手机。
 *       接下来App可以播放寻找手机的音乐或者其他操作
 */
- (void)notifyToSearchPhone{
    AXCachedLogOBJ(@"notifyToSearchPhone");
    if ([self.delegate respondsToSelector:@selector(deviceDidTappedFindMyPhone)]) {
        [self.delegate deviceDidTappedFindMyPhone];
    }
}

#pragma mark - ble delegate -> device Info

- (void)updateDeviceInfo:(ZeronerDeviceInfo *)deviceInfo{
    _deviceInfo = deviceInfo;
    _mac = deviceInfo.bleAddr;
    _model = deviceInfo.model;
    _version = deviceInfo.version;
    if ([self.delegate respondsToSelector:@selector(deviceDidUpdateInfo)]) {
        [self.delegate deviceDidUpdateInfo];
    }
    AXCachedLogOBJ(deviceInfo);
    _preferences = [[[BKPreferences alloc] init] restoreFromDatabase];
    // 如果是第一次连接
    [self initializeDeviceWhenFirstConnected];
    [self saveToDatabase];
    
}

- (void)updateBattery:(ZeronerDeviceInfo *)deviceInfo{
    _deviceInfo = deviceInfo;
    _battery = AXMakeNumberInRange(@(deviceInfo.batLevel), @0, @100).integerValue;
    if ([self.delegate respondsToSelector:@selector(deviceDidUpdateBattery:)]) {
        [self.delegate deviceDidUpdateBattery:self.battery];
    }
    [self saveToDatabase];
    AXCachedLogOBJ(deviceInfo);
    [NSUserDefaults ax_setInteger:deviceInfo.batLevel forKey:deviceInfo.seriesNo.extension(@"deviceInfo.batLevel")];
    
    [[BLELib3 shareInstance] getSleepData_Custom];
}

/**
 the method be called after call - (void)getSupportSportsList;
 
 @param ssList ssList
 */
- (void)notifySupportSportsList:(NSDictionary *)ssList{
    AXCachedLogOBJ(ssList);
    NSArray<NSNumber *> *typeArr = [ssList arrayValueForKey:@"LIST"];
    NSArray<NSString *> *nameArr = [ssList arrayValueForKey:@"NAME"];
    NSArray<NSString *> *unitArr = [ssList arrayValueForKey:@"UNIT"];
    NSUInteger count = typeArr.count; // 必须三项相等且不为0
    if (count && (nameArr.count == count) && (unitArr.count == count)) {
        for (int i = 0; i < count; i++) {
            BKSportList *model = [[BKSportList alloc] init];
            model.type = typeArr[i].intValue;
            model.name = nameArr[i];
            model.unit = unitArr[i];
            [model saveToDatabase];
        }
    } else {
        NSAssert(NO, @"无效的运动列表");
    }
    
}

/**
 *  responseOfGetTime
 *
 *  @param date (year month day hour minute second)
 */
- (void)responseOfGetTime:(NSDate *)date{
    AXCachedLogOBJ(date);
}

/**
 the response of get clock
 
 @param clock clock
 */
- (void)responseOfGetClock:(ZeronerClock *)clock{
    AXCachedLogOBJ(clock);
}

/**
 the response of get sedentary
 
 @param sedentarys sedentarys
 */
- (void)responseOfGetSedentary:(NSArray<ZeronerSedentary *>*)sedentarys{
    AXCachedLogOBJ(sedentarys);
}

/**
 the response of get HWOption
 
 @param hwOption hwOption
 */
- (void)responseOfGetHWOption:(ZeronerHWOption *)hwOption{
    _hwOption = hwOption;
    if (!_preferences) {
        _preferences = hwOption.transformToBKPreferences;
    }
    [self.preferences saveToDatabaseIfNotExists];
    AXCachedLogOBJ(hwOption);
}

- (void)responseOfGetSprotTarget:(ZeronerSportTarget *)spModel{
    AXCachedLogOBJ(spModel);
}

- (void)responseOfDNDSetting:(ZeronerDNDModel *)dndModel{
    AXCachedLogOBJ(dndModel);
}

- (void)responseOfPersonalInfo:(ZeronerPersonal *)pModel{
    AXCachedLogOBJ(pModel);
}

- (void)responseOfMotoControl:(NSUInteger)countsOn{
    AXCachedLogOBJ(@(countsOn));
}

- (void)responseOfCustomOption:(ZeronerCOption *)cOption{
    AXCachedLogOBJ(cOption);
}

- (void)responseOfGPSPoint:(ZeronerGPSPoint *)pModel{
    AXCachedLogOBJ(pModel);
}

#pragma mark - ble delegate -> device data


/**
 *  Method would be invoked when syscData state changed
 *
 *  @param ksdState type means sysc finished process.
 */
- (void)syscDataFinishedStateChange:(KSyscDataState)ksdState{
    NSString *log = [BKLogHelper descriptionForSyncState:ksdState];
    AXCachedLogOBJ(log);
    if (ksdState == KSyscDataStateBegin || ksdState == KSyscDataStateStartSyscF1Data) {
        [self changeSyncState:YES];
    } else if (ksdState == KSyscDataStateInFinished) {
        [self changeSyncState:NO];
    }
}

/**
 *  Method would be invoked when received sport segement data.（data type is 0x28）
 *
 @param dict dict
 */
- (void)updateSleepData:(NSDictionary *)dict{
    AXCachedLogData(dict);
    BKSleepData *model = [BKSleepData modelWithDict:dict];
    [model saveToDatabase];
}

/**
 * Method would be invoked when received sport segement data .（data type is 0x28）
 
 @param dict dict
 */
- (void)updateSportData:(NSDictionary *)dict{
    AXCachedLogData(dict);
    BKSportData *model = [BKSportData modelWithDict:dict];
    [model saveToDatabase];
}

/**
 *  Method would be invoked when received sport summary data（type 0x29）
 *
 @param dict ：Dictionary object contains accurate timestamp provided by smartband.
 */
- (void)updateWholeDaySportData:(NSDictionary *)dict{
    AXCachedLogData(dict);
    BKDayData *model = [BKDayData modelWithDict:dict];
    [model saveToDatabase];
}

/**
 *  Method would be invoked when received sport summary data（type 0x29）
 *
 @param dict ：Dictionary object without accurate timestamp provided by smartband. SDK use [NSDate date] replace it.
 */
- (void)updateCurrentWholeDaySportData:(NSDictionary *)dict{
    AXCachedLogData(dict);
    BKDayData *model = [BKDayData modelWithDict:dict];
    [model saveToDatabase];
}

/**
 * Method would be invoked when received heart rate segement data（type 0x51）
 
 @param dict dict[detail_data], @{type,开始时间，结束时间，消耗能量，5个心率区间的时间分段、能量消耗、平均心率值},]
 */
- (void)updateHeartRateData:(NSDictionary *)dict{
    AXCachedLogData(dict);
    BKHeartRateData *model = [BKHeartRateData modelWithDict:dict];
    [model saveToDatabase];
}

/**
 *  Method would be invoked when received HeartRate_hours data (type 0x53).
 *  This type data shows data of heart rate in different minutes. In normal, it places one piece of data each hour, each data contains 60 values for average data of heart rate.The API/command for getting this data is @{getHeartRateDataOfHours}, call back method @{@link - (void)updateHeartRateData_hours:(NSDictionary *)dict;}
 *
 * dict[@"hour"] 小时，12表示detail的数据属于 12:00-13:00
 * dict[@"detail_data"], 一个小时内@[每分钟平均心率值]
 */
- (void)updateHeartRateData_hours:(NSDictionary *)dict{
    AXCachedLogData(dict);
    BKHeartRateHourData *model = [BKHeartRateHourData modelWithDict:dict];
    [model saveToDatabase];
}

/**
 * Method invoke by of 0x08.
 * Contain data @{key:{jsonStr}}; type key lists : 0x29\0x28,0x51,0x53;
 * jsonStr equal = @"{\"total\":%d,\"start\":%d,\"end\":%d}"; total =cicle num of seq, start=start of seq; end =end of seq
 */
- (void)updateNormalHealthData:(NSDictionary *)dict{
    AXCachedLogData(dict);
    [dict.allKeys enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *tmp = [dict stringValueForKey:obj];
        NSData *data = [tmp dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *dic = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
        BKDataIndex *model = [BKDataIndex modelWithDict:dic];
        model.dataType = obj;
        [model saveToDatabase];
    }];
}


#pragma mark -GNSS
//- (void)responseOfHealth60Data:(NSDictionary *)dict;
//- (void)responseOfHealth61IndexTable:(NSDictionary *)dict;
//- (void)responseOfHealth61Data:(NSDictionary *)dict;
//- (void)responseOfGNSS62IndexTable:(NSDictionary *)dict;
//- (void)responseOfGNSS62Data:(NSDictionary *)dict;
//- (void)responseOfGNSS63Data:(NSDictionary *)dict;
//- (void)responseOfECGIndexTable:(NSDictionary *)dict;
//- (void)responseOfECGData:(NSDictionary *)dict;
/**
 *
 *
 */
- (void)allHealthDataDidUploadSport{
    AXCachedLogOBJ(@"allHealthDataDidUploadSport");
}
- (void)allHealthDataDidUpload28{
    AXCachedLogOBJ(@"allHealthDataDidUpload28");
}
- (void)allHealthDataDidUploadHeartRate{
    AXCachedLogOBJ(@"allHealthDataDidUploadHeartRate");
}
- (void)allHealthDataDidUploadHeartRateHours{
    AXCachedLogOBJ(@"allHealthDataDidUploadHeartRateHours");
}

/**
 *  设置日程的应答
 *
 *  @param success YES 成功  NO 失败
 */
- (void)responseOfScheduleSetting:(BOOL)success{
    NSString *log = [NSString stringWithFormat:@"设置日程的应答:%d",success];
    AXCachedLogOBJ(log);
}

/**
 *  读取某个日程的应答
 *
 *  @param exist YES 存在   NO 不存在
 */
- (void)responseOfScheduleGetting:(BOOL)exist{
    NSString *log = [NSString stringWithFormat:@"读取某个日程的应答:%d",exist];
    AXCachedLogOBJ(log);
}

/**
 *  读取日程Info的应答
 *
 *  @param dict
 dict[@"cur_num"] 当前可配置日程数量
 remaining number of schedule could be set.
 dict[@"all_num"]:日程最大数量
 max number of schedule we can configure
 dict[@"day_num"]:每天可配置日程数量
 max number of schedule could  be configured for one day.
 */
- (void)responseOfScheduleInfoGetting:(NSDictionary *)dict{
    AXCachedLogOBJ(dict);
    
}

- (void)responseSplecialListsInfo:(NSDictionary *)dict{
    AXCachedLogOBJ(dict);
    
}
- (void)responseSplecialRoll:(ZeronerRoll *)zRoll{
    AXCachedLogOBJ(zRoll);
    
}





@end

