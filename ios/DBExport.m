#import "DBExport.h"
#import "SQLUtils.h"

@interface DBExport ()

@property (nonatomic, strong) NSString *exportPath;

@end

@implementation DBExport

// Records will be exported in batches of batch_limit
static long batch_limit = 100;

- (instancetype)initWithDatabaseQueue:(FMDatabaseQueue *)databaseQueue config:(NSDictionary *)config {
    if (self = [super init]) {
        self.dbQueue = databaseQueue;
        self.backgroundQueue = dispatch_queue_create("databaseBackgroundExportQueue", DISPATCH_QUEUE_SERIAL);
        self.config = config;
        
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        self.exportPath = [[paths objectAtIndex:0] stringByAppendingString:@"/Export"];
    }
    return self;
}

/**
 Removes the directory called "Export" from the Documents directory (if any) and creates it again.
 Exports every table from the SQLite database to its own JSON file in the Export directory.
 @param progress Function called every time a batch of records finishes writing. Invoked with (NSString * _Nonnull collection, NSInteger progress, NSInteger total)
 @param completion Function called when the export process is complete. Invoked with (NSArray * _Nonnull) representing an array of encountered errors.
 */
- (void)exportDataWithProgresss:(void (^)(NSString * _Nonnull, NSInteger, NSInteger))progress
                     completion:(void (^)(NSArray * _Nonnull))completion {
    
    // Clean the Export directory
    NSError *error = [self manageExportFolder];
    if (error) {
        completion(@[error]);
        return;
    }
    
    // Retrieve the tables sorted alphabetically
    NSArray *tables = [self orderedTables];
    
    // Allocate errors array that will be passed to the completion handler
    __block NSMutableArray *exportErrors = [NSMutableArray array];
    
    // Execute the export on the background thread
    dispatch_async(self.backgroundQueue, ^{
        
        // The semaphore will process one collection at a time
        dispatch_semaphore_t collectionsSemaphore = dispatch_semaphore_create(0);
        
        for (NSString *table in tables) {
            NSLog(@"Exporting collection %@...", table);
            [self exportTable:table progress:^(NSArray * _Nonnull collectionExportErrors, NSInteger processed, NSInteger total) {
                
                // Report progress
                progress(table, processed, total);
                
            } completion:^(NSArray * _Nonnull collectionExportErrors) {
                
                // Add the collection error list to the process error list
                [exportErrors addObjectsFromArray:collectionExportErrors];
                
                // Continue with next collection
                dispatch_semaphore_signal(collectionsSemaphore);
            }];
            
            dispatch_semaphore_wait(collectionsSemaphore, DISPATCH_TIME_FOREVER);
        }
        
        // Call completion when all tables are exported
        completion(exportErrors);
        
    });
}

/**
 Deletes and creates the "Export" directory in the Documents directory.
 @return nil if no error occurs and an NSError object otherwise.
 */
- (NSError * _Nullable)manageExportFolder {
    
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.exportPath error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.exportPath
                              withIntermediateDirectories:NO
                                               attributes:nil
                                                    error:&error];
    return error;
}

/**
 Returns an array with the collections from config sorted alphabetically
 */
- (NSArray *)orderedTables {
    return [[self.config allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *  _Nonnull obj1, NSString * _Nonnull obj2) {
        return [obj1 compare:obj2];
    }];
}

/**
 Retrieves all records from a table in batches of batch_limit, converts them to JSON and writes them to a json file with the table name in the Export directory.
 @param table The name of the table.
 @param progress Block called when a batch of records finishes processing. Invoked with (NSArray * _Nonnull errors, NSInteger processed, NSInteger total).
 @param completion Block called when the collection export is complete. Invoked with (NSArray * _Nonnull errors).
 */
