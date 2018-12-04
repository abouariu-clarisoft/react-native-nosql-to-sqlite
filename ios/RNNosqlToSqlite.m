#import "RNNosqlToSqlite.h"

#import "DBController.h"

@implementation RNNosqlToSqlite

RCT_EXPORT_MODULE()

- (dispatch_queue_t)methodQueue {
    return dispatch_get_main_queue();
}

RCT_EXPORT_METHOD(configureDatabaseWithName:(NSString *)name encryptionKey:(NSString *)key config:(NSDictionary *)config ) {
    [[DBController sharedInstance] configureDatabaseWithName:name encryptionKey:key config:config];
}

RCT_EXPORT_METHOD(importDataWithProgress:(RCTResponseSenderBlock)progress callback:(RCTResponseSenderBlock)callback) {
    [[DBController sharedInstance] importDataWithProgress:^(NSString * _Nonnull collection, NSInteger progress, NSInteger total) {
        progress(@[collection, @(progress), @(total)]);
    } completion:^(NSArray * _Nonnull errors) {
        callback(@[errors.count > 0 ? errors : [NSNull null]]);
    }];
}

RCT_EXPORT_METHOD(exportDataWithProgress:(RCTResponseSenderBlock)progress callback:(RCTResponseSenderBlock)callback) {
    [[DBController sharedInstance] exportDataWithProgress:^(NSString * _Nonnull collection, NSInteger progress, NSInteger total) {
        progress(@[collection, @(progress), @(total)]);
    } completion:^(NSArray * _Nonnull errors) {
        callback(@[errors.count > 0 ? errors : [NSNull null]]);
    }];
}

RCT_EXPORT_METHOD(performSelect:(NSString *)query completion:(RCTResponseSenderBlock)callback) {
    [[DBController sharedInstance] performSelect:query
                                      completion:^(NSString * _Nullable error, NSArray * _Nullable result) {
                                          callback(@[error ? error : [NSNull null], result]);
    }];
}

RCT_EXPORT_METHOD(performUpdate:(NSString *)query completion:(RCTResponseSenderBlock)callback) {
    [[DBController sharedInstance] performUpdate:query
                                      completion:^(NSString * _Nullable error) {
                                          callback(@[error ? error : [NSNull null]]);
                                      }];
}

RCT_EXPORT_METHOD(performTestQuery) {
    [[DBController sharedInstance] performTestQuery];
}

@end
