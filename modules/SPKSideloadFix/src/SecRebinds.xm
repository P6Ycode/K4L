#import <Security/Security.h>
#import <objc/runtime.h>

#import "Header.h"
#import "../fishhook/fishhook.h"

static OSStatus (*origSecItemAdd)(CFDictionaryRef attributes, CFTypeRef *result);
static OSStatus (*origSecItemCopyMatching)(CFDictionaryRef query, CFTypeRef *result);
static OSStatus (*origSecItemUpdate)(CFDictionaryRef query, CFDictionaryRef attributesToUpdate);
static OSStatus (*origSecItemDelete)(CFDictionaryRef query);

static NSString *SPKStringFromEntitlementValue(id value) {
	if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
		return value;
	}
	if ([value isKindOfClass:[NSArray class]]) {
		for (id entry in (NSArray *)value) {
			if ([entry isKindOfClass:[NSString class]] && [entry length] > 0) {
				return entry;
			}
		}
	}
	return nil;
}

static NSString *SPKAccessGroupFromEntitlements(void) {
	LSBundleProxy *bundleProxy = [objc_getClass("LSBundleProxy") bundleProxyForCurrentProcess];
	NSDictionary *entitlements = bundleProxy.entitlements;
	if (![entitlements isKindOfClass:[NSDictionary class]]) {
		return nil;
	}

	NSString *accessGroup = SPKStringFromEntitlementValue(entitlements[@"keychain-access-groups"]);
	if (accessGroup.length > 0) {
		return accessGroup;
	}

	NSString *applicationIdentifier = SPKStringFromEntitlementValue(entitlements[@"application-identifier"]);
	return applicationIdentifier.length > 0 ? applicationIdentifier : nil;
}

static NSString *SPKAccessGroupFromSentinelKeychainItem(void) {
	if (!origSecItemCopyMatching || !origSecItemAdd) {
		return nil;
	}

	NSDictionary *query = @{
		(__bridge NSString *)kSecClass: (__bridge NSString *)kSecClassGenericPassword,
		(__bridge NSString *)kSecAttrAccount: @"SPKSideloadFixGenericEntry",
		(__bridge NSString *)kSecAttrService: @"SPKSideloadFix",
		(__bridge NSString *)kSecReturnAttributes: (id)kCFBooleanTrue,
	};
	NSMutableDictionary *attributes = [query mutableCopy];
	attributes[(__bridge NSString *)kSecValueData] = [NSData data];

	CFTypeRef result = nil;
	OSStatus status = origSecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
	if (status == errSecItemNotFound) {
		status = origSecItemAdd((__bridge CFDictionaryRef)attributes, &result);
	}
	if (status != errSecSuccess || !result) {
		if (result) CFRelease(result);
		SPKSideloadLog(@"Unable to resolve keychain access group from sentinel item; status=%d", (int)status);
		return nil;
	}

	NSString *accessGroup = [(__bridge NSDictionary *)result objectForKey:(__bridge NSString *)kSecAttrAccessGroup];
	accessGroup = [accessGroup copy];
	CFRelease(result);
	return accessGroup.length > 0 ? accessGroup : nil;
}

static NSString *SPKSideloadAccessGroup(void) {
	static NSString *accessGroup;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSString *entitlementGroup = SPKAccessGroupFromEntitlements();
		BOOL resolvedFromEntitlements = entitlementGroup.length > 0;
		accessGroup = [entitlementGroup copy];
		if (accessGroup.length == 0) {
			accessGroup = [SPKAccessGroupFromSentinelKeychainItem() copy];
		}

		if (accessGroup.length > 0) {
			SPKSideloadLog(@"Resolved keychain access group from %@", resolvedFromEntitlements ? @"entitlements" : @"sentinel item");
		} else {
			SPKSideloadLog(@"No keychain access group resolved; keychain calls will pass through unchanged");
		}
	});
	return accessGroup;
}

