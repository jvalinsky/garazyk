#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSString *_Nullable PDSBlobAuditCIDStringFromRawBytes(NSData *_Nullable rawCID);
NSString *_Nullable PDSBlobAuditCursorFromRawBytes(NSData *_Nullable rawCID);
NSArray<NSString *> *PDSBlobAuditSortedStrings(NSSet<NSString *> *strings);
NSSet<NSString *> *PDSBlobAuditBlobReferenceCIDsFromJSONObject(id _Nullable json);

NS_ASSUME_NONNULL_END
