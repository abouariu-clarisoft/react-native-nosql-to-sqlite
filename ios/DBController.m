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
@property (nonatomic, strong, readonly) FMDatabase *db;
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
        [instance configureDatabasePath];
        [instance configureEncryptionKey];
    });
    return instance;
}

- (void)configureBackgroundQueue {
    _backgroundQueue = dispatch_queue_create("databaseBackgroundQueue", 0);
}

- (void)configureDatabasePath {
    NSArray *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentDir = [documentPaths objectAtIndex:0];
    _databaseFileName = @"database.sqlite";
    _databasePath = [documentDir stringByAppendingPathComponent:_databaseFileName];
}

- (void)configureEncryptionKey {
    _encryptionKey = @"key";
}

- (void)configureDatabaseWithConfig:(NSDictionary *)config {
    //    sqlite3 *db;
    //    sqlite3_stmt *stmt;
    //    bool sqlcipher_valid = NO;
    
    //    if (sqlite3_open([self.databasePath UTF8String], &db) == SQLITE_OK) {
    //        const char* key = [self.encryptionKey UTF8String];
    //        sqlite3_key(db, key, strlen(key));
    //        if (sqlite3_exec(db, (const char*) "SELECT count(*) FROM sqlite_master;", NULL, NULL, NULL) == SQLITE_OK) {
    //            if(sqlite3_prepare_v2(db, "PRAGMA cipher_version;", -1, &stmt, NULL) == SQLITE_OK) {
    //                if(sqlite3_step(stmt)== SQLITE_ROW) {
    //                    const unsigned char *ver = sqlite3_column_text(stmt, 0);
    //                    if(ver != NULL) {
    //                        sqlcipher_valid = YES;
    //
    //                        // password is correct (or database initialize), and verified to be using sqlcipher
    //
    //                    }
    //                }
    //                sqlite3_finalize(stmt);
    //            }
    //        }
    //        sqlite3_close(db);
    //    }
    
    _config = config;
    _db = [FMDatabase databaseWithPath:self.databasePath];
    _dbQueue = [FMDatabaseQueue databaseQueueWithPath:self.databasePath];
    [self.db open];
        [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
            //        [self.db setKey:self.encryptionKey];
        }];
}

/**
 Receives an array with filenames of the collections that must be imported in the database.
 These collections are found in the documents directory.
 */
- (void)importData {
    NSArray *collections = [[self.config allKeys] sortedArrayUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        return [obj1 compare:obj2];
    }];
    NSArray *tableOrder = [self getTableCreationOrder:collections processed:nil];
    NSAssert(tableOrder.count == collections.count, @"Unable to determine table creation order due to dependencies!");
    [collections enumerateObjectsUsingBlock:^(NSString *collection, NSUInteger idx, BOOL * _Nonnull stop) {
        dispatch_async(self.backgroundQueue, ^{
            NSLog(@"Started importing collection %@...", collection);
            [self importCollection:collection];
            NSLog(@"Finished importing data in collection %@!", collection);
        });
    }];
}

- (NSArray *)getTableCreationOrder:(NSArray *)collections processed:(NSMutableArray *)processed {
    if (!processed) {
        processed = [NSMutableArray arrayWithCapacity:collections.count];
    }
    [collections enumerateObjectsUsingBlock:^(NSString *collection, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary *configCollection = self.config[collection];
        NSAssert(configCollection != nil, @"Collection %@ missing from config file!", collection);
        __block BOOL dependable = NO;
        NSMutableArray *dependencies = [NSMutableArray array];
        [configCollection enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *value, BOOL * _Nonnull stop) {
            if (value[@"references"] && ![value[@"references"] isEqualToString:collection] && ![processed containsObject:value[@"references"]]) {
                dependable = YES;
                [dependencies addObject:value[@"references"]];
            }
        }];
        if (!dependable && ![processed containsObject:collection]) {
            [processed addObject:collection];
        } else {
            [self getTableCreationOrder:dependencies processed:processed];
            __block BOOL processedDependencies = true;
            [dependencies enumerateObjectsUsingBlock:^(NSString *dependency, NSUInteger idx, BOOL * _Nonnull stop) {
                if (![processed containsObject:dependency]) {
                    processedDependencies = NO;
                    *stop = YES;
                }
            }];
            if (processedDependencies && ![processed containsObject:collection]) {
                [processed addObject:collection];
            }
        }
    }];
    return processed;
}

- (void)importCollection:(NSString *)collection {
    // create the table
        [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
            [self createTable:collection config:self.config callback:^(BOOL created) {
                if (!created) {
                    NSLog(@"Collection %@ not created!", collection);
                }
            }];
        }];
    // import data
    NSArray *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentDir = [documentPaths objectAtIndex:0];
    FileReader *fileReader = [[FileReader alloc] initWithFilePath:[documentDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", collection]]];
    __block long long lineNumber = 0;
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
            
//            NSLog(@"\n%@", importableObject);
            [self insertObject:json inTable:collection config:self.config[collection]];
        } else {
            [importableObject appendString:line];
        }
        
        //        lineNumber++;
        //        NSLog(@"%lld, %@", lineNumber, line);
    }];
}

- (void)createTable:(NSString *)table config:(NSDictionary *)config callback:(void (^)(BOOL created))callback {
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
//    NSLog(@"\n\n%@\n\n", query);
    
    BOOL result = [self.db executeStatements:query];
    callback(result);
}

- (void)insertObject:(NSDictionary *)object inTable:(NSString *)table config:(NSDictionary *)config {
    NSArray *importantConfigFields = [config allKeys];
    NSMutableDictionary *mappedObject = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *extraFields = [[NSMutableDictionary alloc] init];
    NSMutableArray *manyToManyRecords = [NSMutableArray array];
    [importantConfigFields enumerateObjectsUsingBlock:^(NSString *key, NSUInteger idx, BOOL * _Nonnull stop) {
        if (object[key]) {
            [mappedObject setValue:object[key] forKey:key];
        } else if ([key containsString:@"_"] && [config[key] objectForKey:@"manyOn"]) {
            NSArray *components = [key componentsSeparatedByString:@"_"];
            //fist component should be a key of the object
            if (!object[components[0]]) {
                return;
            } else {
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
            }
        }
    }];
    [object enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL * _Nonnull stop) {
        // throw fields that are not in config in the extra fields
        if (![importantConfigFields containsObject:key]) {
            [extraFields setObject:value forKey:key];
        }
    }];
    NSError *error = nil;
    NSString *stringifiedExtraFields;
    NSData *dataExtraFields = [NSJSONSerialization dataWithJSONObject:extraFields options:NSJSONWritingPrettyPrinted error:&error];
    if (error) {
        NSLog(@"Error for extra fields - not JSON serializable for object %@ in table %@", object, table);
    } else {
        stringifiedExtraFields = [[NSString alloc] initWithData:dataExtraFields encoding:NSUTF8StringEncoding];
    }
    [mappedObject setObject:extraFields forKey:@"extra"];
    
    [self insertRecord:mappedObject inTable:table];
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

@end