static CFDictionaryRef SPKCopyDictionaryByInjectingAccessGroup(CFDictionaryRef dictionary, NSString **mode) {
	NSDictionary *source = (__bridge NSDictionary *)dictionary;
	if (![source isKindOfClass:[NSDictionary class]]) {
		if (mode) *mode = @"pass-through";
		return NULL;
	}

	id existingAccessGroup = source[(__bridge NSString *)kSecAttrAccessGroup];
	if (existingAccessGroup) {
		if (mode) *mode = @"preserved";
		return NULL;
	}

	NSString *accessGroup = SPKSideloadAccessGroup();
	if (accessGroup.length == 0) {
		if (mode) *mode = @"pass-through";
		return NULL;
	}

	NSMutableDictionary *mutableDictionary = [source mutableCopy];
	mutableDictionary[(__bridge NSString *)kSecAttrAccessGroup] = accessGroup;
	if (mode) *mode = @"injected";
	return (CFDictionaryRef)CFBridgingRetain(mutableDictionary);
}

static void SPKLogSecOperation(NSString *operation, OSStatus status, CFAbsoluteTime startedAt, NSString *mode) {
	static NSMutableDictionary<NSString *, NSNumber *> *lastLogTimes;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		lastLogTimes = [NSMutableDictionary dictionary];
	});

	CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
	NSString *key = [NSString stringWithFormat:@"%@:%@:%d", operation, mode ?: @"unknown", (int)status];
	@synchronized (lastLogTimes) {
		NSNumber *last = lastLogTimes[key];
		if (last && now - last.doubleValue < 2.0 && status == errSecSuccess) {
			return;
		}
		lastLogTimes[key] = @(now);
	}

	SPKSideloadLog(@"Keychain %@ status=%d duration=%.2fms mainThread=%@ accessGroup=%@",
		operation,
		(int)status,
		(now - startedAt) * 1000.0,
		[NSThread isMainThread] ? @"yes" : @"no",
		mode ?: @"unknown");
}

static OSStatus zxSecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
	CFAbsoluteTime startedAt = CFAbsoluteTimeGetCurrent();
	NSString *mode = nil;
	CFDictionaryRef patchedAttributes = SPKCopyDictionaryByInjectingAccessGroup(attributes, &mode);
	OSStatus status = origSecItemAdd(patchedAttributes ?: attributes, result);
	if (patchedAttributes) CFRelease(patchedAttributes);
	SPKLogSecOperation(@"SecItemAdd", status, startedAt, mode);
	return status;
}

static OSStatus zxSecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
	CFAbsoluteTime startedAt = CFAbsoluteTimeGetCurrent();
	NSString *mode = nil;
	CFDictionaryRef patchedQuery = SPKCopyDictionaryByInjectingAccessGroup(query, &mode);
	OSStatus status = origSecItemCopyMatching(patchedQuery ?: query, result);
	if (patchedQuery) CFRelease(patchedQuery);
	SPKLogSecOperation(@"SecItemCopyMatching", status, startedAt, mode);
	return status;
}

static OSStatus zxSecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
	CFAbsoluteTime startedAt = CFAbsoluteTimeGetCurrent();
	NSString *mode = nil;
	CFDictionaryRef patchedQuery = SPKCopyDictionaryByInjectingAccessGroup(query, &mode);
	OSStatus status = origSecItemUpdate(patchedQuery ?: query, attributesToUpdate);
	if (patchedQuery) CFRelease(patchedQuery);
	SPKLogSecOperation(@"SecItemUpdate", status, startedAt, mode);
	return status;
}

static OSStatus zxSecItemDelete(CFDictionaryRef query) {
	CFAbsoluteTime startedAt = CFAbsoluteTimeGetCurrent();
	NSString *mode = nil;
	CFDictionaryRef patchedQuery = SPKCopyDictionaryByInjectingAccessGroup(query, &mode);
	OSStatus status = origSecItemDelete(patchedQuery ?: query);
	if (patchedQuery) CFRelease(patchedQuery);
	SPKLogSecOperation(@"SecItemDelete", status, startedAt, mode);
	return status;
}

void rebindSecFuncs() {
	struct rebinding rebinds[4] = {
		{"SecItemAdd", (void *)zxSecItemAdd, (void **)&origSecItemAdd},
		{"SecItemCopyMatching", (void *)zxSecItemCopyMatching, (void **)&origSecItemCopyMatching},
		{"SecItemUpdate", (void *)zxSecItemUpdate, (void **)&origSecItemUpdate},
		{"SecItemDelete", (void *)zxSecItemDelete, (void **)&origSecItemDelete}
	};
	SPKSideloadLog(@"rebind_symbols result=%d", rebind_symbols(rebinds, 4));
}
