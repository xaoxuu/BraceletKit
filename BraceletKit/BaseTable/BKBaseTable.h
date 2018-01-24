//
//  BKBaseTable.h
//  BraceletKit
//
//  Created by xaoxuu on 21/01/2018.
//  Copyright © 2018 xaoxuu. All rights reserved.
//

#import <UIKit/UIKit.h>

@class FMResultSet, BKBaseTable;

@protocol BKDatabase <NSObject>

@required
/**
 表名
 
 @return 表名
 */
+ (NSString *)tableName;
/**
 列名
 
 @return 列名
 */
+ (NSString *)tableColumns;
/**
 主键
 
 @return 主键
 */
+ (NSString *)tablePrimaryKey;


/**
 model转valuestring
 
 @return valuestring
 */
- (NSString *)valueString;

/**
 set转model
 
 @param set set
 @return model
 */
+ (instancetype)modelWithSet:(FMResultSet *)set;

/**
 当前实例满足什么条件可缓存
 
 @return 当前实例满足什么条件可缓存
 */
- (BOOL)cacheable;



@optional

/**
 可以确定这条数据存在的where语句
 
 @return 可以确定这条数据存在的where语句
 */
- (NSString *)whereExists;

/**
 从数据库中恢复这条数据
 
 @return 从数据库中恢复这条数据
 */
- (instancetype)restoreFromDatabase;


/**
 取出当天的所有原始数据

 @param date 天（日期只需要精确到天）
 @return 满足条件的所有原始数据
 */
+ (NSArray<__kindof BKBaseTable *> *)selectFromDatabaseWithDate:(NSDate *)date;


/**
 取出从某个时刻到某个时刻的所有原始数据

 @param startDate 开始时间
 @param endDate 截止时间
 @return 满足条件的所有原始数据
 */
+ (NSArray<__kindof BKBaseTable *> *)selectFromDatabaseWithStartDate:(NSDate *)startDate endDate:(NSDate *)endDate;

@end


@interface BKBaseTable : NSObject


/**
 建表
 */
+ (void)createTableIfNotExists;

/**
 保存到数据库

 @return 是否成功
 */
- (BOOL)saveToDatabase;


/**
 从数据库中取出数据
 
 @param where where语句
 @return 满足条件的所有原始数据
 */
+ (NSArray<__kindof BKBaseTable *> *)selectFromDatabaseWhere:(NSString *)where;


@end