#import "DBController.h"
#import "DBImport.h"
#import "DBExport.h"

#import <sqlite3.h>

@interface DBController ()

@property (nonatomic, strong, readonly) NSString *databaseFileName;
@property (nonatomic, strong, readonly) NSString *databasePath;
@property (nonatomic, strong, readonly) NSString *encryptionKey;
@property (nonatomic, strong, readonly) NSDictionary *config;

@end

@implementation DBController

+ (instancetype)sharedInstance {
    static DBController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[DBController alloc] init];
    });
    return instance;
}

/**
 Sets the database path and filename in the application Documents directory
 @param databaseName The name of the database
 */
- (void)configureDatabasePath:(NSString *)databaseName {
    NSArray *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentDir = [documentPaths objectAtIndex:0];
    _databaseFileName = databaseName;
    _databasePath = [documentDir stringByAppendingPathComponent:_databaseFileName];
}

/**
 Sets the database encyption key
 @param encryptionKey The database encryption key
 */
- (void)configureEncryptionKey:(NSString *)encryptionKey {
    _encryptionKey = encryptionKey;
}

/**
 Configures the database, sets the configuration, sets the encryption key and opens the database.
 @param name The database name
 @param encryptionKey The encryption key
 @param config The configuration dictionary that describes the database structure
 */
- (void)configureDatabaseWithName:(NSString *)name encryptionKey:(NSString *)encryptionKey config:(NSDictionary *)config {
    [self configureDatabasePath:name];
    [self configureEncryptionKey:encryptionKey];
    _config = config;
    _dbQueue = [FMDatabaseQueue databaseQueueWithPath:self.databasePath];
    [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
        [db open];
        [db setKey:encryptionKey];
    }];
}

/**
 Starts the database import process
 @param progress Function that is called with progress (collection, processed and total)
 @param completion Function that is called when the import is complete
 */
- (void)importDataWithProgress:(void (^)(NSString * _Nonnull, NSInteger, NSInteger))progress completion:(void (^)(NSArray * _Nonnull))completion {
    DBImport *import = [[DBImport alloc] initWithDatabaseQueue:self.dbQueue
                                                        config:self.config];
    [import importDataWithProgress:progress completion:completion];
}

/**
 Starts the database export process
 @param progress Function that is called with progress (collection, processed and total)
 @param completion Function that is called when the export is complete
 */
- (void)exportDataWithProgress:(void (^)(NSString * _Nonnull, NSInteger, NSInteger))progress
                    completion:(void (^)(NSArray * _Nonnull))completion {
    DBExport *export = [[DBExport alloc] initWithDatabaseQueue:self.dbQueue
                                                        config:self.config];
    [export exportDataWithProgresss:progress completion:completion];
}

/**
 Executes a query on 3 joined tables
 */
- (void)performTestQuery {
    
    /**
     Select follow-ups that meet the following criteria:
     follow-up date is between 2 specified days
     follow-up has a specified status
     person has a specified age
     person has a specified gender
     includes cases (person's id is either person_0_id or person_1_id in a record from relationship table)
     results are ordered by follow-up's date and id descending
     results are paginated
     */
    
    NSDate *date = [NSDate date];
    NSLog(@"%@ Started executing query...", date);
    NSString *query = @"select \
    F.extra as 'followup-extra', \
    P.extra as 'person-extra', \
    R1.extra as 'relationship1-extra', \
    R2.extra as 'relationship2-extra' \
    from followUp as F \
    join person AS P on P._id = F.personId \
    and F.date between '2018-11-01' and '2018-11-23' \
    and F.statusId = 'LNG_REFERENCE_DATA_CONTACT_DAILY_FOLLOW_UP_STATUS_TYPE_NOT_PERFORMED' \
    and P.age_years between 14 and 80 \
    and P.gender = 'LNG_REFERENCE_DATA_CATEGORY_GENDER_MALE' \
    left join relationship as R1 on R1.persons_0_id = P._id \
    left join relationship as R2 on R2.persons_1_id = P._id \
    order by F.date, F._id desc \
    limit 20, 10";
    
    [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
        FMResultSet *set = [db executeQuery:query];
        while ([set next]) {
            NSLog(@"%@", [set stringForColumn:@"followup-extra"]);
        }
        NSDate *endDate = [NSDate date];
        NSLog(@"%@ Query executed in %f ms", endDate, [endDate timeIntervalSinceDate:date]*1000);
    }];
}

/**
 Executes a SELECT statement and returns the results in an array. The array contains objects with the column names as keys.
 Joining tables with the same column names will result the value of the last column to be overwritten in the object record.
 Therefore, is advisable to perform queries that return records with unique column names.
 @param query The SELECT query
 @param completion Invoked with (NSError * _Nullable error, NSArray * _Nullable result)
 */
- (void)performSelect:(NSString *)query completion:(nonnull void (^)(NSError * _Nullable, NSArray * _Nullable))completion {
    [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
        // Execute query
        FMResultSet *set = [db executeQuery:query];
        
        // A null set means an error occurred
        if (!set) {
            // return completion with error
            completion(db.lastError, nil);
            return;
        }
        
        // Add records to result array
        NSMutableArray *result = [[NSMutableArray alloc] init];
        while ([set next]) {
            [result addObject:[set resultDictionary]];
        }
        
        // Call completion with result
        completion(nil, result);
    }];
}

/**
 Executes CREATE, UPDATE, INSERT, ALTER, COMMIT, BEGIN, DETACH, DELETE, DROP, END, EXPLAIN, VACUUM, and REPLACE statements and calls completion with a nullable NSString representing an error message.
 @param query The query to be executed
 @param completion Invoked with (NSString * _Nullable error)
 */
- (void)performUpdate:(NSString *)query completion:(void (^)(NSError * _Nullable))completion {
    [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
        // Execute query
        BOOL result = [db executeUpdate:query];
        completion(result ? nil : db.lastError);
    }];
}

/**
 Closes the database
 */
- (void)closeDatabase {
    [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
        [db close];
    }];
}

@end
