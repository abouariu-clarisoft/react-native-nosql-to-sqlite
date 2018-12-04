#import "DBImport.h"
#import "NoSQLUtils.h"
#import "FileReader.h"

@implementation DBImport

static int queue_limit = 2000;

- (instancetype)initWithDatabaseQueue:(FMDatabaseQueue *)databaseQueue config:(NSDictionary *)config {
    if (self = [super init]) {
        self.dbQueue = databaseQueue;
        self.backgroundQueue = dispatch_queue_create("databaseBackgroundImportQueue", DISPATCH_QUEUE_SERIAL);
        self.config = config;
    }
    return self;
}

/**
 Creates SQLite tables.
 Populates the SQLite tables with data from the json files.
 @param completion Called when synchronization is complete or an error occurs
 */
- (void)importDataWithProgress:(void(^)(NSString * _Nonnull collection, NSInteger progress, NSInteger total))progress
                    completion:(void(^)(NSArray * _Nonnull errors))completion {
    
    // Create the tables
    dispatch_group_t tables_group = dispatch_group_create();
    dispatch_group_enter(tables_group);
    [self createTables:^(NSError * _Nullable error) {
        // Break when tables creation fails
        if (error) {
            completion(@[error]);
            return;
        }
        dispatch_group_leave(tables_group);
    }];
    
    dispatch_group_notify(tables_group, self.backgroundQueue, ^{
        // Populate the tables
        [self populateTables:progress completion:completion];
    });
}

/**
 Creates all the SQLite tables specified in the config file.
 @param completion Called when all tables are created or an error occurs.
 */
- (void)createTables:(void(^)(NSError * _Nullable error))completion {
    // Retrieve the order in which the tables must be created
    NSArray *tables = [self getTableCreationOrder:[self.config allKeys] processed:nil];
    // Counter used to call completion when all tables are processed
    __block NSInteger createdTables = 0;
    
    // Create tables one by one
    for (NSString *table in tables) {
        [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
            [self createTable:table
                       config:self.config
                     database:db
                     callback:^(NSError * _Nullable error) {
                         // Break when a table creation fails
                         if (error) {
                             completion(error);
                             return;
                         }
                         createdTables++;
                         
                         // call completion when all tables are created
                         if (createdTables == tables.count) {
                             completion(nil);
                         }
                     }];
        }];
    }
}

/**
 Determines the order to create tables by analyzing the foreign keys.
 When a table with foreign keys is analyzed, the referenced tables are also recursively analyzed up to the point where tables with no dependencies are found.
 If cyclic dependencies are discovered, the cycle will not be added to the result list and the number of elements of will be different from the number of elements of the input array.
 @param collections An array of strings representing the table names.
 @param processed An array of strings representing the collections that have already been added to the processing list
 @return An array of strings representing the table creation order.
 */
- (NSArray *)getTableCreationOrder:(NSArray *)collections processed:(NSMutableArray *)processed {
    // First initialization of the array that will track the tables that have already been marked for processing
    if (!processed) {
        processed = [NSMutableArray arrayWithCapacity:collections.count];
    }
    
    [collections enumerateObjectsUsingBlock:^(NSString *collection, NSUInteger idx, BOOL * _Nonnull stop) {
        
        // Every table should have the structure specified in the configuration file, assert otherwise
        NSDictionary *configCollection = self.config[collection];
        NSAssert(configCollection != nil, @"Collection %@ missing from config file!", collection);
        
        // Determine whether other tables depend on the current table
        __block BOOL dependable = NO;
        NSMutableArray *dependencies = [NSMutableArray array];
        [configCollection enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *value, BOOL * _Nonnull stop) {
            // A table is dependable if:
            // 1. it references another table
            // 2. the referenced table is not itself (self-referred tables can be independently created)
            // 3. has not already been added to the processing list
            if (value[@"references"] &&
                ![value[@"references"] isEqualToString:collection] &&
                ![processed containsObject:value[@"references"]]) {
                dependable = YES;
                // Add the table to the dependencies list to be resolved later
                [dependencies addObject:value[@"references"]];
            }
        }];
        
        // If no other tables depend on the current table, mark it for processing. Otherwise, resolve dependencies.
        if (!dependable && ![processed containsObject:collection]) {
            [processed addObject:collection];
        } else {
            // Recursively resolve dependencies
            [self getTableCreationOrder:dependencies processed:processed];
            
            // When recursively resolving dependencies, they will be added to the processed list.
            __block BOOL processedDependencies = true;
            [dependencies enumerateObjectsUsingBlock:^(NSString *dependency, NSUInteger idx, BOOL * _Nonnull stop) {
                if (![processed containsObject:dependency]) {
                    processedDependencies = NO;
                    *stop = YES;
                }
            }];
            
            // Finally, if all dependencies have been resolved, add the current table
            if (processedDependencies && ![processed containsObject:collection]) {
                [processed addObject:collection];
            }
        }
    }];
    
    return processed;
}

