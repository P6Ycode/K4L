#import <objc/runtime.h>

#import "Header.h"

BOOL createDirectoryIfNotExists(NSString *path) {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	if ([fileManager fileExistsAtPath:path]) {
		return YES;
	}

	NSError *error = nil;
	[fileManager createDirectoryAtPath:path
		   withIntermediateDirectories:YES
							attributes:nil
								 error:&error];

	if (error) {
		SCISideloadLog(@"Failed to create directory at path=%@ error=%@", path, error);
		return NO;
	}

	SCISideloadLog(@"Created directory at path=%@", path);
	return YES;
}

NSURL *getAppGroupPathIfExists() {
	static NSURL *cachedAppGroupPath = nil;
	if (cachedAppGroupPath) return cachedAppGroupPath;

	LSBundleProxy *bundleProxy = [objc_getClass("LSBundleProxy") bundleProxyForCurrentProcess];
	if (!bundleProxy) {
		SCISideloadLog(@"Failed to retrieve LSBundleProxy for current process");
		return nil;
	}

	NSDictionary *entitlements = bundleProxy.entitlements;
	if (!entitlements || ![entitlements isKindOfClass:[NSDictionary class]]) {
		SCISideloadLog(@"Failed to retrieve entitlements");
		return nil;
	}

	NSArray *appGroups = entitlements[@"com.apple.security.application-groups"];
	if (!appGroups) {
		SCISideloadLog(@"No app groups found in entitlements");
		return nil;
	}

	if (appGroups.count == 0) {
		SCISideloadLog(@"App group entitlement exists but contains no groups");
		return nil;
	}

	NSString *appGroupName = [appGroups firstObject];

	NSDictionary *appGroupsPaths = bundleProxy.groupContainerURLs;
	if (!appGroupsPaths || ![appGroupsPaths isKindOfClass:[NSDictionary class]]) {
		SCISideloadLog(@"Failed to retrieve group container URLs");
		return nil;
	}

	NSURL *ourAppGroupURL = appGroupsPaths[appGroupName];
	if (ourAppGroupURL) {
		cachedAppGroupPath = ourAppGroupURL;
		SCISideloadLog(@"Resolved app group path for group=%@", appGroupName);
	} else {
		SCISideloadLog(@"No path found for app group=%@", appGroupName);
	}
	
	return cachedAppGroupPath;
}
