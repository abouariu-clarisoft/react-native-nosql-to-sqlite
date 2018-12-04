#import "SQLUtils.h"

@implementation SQLUtils

/**
Counts the number of records in a table.
 @param table The name of the table.
 @param queue The FMDB database queue that will be used to execute the statement.
 @param completion The completion block called when the operation is complete. Invoked with (long result).
 */
+ (void)countNumberOfRecordsInTable:(NSString *)table databaseQueue:(FMDatabaseQueue *)queue completion:(void(^)(long result))completion {
    [queue inDatabase:^(FMDatabase * _Nonnull db) {
        long result = [db longForQuery:[NSString stringWithFormat:@"SELECT COUNT(*) FROM %@", table]];
        completion(result);
    }];
}

@end
