#import <Foundation/Foundation.h>

#import <FMDB.h>

NS_ASSUME_NONNULL_BEGIN

@interface DBController : NSObject

@property (nonatomic, strong, readonly) FMDatabaseQueue *dbQueue;

+ (instancetype)sharedInstance;

- (void)configureDatabaseWithName:(NSString *)name encryptionKey:(NSString *)encryptionKey config:(NSDictionary *)config;
- (void)importDataWithProgress:(void(^)(NSString * _Nonnull collection, NSInteger progress, NSInteger total))progress
                    completion:(void(^)(NSArray * _Nonnull errors))completion;
- (void)exportDataWithProgress:(void(^)(NSString * _Nonnull collection, NSInteger progress, NSInteger total))progress
                    completion:(void(^)(NSArray * _Nonnull errors))completion;
- (void)performSelect:(NSString *)query completion:(void(^)(NSError * _Nullable error, NSArray * _Nullable result))completion;
- (void)performUpdate:(NSString *)query completion:(void(^)(NSError * _Nullable error))completion;

- (void)performTestQuery;
- (void)closeDatabase;

@end

NS_ASSUME_NONNULL_END