/**
 Creates and executes a query to create a table (if it doesn't exist) in the database based on the configuration
 @param table The table name
 @param config The configuration structure
 @param db The database name
 @param callback Invoked with (BOOL created)
 */
- (void)createTable:(NSString *)table config:(NSDictionary *)config database:(FMDatabase *)db callback:(void (^)(NSError * _Nullable error))callback {
    // Build the query to create the table
    NSMutableString *query = [[NSMutableString alloc] init];
    NSMutableString *constraint = [[NSMutableString alloc] init];
    [query appendFormat:@"CREATE TABLE IF NOT EXISTS %@(\n", table];
    __block NSInteger processed = 0;
    __block BOOL hasFKs = NO;
    [config[table] enumerateKeysAndObjectsUsingBlock:^(NSString* key, NSDictionary *value, BOOL * _Nonnull stop) {
        if (!value[@"manyOn"]) {
            [query appendFormat:@"%@ %@", key, value[@"type"]];
            if (value[@"pk"]) {
                [query appendFormat:@" PRIMARY KEY"];
            }
            [query appendFormat:@",\n"];
        }
        if (value[@"references"]) {
            hasFKs = YES;
            if (value[@"manyOn"]) {
                // Create table for many to many relationship
                NSString *tableName = [NSString stringWithFormat:@"%@_%@", table, value[@"references"]];
                NSDictionary *manyToManyConfig = @{
                                                   tableName: @{
                                                           [NSString stringWithFormat:@"%@Id", table]: @{
                                                                   @"type": @"VARCHAR(100)",
                                                                   @"references": table
                                                                   },
                                                           [NSString stringWithFormat:@"%@Id", value[@"references"]]: @{
                                                                   @"type": @"VARCHAR(100)",
                                                                   @"references": value[@"references"]},
                                                           }
                                                   };
                
                // Create the many to many table recursively
                [self createTable:tableName
                           config:manyToManyConfig
                         database:db
                         callback:callback];
            } else {
                // Add FK constraint
                [constraint appendString:@"\n"];
                [constraint appendFormat:@"CONSTRAINT fk_%@ ", value[@"references"]];
                [constraint appendFormat:@"FOREIGN KEY (%@) ", key];
                [constraint appendFormat:@"REFERENCES %@(%@)\n", value[@"references"], value[@"referencesOn"] ? value[@"referencesOn"] : @"_id"];
                [constraint appendString:@"ON DELETE SET NULL\n"];
            }
        }
        processed++;
    }];
    
    // Add the "extra field"
    [query appendString:@"extra VARCHAR(10000)"];
    
    // Add a comma if it has a foreign key
    if (hasFKs) {
        [query appendString:@",\n"];
        [query appendString:constraint];
    } else {
        [query appendString:@"\n"];
    }
    [query appendString:@");"];
    
    // Execute query to create table
    BOOL result = [db executeStatements:query];
    NSError *error = nil;
    if (!result) {
        error = [db lastError];
    }
    
    callback(error);
}

/**
 Takes every collection from the config file and populates them asynchronously in series.
 @param progress An events function called every time progress is achieved. Invoked with (NSString * _Nonnull table, NSInteger progress, NSInteger total).
 @param completion A function called when all the tables are populated or an error occurs. Invoked with (NSArray * _Nonnull errors).
 */
- (void)populateTables:(void(^)(NSString * _Nonnull table, NSInteger progress, NSInteger total))progress
            completion:(void(^)(NSArray * _Nonnull errors))completion {
    // Retrieve the order in which the tables must be populated
    NSArray *tables = [self getTableCreationOrder:[self.config allKeys] processed:nil];
    
    // Used to wait for a table to be populated before populating the next table
    dispatch_semaphore_t collectionsSemaphore = dispatch_semaphore_create(0);
    
    NSMutableArray *errors = [NSMutableArray array];
    for (NSString *table in tables) {
        NSLog(@"Populating collection %@...", table);
        [self populateTable:table semaphore:collectionsSemaphore progress:^(NSArray *recordErrors, NSInteger processed, NSInteger total) {
            if (errors.count > 0) {
                [errors addObjectsFromArray:recordErrors];
            }
            progress(table, processed, total);
        }];
        
        dispatch_semaphore_wait(collectionsSemaphore, DISPATCH_TIME_FOREVER);
    }
    completion(errors);
}

/**
 Reads the json file with the specified name line by line and inserts the records in the database table with the same name.
 @param table The name of the collection that will be read. It also represents the name of the SQLite table where the records will be inserted.
 @param collectionSemaphore A semaphore that signals when the collection processing is complete.
 @param progress A method that is called for every processed record. Invoked with (NSArray * _Nullable errors, NSInteger processed, NSInteger total).
 */
