#import <Foundation/Foundation.h>
#import "FileReader.h"

NS_ASSUME_NONNULL_BEGIN

@interface NoSQLUtils : NSObject

+ (NSInteger)countNumberOfObjectsInCollection:(NSString *)collection;
+ (FileReader *)fileReaderForCollection:(NSString *)collection;

@end

NS_ASSUME_NONNULL_END
