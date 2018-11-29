#import "RNNosqlToSqlite.h"

#import "DBController.h"

@implementation RNNosqlToSqlite

RCT_EXPORT_MODULE()

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

RCT_EXPORT_METHOD(configureDatabaseWithName:(NSString *)name encryptionKey:(NSString *)key config:(NSDictionary *)config ) {
    [[DBController sharedInstance] configureDatabaseWithName:name encryptionKey:key config:config];
}

RCT_EXPORT_METHOD(importData:(RCTResponseSenderBlock)callback) {
    [[DBController sharedInstance] importData:^(BOOL success) {
        callback(@[[NSNull null]]);
    }];
}

RCT_EXPORT_METHOD(performSelect:(NSString *)query completion:(RCTResponseSenderBlock)callback) {
    [[DBController sharedInstance] performSelect:query
                                      completion:^(NSString * _Nullable error, NSInteger affectedRows, NSArray * _Nullable result) {
                                          callback(@[error ? error : [NSNull null], @(affectedRows), result]);
    }];
}

RCT_EXPORT_METHOD(performTestQuery) {
    [[DBController sharedInstance] performTestQuery];
}

@end
