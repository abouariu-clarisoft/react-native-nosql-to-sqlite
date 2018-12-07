#import "NoSQLUtils.h"

@implementation NoSQLUtils

/**
 Counts the number of objects in a collection
 @param collection The name of the collection
 @return The number of objects in the collection
 */
+ (NSInteger)countNumberOfObjectsInCollection:(NSString *)collection {
    @autoreleasepool {
        // Used to read the collection line by line
        FileReader *fileReader = [NoSQLUtils fileReaderForCollection:collection];
        
        // All objects in the collection start with "  {" and end with "  }[,]".
        __block NSInteger count = 0;
        [fileReader enumerateLinesUsingBlock:^(NSString * _Nonnull line, BOOL * _Nonnull stop) {
            // Wrap everything into an autorelease pool for memory management
            if ([line hasPrefix:@"  }"]) {
                count++;
            }
        }];
        return count;
    }
}

/**
 Returns a file reader for a specific collection.
 @param collection The name of the collection
 @return A FileReader object linked to the collection
 */
+ (FileReader *)fileReaderForCollection:(NSString *)collection {
    NSArray *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentDir = [documentPaths objectAtIndex:0];
    FileReader *fileReader = [[FileReader alloc] initWithFilePath:[documentDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", collection]]];
    return fileReader;
}

@end
