#import <Foundation/Foundation.h>
#import <FMDB.h>

NS_ASSUME_NONNULL_BEGIN

@interface DBImport : NSObject

@property (nonatomic, strong) FMDatabaseQueue *dbQueue;
@property (nonatomic) dispatch_queue_t backgroundQueue;
@property (nonatomic, strong) NSDictionary *config;

- (instancetype)initWithDatabaseQueue:(FMDatabaseQueue *)databaseQueue config:(NSDictionary *)config;
- (void)importDataWithProgress:(void(^)(NSString * _Nonnull collection, NSInteger progress, NSInteger total))progress
                    completion:(void(^)(NSArray * _Nonnull errors))completion;

@end

NS_ASSUME_NONNULL_END
