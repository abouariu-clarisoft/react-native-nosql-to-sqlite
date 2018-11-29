//
//  DBController.m
//  WHO
//
//  Created by Andrei Bouariu on 17/10/2018.
//  Copyright © 2018 clarisoft. All rights reserved.
//

#import "DBController.h"
#import "FileReader.h"

#import <sqlite3.h>

@interface DBController ()

@property (nonatomic, strong, readonly) NSString *databaseFileName;
@property (nonatomic, strong, readonly) NSString *databasePath;
@property (nonatomic, strong, readonly) NSString *encryptionKey;
@property (nonatomic, strong, readonly) NSDictionary *config;
@property (nonatomic, strong, readonly) dispatch_queue_t backgroundQueue;

@end

@implementation DBController

+ (instancetype)sharedInstance {
    static DBController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[DBController alloc] init];
        [instance configureBackgroundQueue];
    });
    return instance;
}


/**
 Initializes a serial background queue that will be used for import operations.
 */
- (void)configureBackgroundQueue {
    _backgroundQueue = dispatch_queue_create("databaseBackgroundQueue", DISPATCH_QUEUE_SERIAL);
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
 Receives an array with filenames of the collections that must be imported in the database.
 These collections are found in the documents directory.
 */
- (void)importData:(void (^)(BOOL))completion {
    NSArray *collections = [[self.config allKeys] sortedArrayUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        // force a collection to be processed first
        /*
         if ([obj1 isEqualToString:@"relationship"]) {
         if ([obj1 compare:obj2] == NSOrderedAscending) {
         return NSOrderedAscending;
         } else return NSOrderedDescending;
         }
         if ([obj2 isEqualToString:@"relationship"]) {
         if ([obj1 compare:obj2] == NSOrderedAscending) {
         return NSOrderedDescending;
         } else return NSOrderedAscending;
         }
         */
        return [obj1 compare:obj2];
    }];
    
    // Determine the order to create the tables
    NSArray *tableOrder = [self getTableCreationOrder:collections processed:nil];
    NSAssert(tableOrder.count == collections.count, @"Unable to determine table creation order due to dependencies!");
    
    // Import data in each table
    [collections enumerateObjectsUsingBlock:^(NSString *collection, NSUInteger idx, BOOL * _Nonnull stop) {
        dispatch_async(self.backgroundQueue, ^{
            NSLog(@"Started importing collection %@...", collection);
            [self importCollection:collection];
            NSLog(@"Finished importing data in collection %@!", collection);
            // Call completion when all collections have been imported
            if (idx == collections.count - 1) {
                completion(YES);
            }
        });
    }];
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

- (void)importCollection:(NSString *)collection {
    
    // create the table
    __weak typeof (self) weakSelf = self;
    [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
        [weakSelf createTable:collection config:weakSelf.config database:db callback:^(BOOL created) {
            if (!created) {
                NSLog(@"Collection %@ not created!", collection);
            }
        }];
    }];
    
    // import data
    NSArray *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentDir = [documentPaths objectAtIndex:0];
    FileReader *fileReader = [[FileReader alloc] initWithFilePath:[documentDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", collection]]];
    
    __block NSMutableString *importableObject;
    [fileReader enumerateLinesUsingBlock:^(NSString * _Nonnull line, BOOL * _Nonnull stop) {
        // parse the ugly object that destroys lifes
        if (![line hasPrefix:@"  "]) {
            return;
        }
        
        //mark object start
        if ([line hasPrefix:@"  {"]) {
            importableObject = [[NSMutableString alloc] init];
        }
        
        // mark object end
        if ([line hasPrefix:@"  }"]) {
            [importableObject appendString:@"  }"];
            //process object
            NSError *jsonError;
            NSData *objectData = [importableObject dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:objectData
                                                                 options:NSJSONReadingMutableContainers
                                                                   error:&jsonError];
            
            [self convertObject:json forTable:collection config:self.config[collection]];
        } else {
            [importableObject appendString:line];
        }
    }];
}


/**
 Creates a table (if it doesn't exist) based on the configuration
 
 @param table The table name
 @param config The configuration structure
 @param db The database name
 @param callback Invoked with (BOOL created)
 */
- (void)createTable:(NSString *)table config:(NSDictionary *)config database:(FMDatabase *)db callback:(void (^)(BOOL created))callback {
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
                // create table for many to many relationship
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
                [self createTable:tableName
                           config:manyToManyConfig
                         database:db
                         callback:callback];
            } else {
                // add FK constraint
                [constraint appendString:@"\n"];
                [constraint appendFormat:@"CONSTRAINT fk_%@ ", value[@"references"]];
                [constraint appendFormat:@"FOREIGN KEY (%@) ", key];
                [constraint appendFormat:@"REFERENCES %@(%@)\n", value[@"references"], value[@"referencesOn"] ? value[@"referencesOn"] : @"_id"];
                [constraint appendString:@"ON DELETE SET NULL\n"];
            }
        }
        processed++;
    }];
    [query appendString:@"extra VARCHAR(5000)"];
    if (hasFKs) {
        [query appendString:@",\n"];
        [query appendString:constraint];
    } else {
        [query appendString:@"\n"];
    }
    [query appendString:@");"];
    
    BOOL result = [db executeStatements:query];
    
    callback(result);
}

