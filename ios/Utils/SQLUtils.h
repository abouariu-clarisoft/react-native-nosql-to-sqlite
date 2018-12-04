#import <Foundation/Foundation.h>
#import <FMDB.h>

NS_ASSUME_NONNULL_BEGIN

@interface SQLUtils : NSObject

+ (void)countNumberOfRecordsInTable:(NSString *)table databaseQueue:(FMDatabaseQueue *)queue completion:(void(^)(long result))completion;

@end

NS_ASSUME_NONNULL_END
