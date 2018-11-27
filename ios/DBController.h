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

- (void)configureDatabaseWithConfig:(NSDictionary *)config;
- (void)importData:(void(^)(BOOL success))completion;
- (void)performTestQuery;

@end

NS_ASSUME_NONNULL_END