- (void)populateTable:(NSString *)table
            semaphore:(dispatch_semaphore_t)collectionSemaphore
             progress:(void(^)(NSArray * _Nullable errors, NSInteger processed, NSInteger total))progress {
    @autoreleasepool {
        
        // Count the objects in the collection to determine progress
        NSInteger total = [NoSQLUtils countNumberOfObjectsInCollection:table];
        
        // Create a file reader to parse the json file line by line
        FileReader *fileReader = [NoSQLUtils fileReaderForCollection:table];
        
        // Objects will be created in a batch of `queue_limit` at a time. Increase or decrease `queue_limit` for optimal performance.
        dispatch_semaphore_t recordsSemaphore = dispatch_semaphore_create(queue_limit);
        NSString *line = nil;
        __block NSMutableString *importableObject = nil;
        __block NSInteger processed = 0;
        while ((line = [fileReader readLine])) {
            @autoreleasepool {
                // Skip lines that do not start with 2 empty spaces. Those lines aren't part of an object, they are usually the first and last lines in the file.
                if (![line hasPrefix:@"  "]) {
                    continue;
                }
                // Mark object start
                if ([line hasPrefix:@"  {"]) {
                    importableObject = [[NSMutableString alloc] init];
                }
                // Mark object end
                if ([line hasPrefix:@"  }"]) {
                    
                    [importableObject appendString:@"  }"];
                    
                    // Create an NSDictionary from the stringified JSON
                    NSError *jsonError;
                    NSData *objectData = [importableObject dataUsingEncoding:NSUTF8StringEncoding];
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:objectData
                                                                         options:NSJSONReadingMutableContainers
                                                                           error:&jsonError];
                    
                    // Insert/update the object in database
                    __block NSMutableArray *recordsErrors = [NSMutableArray array];
                    [self convertObject:json forTable:table config:self.config[table] completion:^(NSArray * _Nullable errors) {
                        [recordsErrors addObjectsFromArray:errors];
                        dispatch_semaphore_signal(recordsSemaphore);
                    }];
                    
                    // When the object is inserted/updated, signal the record semaphore to continue with the next record
                    dispatch_semaphore_wait(recordsSemaphore, DISPATCH_TIME_FOREVER);
                    progress(recordsErrors, ++processed, total);
                } else {
                    // Append the line
                    [importableObject appendString:line];
                }
            }
        }
        // When the file is processed, signal the collection semaphore to proceed with the next file
        dispatch_semaphore_signal(collectionSemaphore);
    }
}

/**
 Converts an object from the JSON collection to an squished object (important fields + extra).
 Inserts in database the squished object and its related records (for many to many relationships);
 
 @param object The object from the JSON collection
 @param table The name of the table/JSON collection
 @param config The configuration file to perform the mapping
 @param completion Callback that is called when all the records are processed. Every error is added to an array of errors that is passed to the completion block. Invoked with (NSArray * _Nullable errors).
 */