- (void)convertObject:(NSDictionary *)object forTable:(NSString *)table config:(NSDictionary *)config {
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
    
    // Insert the current record
    [self insertRecord:mappedObject inTable:table];
    
    // Insert the additional records related to many-to-many relationship with the current record
    [manyToManyRecords enumerateObjectsUsingBlock:^(NSDictionary *record, NSUInteger idx, BOOL * _Nonnull stop) {
        [self insertRecord:record inTable:record[@"table"]];
    }];
    
}

- (void)insertRecord:(NSDictionary *)record inTable:(NSString *)table {
    NSMutableString *query = [[NSMutableString alloc] init];
    [query appendFormat:@"INSERT OR REPLACE INTO %@ (\n", table];
    NSMutableString *fields = [[NSMutableString alloc] initWithCapacity:[record allKeys].count];
    NSMutableString *placeHolderValues = [[NSMutableString alloc] initWithCapacity:[record allKeys].count];
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:[record allKeys].count];
    __block NSInteger processed = 0;
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
    
    [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
        NSError *error = nil;
        [db executeUpdate:query values:values error:&error];
        if (error) {
            NSLog(@"Error inserting object %@ in table %@: %@", record, table, error.localizedDescription);
        }
    }];
}

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
    limit 100, 50";
    
    [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
        FMResultSet *set = [db executeQuery:query];
        NSInteger count = 0;
        while ([set next]) {
            count++;
            NSLog(@"%d", [set intForColumn:@"age_years"]);
        }
        NSDate *endDate = [NSDate date];
        NSLog(@"%@ Query execution complete! %ld results returned in %f ms", endDate, count, [endDate timeIntervalSinceDate:date]*1000);
    }];
}

/**
 Executes a SELECT statement and returns the results in an array. The array contains objects with the column names as keys.
 Joining tables with the same column names will result the value of the last column to be overwritten in the object record.
 Therefore, is advisable to perform queries that return records with unique column names.
 @param query The SELECT query
 @param completion Invoked with (error, affectedRows, result)
 */
- (void)performSelect:(NSString *)query completion:(nonnull void (^)(NSString * _Nullable, NSInteger, NSArray * _Nullable))completion {
    [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
        // execute query
        FMResultSet *set = [db executeQuery:query];
        
        // null set represents error
        if (!set) {
            // return completion with error
            completion(db.lastErrorMessage, 0, nil);
            return;
        }
        
        // add records to result array
        NSMutableArray *result = [[NSMutableArray alloc] init];
        while ([set next]) {
            [result addObject:[set resultDictionary]];
        }
        
        // call completion with result
        completion(nil, 0, result);
    }];
}

@end
