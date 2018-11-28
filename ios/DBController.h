//
//  DBController.h
//  WHO
//
//  Created by Andrei Bouariu on 17/10/2018.
//  Copyright © 2018 clarisoft. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <FMDB.h>

NS_ASSUME_NONNULL_BEGIN

@interface DBController : NSObject

@property (nonatomic, strong, readonly) FMDatabaseQueue *dbQueue;

+ (instancetype)sharedInstance;

- (void)configureDatabaseWithName:(NSString *)name encryptionKey:(NSString *)encryptionKey config:(NSDictionary *)config;
- (void)importData:(void(^)(BOOL success))completion;
- (void)performSelect:(NSString *)query completion:(void(^)( NSString * _Nullable error, NSInteger affectedRows, NSArray * _Nullable result))completion;
- (void)performTestQuery;

@end

NS_ASSUME_NONNULL_END
