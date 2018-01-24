//
//  BKDevice.m
//  BraceletKit
//
//  Created by xaoxuu on 20/01/2018.
//  Copyright © 2018 xaoxuu. All rights reserved.
//

#import "BKDevice.h"
#import "_BKHeader.h"
#import <AVFoundation/AVFoundation.h>
#import "BKServices.h"

#import "BKUser.h"
#import "BKDevice.h"
#import "BKPreferences.h"
#import "BKDataIndex.h"
#import "BKDataDay.h"
#import "BKDataSport.h"
#import "BKDataHR.h"
#import "BKDataHRHour.h"
#import "BKDataSleep.h"
#import "BKSportList.h"


@interface BKDevice() <BLELib3Delegate>

@property (strong, nonatomic) ZeronerDeviceInfo *deviceInfo;

@property (strong, nonatomic) ZeronerHWOption *hwOption;

@end

@implementation BKDevice

+ (void)load{
    [self createTableIfNotExists];
}


+ (instancetype)currentDevice{
    return [BKServices sharedInstance].connector.device;
}





#pragma mark - ble delegate -> device setting

#pragma mark required
/*
 *  Set bracelet parameter after connect with app.
 *  like ZeronerHWOption, ZeronerPersonal
 */
- (void)setBLEParameterAfterConnect{
    AXCachedLogOBJ(@"setBLEParameterAfterConnect");
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
    return @"123456";
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
    AudioServicesPlayAlertSound(1008);
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
    [self saveToDatabase];
    AXCachedLogOBJ(deviceInfo);
    // 获取设置信息
    [[BLELib3 shareInstance] readFirmwareOption];
}

- (void)updateBattery:(ZeronerDeviceInfo *)deviceInfo{
    _deviceInfo = deviceInfo;
    _battery = AXMakeNumberInRange(@(deviceInfo.batLevel), @0, @100).doubleValue / 100.0f;
    if ([self.delegate respondsToSelector:@selector(deviceDidUpdateBatteryPercent:)]) {
        [self.delegate deviceDidUpdateBatteryPercent:self.battery];
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
    _preferences = hwOption.transformToBKPreferences;
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
}

/**
 *  Method would be invoked when received sport segement data.（data type is 0x28）
 *
 @param dict dict
 */
- (void)updateSleepData:(NSDictionary *)dict{
    AXCachedLogData(dict);
    BKDataSleep *model = [BKDataSleep modelWithDict:dict];
    [model saveToDatabase];
}

/**
 * Method would be invoked when received sport segement data .（data type is 0x28）
 
 @param dict dict
 */
- (void)updateSportData:(NSDictionary *)dict{
    AXCachedLogData(dict);
    BKDataSport *model = [BKDataSport modelWithDict:dict];
    [model saveToDatabase];
}

/**
 *  Method would be invoked when received sport summary data（type 0x29）
 *
 @param dict ：Dictionary object contains accurate timestamp provided by smartband.
 */
- (void)updateWholeDaySportData:(NSDictionary *)dict{
    AXCachedLogData(dict);
    BKDataDay *model = [BKDataDay modelWithDict:dict];
    [model saveToDatabase];
}

/**
 *  Method would be invoked when received sport summary data（type 0x29）
 *
 @param dict ：Dictionary object without accurate timestamp provided by smartband. SDK use [NSDate date] replace it.
 */
- (void)updateCurrentWholeDaySportData:(NSDictionary *)dict{
    AXCachedLogData(dict);
    BKDataDay *model = [BKDataDay modelWithDict:dict];
    [model saveToDatabase];
}

/**
 * Method would be invoked when received heart rate segement data（type 0x51）
 
 @param dict dict[detail_data], @{type,开始时间，结束时间，消耗能量，5个心率区间的时间分段、能量消耗、平均心率值},]
 */
- (void)updateHeartRateData:(NSDictionary *)dict{
    AXCachedLogData(dict);
    BKDataHR *model = [BKDataHR modelWithDict:dict];
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
    BKDataHRHour *model = [BKDataHRHour modelWithDict:dict];
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
        [column appendVarcharColumn:@"version" comma:YES];
        
        [column appendVarcharColumn:@"lastmodified" comma:NO];
        columnName = column;
    });
    return columnName;
}
+ (NSString *)tablePrimaryKey{
    return @"device_id, uuid";
}

+ (instancetype)modelWithSet:(FMResultSet *)set{
    int i = 0;
    BKDevice *model = [[BKDevice alloc] init];
    i++;// device_id
    model.mac = [set stringForColumnIndex:i++];
    model.uuid = [set stringForColumnIndex:i++];
    model.name = [set stringForColumnIndex:i++];
    model.model = [set stringForColumnIndex:i++];
    model.version = [set stringForColumnIndex:i++];
    
    return model;
}

- (NSString *)valueString{
    NSMutableString *value = [NSMutableString string];
    [value appendVarcharValue:bk_device_id() comma:YES]; // device_id = mac
    [value appendVarcharValue:self.mac comma:YES];
    [value appendVarcharValue:self.uuid comma:YES];
    [value appendVarcharValue:self.name comma:YES];
    [value appendVarcharValue:self.model comma:YES];
    [value appendVarcharValue:self.version comma:YES];
    
    [value appendVarcharValue:bk_date_string(bk_today()) comma:NO];
    return value;
}

- (BOOL)cacheable{
    return bk_user_id().length && self.mac.length && ![self.mac isEqualToString:@"advertisementData.length is less than 6"];
}

- (NSString *)whereExists{
    return [NSString stringWithFormat:@"device = '%@'", self.mac];
}

+ (instancetype)lastConnectedDevice{
    __block BKDevice *cachedDevice;
    databaseTransaction(^(FMDatabase * _Nonnull db, BOOL * _Nonnull rollback) {
        [db ax_select:@"*" from:self.tableName where:@"" orderBy:@"lastmodified DESC LIMIT 1" result:^(NSMutableArray * _Nonnull result, FMResultSet * _Nonnull set) {
            while (set.next) {
                cachedDevice = [self modelWithSet:set];
            }
        }];
    });
    return cachedDevice;
}

- (NSString *)restoreMac{
    __block NSString *mac;
    databaseTransaction(^(FMDatabase * _Nonnull db, BOOL * _Nonnull rollback) {
        NSString *where = [NSString stringWithFormat:@"uuid = '%@'", self.uuid];
        [db ax_select:@"mac" from:self.class.tableName where:where result:^(NSMutableArray * _Nonnull result, FMResultSet * _Nonnull set) {
            while (set.next) {
                mac = [set stringForColumnIndex:0];
            }
        }];
        if (!mac.length) { // 如果根据UUID找不到，可尝试根据设备name恢复
            NSString *where = [NSString stringWithFormat:@"name = '%@'", self.name];
            [db ax_select:@"mac" from:self.class.tableName where:where result:^(NSMutableArray * _Nonnull result, FMResultSet * _Nonnull set) {
                while (set.next) {
                    mac = [set stringForColumnIndex:0];
                }
            }];
        }
        if (!mac.length) { // 如果根据name找不到，可尝试根据设备model恢复
            NSString *where = [NSString stringWithFormat:@"model = '%@'", self.model];
            [db ax_select:@"mac" from:self.class.tableName where:where result:^(NSMutableArray * _Nonnull result, FMResultSet * _Nonnull set) {
                while (set.next) {
                    mac = [set stringForColumnIndex:0];
                }
            }];
        }
    });
    return mac;
}



@end