- (void)exportTable:(NSString *)table
           progress:(void(^)(NSArray * _Nonnull errors, NSInteger processed, NSInteger total))progress
         completion:(void(^)(NSArray * _Nonnull errors))completion {
    
    // Count all objects in collection to determine progress. Since the method will take more time to execute by counting the objects, this will be done only if the progress block exists.
    __block long numberOfRecords = 0;
    if (progress) {
        [SQLUtils countNumberOfRecordsInTable:table databaseQueue:self.dbQueue completion:^(long result) {
            numberOfRecords = result;
        }];
    }
    
    // Create the file where the collection will be written
    NSString *collectionPath = [NSString stringWithFormat:@"%@/%@.json", self.exportPath, table];
    [[NSFileManager defaultManager] createFileAtPath:collectionPath contents:nil attributes:nil];
    
    // A file handle that will be used to write in the json collection
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:collectionPath];
    
    // Open the collection array by writing "["
    [handle writeData:[@"[" dataUsingEncoding:NSUTF8StringEncoding]];
    
    // A semaphore that will process a batch at a time
    dispatch_semaphore_t batchSemaphore = dispatch_semaphore_create(0);
    
    __block BOOL isFirstRecord = YES;
    __block BOOL keepProcessing = YES;
    __block long skip = 0;
    __block NSMutableArray *errors = [NSMutableArray array];
    
    while (keepProcessing) {
        
        @autoreleasepool {
            
            NSString *query = [NSString stringWithFormat:@"SELECT * from %@ order by _id limit %ld, %ld", table, skip, batch_limit];
            
            // Execute query
            [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
                FMResultSet *set = [db executeQuery:query];
                
                __block long processed = 0;
                
                if (set) {
                    
                    // A semaphore that will process a record at a time
                    dispatch_semaphore_t recordSemaphore = dispatch_semaphore_create(0);
                    __block NSInteger numberOfRecordsInBatch = 0;
                    
                    // Query successfully executed
                    while ([set next]) {
                        
                        numberOfRecordsInBatch++;
                        
                        // The resultDictionary property of the set will be used to rebuild the object by setting all keys, extracting the "extra" field keys as root keys and then deleting the "extra" field.
                        NSMutableDictionary *record = [NSMutableDictionary dictionaryWithDictionary:set.resultDictionary];
                        
                        // Change boolean values from 1/0 to true/false
                        __block NSMutableDictionary *booleans = [[NSMutableDictionary alloc] init];
                        [record enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, id _Nonnull value, BOOL * _Nonnull stop) {
                            NSDictionary *configForTable = [self.config objectForKey:table];
                            NSDictionary *configForKey = [configForTable objectForKey:key];
                            if ([[configForKey objectForKey:@"type"] isEqualToString:@"BOOLEAN"]) {
                                if (value && value != [NSNull null]) {
                                    value = [value boolValue] ? @YES : @NO;
                                } else {
                                    value = @NO;
                                }
                                [booleans setObject:value forKey:key];
                            }
                        }];
                        [record setValuesForKeysWithDictionary:booleans];
                        
                        // Extract "extra" field and rebuild object
                        [self convertSQLiteRecordToJSON:set completion:^(NSError * _Nullable error, NSDictionary *result) {
                            
                            if (error) {
                                // Error rebuilding object
                                [errors addObject:error];
                                
                                // Signal the records semaphore
                                dispatch_semaphore_signal(recordSemaphore);
                            } else {
                                
                                // set all fields from "extra" as root keys
                                [record setValuesForKeysWithDictionary:result];
                                
                                // remove the field "extra"
                                [record removeObjectForKey:@"extra"];
                                
                                // The record object is a dictionary that can be exported to the JSON collection
                                // Save the object to the export file
                                NSError * error = [self writeJSONRecord:record toFileHandle:handle isFirst:isFirstRecord];
                                
                                if (!error) {
                                    // Increase the processed records number
                                    processed++;
                                    
                                    // Mark the first record as processed
                                    isFirstRecord = NO;
                                }
                                
                                // Report progress
                                progress(errors, processed + skip, numberOfRecords);
                                
                                // Signal the records semaphore
                                dispatch_semaphore_signal(recordSemaphore);
                                
                            }
                        }];
                        
                        // Don't go to the next record in loop until the current one completes
                        dispatch_semaphore_wait(recordSemaphore, DISPATCH_TIME_FOREVER);
                        
                    }
                    
                    // If the set has no records, the collection is complete, exit loop on next cycle
                    if (numberOfRecordsInBatch == 0) {
                        keepProcessing = NO;
                    }
                    
                } else {
                    
                    // Error executing query
                    [errors addObject:[db lastError]];
                    
                    // Report progress
                    progress(errors, processed, numberOfRecords);
                    
                }
                
                // Increase pagination for next query
                skip += batch_limit;
                
                // Signal semaphore to continue loop
                dispatch_semaphore_signal(batchSemaphore);
                
            }];
            
            // Wait until operation above completes
            dispatch_semaphore_wait(batchSemaphore, DISPATCH_TIME_FOREVER);
        }
    }
    
    // Close the collection array by writing "]"
    [handle writeData:[@"]" dataUsingEncoding:NSUTF8StringEncoding]];
    
    // Close the file handle
    [handle closeFile];
    
    // Call the completion
    completion(errors);
}

/**
 Extracts the "extra" field from a FMResult set, attempts to parse it as a JSON and passes it to completion as an NSDictionary.
 @param set The FMResult set used to extract the field.
 @param completion Called when operation is complete. Invoked with (NSError * _Nullable error, NSDictionary *result).
 */
- (void)convertSQLiteRecordToJSON:(FMResultSet *)set completion:(void(^)(NSError * _Nullable error, NSDictionary *result))completion {
    NSError *error = nil;
    NSString *extra = [set stringForColumn:@"extra"];
    NSData * data = [extra dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *extraJSON = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
    completion(error, extraJSON);
}

/**
 Writes a JSON record to a file handle.
 If 'isFirst' is set to true, it will prepend an '[' character to open the array of the collection. Otherwise, it will prepend a ',' character to follow the previous record.
 @param record A NSDictionary that will be written to file.
 @param fileHandle A NSFileHandle used to write to the file.
 @param isFirst A boolean value specifying if the record is the first record of the collection.
 @return An error in case of failure and nil otherwise.
 */
- (NSError * _Nullable)writeJSONRecord:(NSDictionary *)record toFileHandle:(NSFileHandle *)fileHandle isFirst:(BOOL)isFirst {
    NSError *error = nil;
    // Stringify the dictionary to JSON
    NSData *jsonRecord = [NSJSONSerialization dataWithJSONObject:record
                                                         options:NSJSONWritingPrettyPrinted
                                                           error:&error];
    if (!error) {
        // Write to file
        // Write "," from the 2nd record onwards
        NSString *prepend = nil;
        if (!isFirst) {
            prepend = @",\n";
        }
        [fileHandle writeData:[prepend dataUsingEncoding:NSUTF8StringEncoding]];
        
        // Write the string to the file handler
        [fileHandle writeData:jsonRecord];
    }
    return error;
}

@end
