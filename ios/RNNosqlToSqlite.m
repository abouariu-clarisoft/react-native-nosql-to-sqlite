#import "RNNosqlToSqlite.h"

#import "DBController.h"

@implementation RNNosqlToSqlite

RCT_EXPORT_MODULE();

- (dispatch_queue_t)methodQueue {
    return dispatch_get_main_queue();
}

- (NSArray<NSString *> *)supportedEvents {
    return @[@"ImportProgress", @"ExportProgress"];
}

RCT_EXPORT_METHOD(configureDatabaseWithName:(NSString *)name encryptionKey:(NSString *)key config:(NSDictionary *)config ) {
    [[DBController sharedInstance] configureDatabaseWithName:name encryptionKey:key config:config];
}

RCT_EXPORT_METHOD(importData:(RCTResponseSenderBlock)callback) {
    [[DBController sharedInstance] importDataWithProgress:^(NSString * _Nonnull collection, NSInteger processed, NSInteger total) {
        [self sendEventWithName:@"ImportProgress" body:@[collection, @(processed), @(total)]];
    } completion:^(NSArray * _Nonnull errors) {
        callback(@[errors.count > 0 ? errors : [NSNull null]]);
    }];
}

RCT_EXPORT_METHOD(exportData:(RCTResponseSenderBlock)callback) {
    [[DBController sharedInstance] exportDataWithProgress:^(NSString * _Nonnull collection, NSInteger processed, NSInteger total) {
        [self sendEventWithName:@"ExportProgress" body:@[collection, @(processed), @(total)]];
    } completion:^(NSArray * _Nonnull errors) {
        callback(@[errors.count > 0 ? errors : [NSNull null]]);
    }];
}

RCT_EXPORT_METHOD(performSelect:(NSString *)query completion:(RCTResponseSenderBlock)callback) {
    [[DBController sharedInstance] performSelect:query
                                      completion:^(NSError * _Nullable error, NSArray * _Nullable result) {
                                          callback(@[error ? error : [NSNull null], result]);
                                      }];
}

RCT_EXPORT_METHOD(performUpdate:(NSString *)query completion:(RCTResponseSenderBlock)callback) {
    [[DBController sharedInstance] performUpdate:query
                                      completion:^(NSError * _Nullable error) {
                                          callback(@[error ? error : [NSNull null]]);
                                      }];
}

RCT_EXPORT_METHOD(performTestQuery) {
    [[DBController sharedInstance] performTestQuery];
}

@end