- (void)convertObject:(NSDictionary *)object forTable:(NSString *)table config:(NSDictionary *)config completion:(void(^)(NSArray * _Nullable errors))completion {
    NSArray *importantConfigFields = [config allKeys];
    NSMutableDictionary *mappedObject = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *extraFields = [[NSMutableDictionary alloc] init];
    NSMutableArray *manyToManyRecords = [NSMutableArray array];
    [importantConfigFields enumerateObjectsUsingBlock:^(NSString *key, NSUInteger idx, BOOL * _Nonnull stop) {
        if (object[key]) {
            [mappedObject setValue:object[key] forKey:key];
            return;
        }
        // Handle embedded fields that should become columns
        if ([key containsString:@"_"]) {
            NSArray *components = [key componentsSeparatedByString:@"_"];
            //first component should be a key of the object
            if (!object[components[0]]) {
                return;
            }
            // Handle embedded fields that have many to many relationships
            if ([config[key] objectForKey:@"manyOn"]) {
                id manyArray = object[components[0]];
                if (![manyArray isKindOfClass:[NSArray class]]) {
                    NSAssert(false, @"Object %@ should be an array for M-M mapping in table %@!", components[0], table);
                } else {
                    [manyArray enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                        if (obj[components[1]]) {
                            [manyToManyRecords addObject:@{
                                                           @"table": [NSString stringWithFormat:@"%@_%@", table, config[key][@"references"]],
                                                           [NSString stringWithFormat:@"%@Id", table]: object[@"_id"],
                                                           components[1]: obj[components[1]]
                                                           }];
                        }
                    }];
                }
            } else {
                // Handle regular embedded fields (no many-to-many relationships)
                // I.e. 1: persons_0_id would be an object with key "person" that contains an array of objects that have the property "_id".
                // I.e. 2: addresses_locationId would be an object with key "addresses" that contains an object with key "locationId".
                // The last property would be of the type specified in the field "type" in the config file.
                id embeddedField = object;
                
                // Go through all the properties in depth (array or object)
                for (NSString *component in components) {
                    NSString *prop = component;
                    
                    // determine if the component is the index of an array or the key of an object
                    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
                    formatter.numberStyle = NSNumberFormatterDecimalStyle;
                    NSNumber *arrayIndex = [formatter numberFromString:component];
                    if (arrayIndex) {
                        // component is the index of an array
                        embeddedField = embeddedField[[arrayIndex integerValue]];
                    } else {
                        // component is the key of an object
                        embeddedField = [embeddedField valueForKey:prop];
                    }
                }
                
                // Set the value to be saved in the column with the given key
                [mappedObject setValue:embeddedField forKey:key];
            }
        }
    }];
    
    // All fields that are not part of the config file will be saved in a column named "extra"
    [object enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL * _Nonnull stop) {
        // throw fields that are not in config in the extra fields
        if (![importantConfigFields containsObject:key]) {
            [extraFields setObject:value forKey:key];
        }
    }];
    
    // Create the JSON string with the extra fields
    NSError *error = nil;
    NSString *stringifiedExtraFields;
    NSData *dataExtraFields = [NSJSONSerialization dataWithJSONObject:extraFields options:NSJSONWritingPrettyPrinted error:&error];
    if (error) {
        NSLog(@"Error for extra fields - not JSON serializable for object %@ in table %@", object, table);
    } else {
        stringifiedExtraFields = [[NSString alloc] initWithData:dataExtraFields encoding:NSUTF8StringEncoding];
    }
    
    // Set stringified JSON to be saved in the "extra" column
    [mappedObject setObject:stringifiedExtraFields forKey:@"extra"];
    
    __block NSMutableArray *errors = [NSMutableArray array];
    
    dispatch_group_t recordGroup = dispatch_group_create();
    dispatch_queue_t recordQueue = dispatch_queue_create("recordQueue", DISPATCH_QUEUE_CONCURRENT);
    
    dispatch_group_async(recordGroup, recordQueue, ^{
        // Insert the current record
        [self insertRecord:mappedObject inTable:table completion:^(NSError * _Nullable error) {
            if (error) {
                [errors addObject:error];
            }
        }];
    });
    
    dispatch_group_async(recordGroup, recordQueue, ^{
        // Insert the additional records related to many-to-many relationship with the current record
        [manyToManyRecords enumerateObjectsUsingBlock:^(NSDictionary *record, NSUInteger idx, BOOL * _Nonnull stop) {
            [self insertRecord:record inTable:record[@"table"] completion:^(NSError * _Nullable error) {
                if (error) {
                    [errors addObject:error];
                }
            }];
        }];
    });
    
    dispatch_group_notify(recordGroup, dispatch_queue_create("q", DISPATCH_QUEUE_CONCURRENT), ^{
        completion(errors);
    });
    
}

/**
 Inserts a record into the specified table.
 @param record The record to be inserted
 @param table The table where the record will be inserted
 @param completion Callback called once the operation is complete. Invoked with (NSError * _Nullable error)
 */
- (void)insertRecord:(NSDictionary *)record inTable:(NSString *)table completion:(void(^)(NSError * _Nullable error))completion {
    // Build SQL query
    NSMutableString *query = [[NSMutableString alloc] init];
    [query appendFormat:@"INSERT OR REPLACE INTO %@ (\n", table];
    NSMutableString *fields = [[NSMutableString alloc] initWithCapacity:[record allKeys].count];
    NSMutableString *placeHolderValues = [[NSMutableString alloc] initWithCapacity:[record allKeys].count];
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:[record allKeys].count];
    __block NSInteger processed = 0;
    
    // Parametrize query with (?) for values
    [record enumerateKeysAndObjectsUsingBlock:^(NSString *field, NSString *value, BOOL * _Nonnull stop) {
        processed++;
        if ([field isEqualToString:@"table"]) {
            return;
        }
        [fields appendFormat:@"%@", field];
        [placeHolderValues appendString:@"?"];
        if (processed == [record allKeys].count) {
            [fields appendString:@")\n"];
            [placeHolderValues appendString:@")\n"];
        } else {
            [fields appendString:@", "];
            [placeHolderValues appendString:@", "];
        }
        [values addObject:value];
    }];
    [query appendString:fields];
    [query appendString:@"VALUES ("];
    [query appendString:placeHolderValues];
    
    // Execute query
    [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
        NSError *error = nil;
        [db executeUpdate:query values:values error:&error];
        if (error) {
            NSLog(@"Error inserting object %@ in table %@: %@", record, table, error.localizedDescription);
        }
        completion(error);
    }];
}

- (void)dealloc {
    NSLog(@"dealloc DBImport");
}

@end
