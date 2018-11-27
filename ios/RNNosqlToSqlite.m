#import "RNNosqlToSqlite.h"

#import "DBController.h"

@implementation RNNosqlToSqlite

RCT_EXPORT_MODULE()

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

RCT_EXPORT_METHOD(configureDatabaseWithConfig:(NSDictionary *)config) {
    [[DBController sharedInstance] configureDatabaseWithConfig:config];
}

RCT_EXPORT_METHOD(importData:(RCTResponseSenderBlock)callback) {
    [[DBController sharedInstance] importData:^(BOOL success) {
        callback(@[[NSNull null]]);
    }];
}

RCT_EXPORT_METHOD(performTestQuery) {
    [[DBController sharedInstance] performTestQuery];
}

@end
