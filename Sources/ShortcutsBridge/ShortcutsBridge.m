#import "ShortcutsBridge.h"

#import <AppKit/AppKit.h>
#import <ScriptingBridge/ScriptingBridge.h>

// Hand-declared bindings for Shortcuts Events, covering only the members this server
// sends.
//
// `sdef "/System/Library/CoreServices/Shortcuts Events.app" | sdp -fh` generates a
// 125-line header; declaring the handful of members actually used is smaller and
// auditable. Every selector here was checked against that generated header — confirm
// before adding one:
//
//     sdef "/System/Library/CoreServices/Shortcuts Events.app" | sdp -fh --basename S
//
// Scripting Bridge camel-cases dictionary names, so `accepts input` becomes
// `acceptsInput` and `action count` becomes `actionCount`. `id` is a method rather than a
// property because the dictionary spells the code `ID  `.
//
// Two members of the `shortcut` class are deliberately absent. `icon` is a TIFF image and
// image bytes have no business crossing this boundary; `color` is decoration for a UI
// nothing here draws. Neither is declared, which makes both unreachable from this process
// — the narrow protocol is the safeguard. For the same reason nothing is declared "in case
// it is useful later": every member is one this server sends.
//
// The `organize` access group is not touched either. `folder` is `rw` in the dictionary
// and the standard suite offers `delete`, `duplicate` and `move`; none is declared here,
// so this process cannot rearrange or destroy anything in the library even if asked to.

@protocol ShortcutsFolder <NSObject>
@property (copy) NSString *name;
- (NSString *)id;
@end

@protocol Shortcut <NSObject>
@property (copy, readonly) NSString *name;
@property (copy, readonly) NSString *subtitle;
- (NSString *)id;
@property (copy) id<ShortcutsFolder> folder;
@property (readonly) BOOL acceptsInput;
@property (readonly) NSInteger actionCount;
- (id)runWithInput:(nullable id)withInput;
@end

@protocol ShortcutsApplication <NSObject>
@property (readonly) SBElementArray<id<Shortcut>> *shortcuts;
@end

NSString *const ShortcutsBridgeErrorDomain = @"codes.eneko.apple-shortcuts-mcp";
static NSString *const ShortcutsEventsBundleIdentifier = @"com.apple.shortcuts.events";

#pragma mark - Event failure capture

/// Captures the failure of an Apple event instead of letting Scripting Bridge swallow it.
///
/// Without a delegate, a failed event returns nil and logs; a denied automation grant
/// would then be indistinguishable from an empty Shortcuts library, and a shortcut that
/// hung until the timeout would look like one that simply returned nothing. Both are the
/// kind of silent failure this project refuses to ship.
@interface ShortcutsEventObserver : NSObject <SBApplicationDelegate>
@property (nonatomic, strong, nullable) NSError *lastError;
@end

@implementation ShortcutsEventObserver

- (id)eventDidFail:(const AppleEvent *)event withError:(NSError *)error {
    self.lastError = error;
    return nil;
}

@end

@implementation ShortcutsBridge

#pragma mark - Plumbing

+ (BOOL)isShortcutsEventsInstalled {
    return [NSWorkspace.sharedWorkspace
               URLForApplicationWithBundleIdentifier:ShortcutsEventsBundleIdentifier] != nil;
}

+ (NSError *)errorWithCode:(ShortcutsBridgeError)code message:(NSString *)message {
    return [NSError errorWithDomain:ShortcutsBridgeErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

/// Translates an OSStatus carried by a failed Apple event into one of this bridge's cases.
///
/// The three that matter are told apart by number because their remedies differ
/// completely: a denied grant is fixed in System Settings, a timeout means the shortcut is
/// probably still running, and anything else is a fault in the shortcut itself.
+ (NSError *)translatedError:(NSError *)error {
    switch (error.code) {
        case errAEEventNotPermitted:
        case userCanceledErr:
            return [self errorWithCode:ShortcutsBridgeErrorNotPermitted
                               message:@"macOS refused this process permission to control "
                                        "Shortcuts Events."];
        case errAETimeout:
            return [self errorWithCode:ShortcutsBridgeErrorTimedOut
                               message:@"Shortcuts Events did not answer before the timeout."];
        case procNotFound:
            return [self errorWithCode:ShortcutsBridgeErrorNotReachable
                               message:@"Shortcuts Events could not be reached."];
        default:
            return [self errorWithCode:ShortcutsBridgeErrorRunFailed
                               message:error.localizedDescription
                                           ?: @"Shortcuts Events reported a failure."];
    }
}

/// The application object, or nil with `error` set.
///
/// Casting to the protocol is a compile-time annotation in Objective-C: no runtime check,
/// no metadata symbol, and so none of the trouble the same line causes in Swift.
///
/// Unlike the sibling mail server, this one does not refuse to act when the target is not
/// already running. Shortcuts Events is a faceless helper — it has no windows, no Dock tile
/// and no state a person could lose — and its own dictionary names launching it as the way
/// to run a shortcut without opening the Shortcuts app. Refusing to start it would mean
/// refusing to work at all.
+ (nullable SBApplication<ShortcutsApplication> *)
    applicationObservedBy:(ShortcutsEventObserver *)observer
                    error:(NSError **)error {
    if (!self.isShortcutsEventsInstalled) {
        if (error) {
            *error = [self errorWithCode:ShortcutsBridgeErrorNotInstalled
                                 message:@"Shortcuts Events is not installed on this Mac."];
        }
        return nil;
    }
    SBApplication *application =
        [SBApplication applicationWithBundleIdentifier:ShortcutsEventsBundleIdentifier];
    if (!application) {
        if (error) {
            *error = [self errorWithCode:ShortcutsBridgeErrorNotReachable
                                 message:@"Shortcuts Events could not be reached."];
        }
        return nil;
    }
    // `delegate` is an assign property, so the observer has to outlive every event sent
    // through this object. Each caller keeps it in scope and clears it before returning.
    application.delegate = observer;
    return (SBApplication<ShortcutsApplication> *)application;
}

/// Reduces the `any` a shortcut returns to text, or nil when it has no textual meaning.
///
/// Reduction only — no truncation and no labelling. Those are policy and live in Swift
/// where the tests can reach them; nil here means "there was a value and it is not text",
/// which the caller reports rather than hides.
+ (nullable NSString *)textFrom:(nullable id)value {
    // An SBObject is a specifier the application has not evaluated yet. Resolving it here,
    // once, before the type ladder is what keeps the array branch below from recursing
    // without a bound.
    if ([value isKindOfClass:SBObject.class]) value = [(SBObject *)value get];

    if (!value || value == NSNull.null) return nil;
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSAttributedString.class]) return [value string];
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    if ([value isKindOfClass:NSURL.class]) return [value absoluteString];
    if ([value isKindOfClass:NSDate.class]) {
        NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
        formatter.timeZone = NSTimeZone.localTimeZone;
        return [formatter stringFromDate:value];
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        for (id element in value) {
            NSString *line = [self textFrom:element];
            if (line) [lines addObject:line];
        }
        return lines.count > 0 ? [lines componentsJoinedByString:@"\n"] : nil;
    }
    if ([value isKindOfClass:NSDictionary.class] &&
        [NSJSONSerialization isValidJSONObject:value]) {
        NSData *json = [NSJSONSerialization
            dataWithJSONObject:value
                       options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                         error:NULL];
        return json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
    }
    return nil;
}

#pragma mark - Reads

+ (nullable NSArray<NSDictionary<NSString *, id> *> *)shortcutsWithError:(NSError **)error {
    ShortcutsEventObserver *observer = [[ShortcutsEventObserver alloc] init];
    SBApplication<ShortcutsApplication> *application = [self applicationObservedBy:observer
                                                                            error:error];
    if (!application) return nil;

    NSMutableArray<NSDictionary<NSString *, id> *> *results = [NSMutableArray array];
    for (id<Shortcut> shortcut in application.shortcuts) {
        NSString *name = shortcut.name;
        NSString *identifier = [shortcut id];
        // A shortcut with no identifier cannot be run later, so listing it would only
        // offer the caller something that fails on the next call.
        if (name.length == 0 || identifier.length == 0) continue;

        NSMutableDictionary<NSString *, id> *entry = [@{
            @"name": name,
            @"id": identifier,
            @"subtitle": shortcut.subtitle ?: @"",
            @"acceptsInput": @(shortcut.acceptsInput),
            @"actionCount": @(shortcut.actionCount),
        } mutableCopy];
        // Absent rather than empty for a shortcut at the top level: "no folder" and "a
        // folder whose name is blank" are different facts.
        NSString *folder = shortcut.folder.name;
        if (folder.length > 0) entry[@"folder"] = folder;
        [results addObject:entry];
    }

    application.delegate = nil;
    if (observer.lastError) {
        if (error) *error = [self translatedError:observer.lastError];
        return nil;
    }
    return results;
}

#pragma mark - Run

+ (nullable NSDictionary<NSString *, id> *)runShortcutWithIdentifier:(NSString *)identifier
                                                               input:(nullable NSString *)input
                                                      timeoutSeconds:(NSInteger)timeoutSeconds
                                                               error:(NSError **)error {
    ShortcutsEventObserver *observer = [[ShortcutsEventObserver alloc] init];
    SBApplication<ShortcutsApplication> *application = [self applicationObservedBy:observer
                                                                            error:error];
    if (!application) return nil;

    // Ticks, at 60 to the second. Without a bound the send mode waits forever, and a
    // shortcut stuck on a confirmation dialog would take the whole server down with it.
    application.timeout = timeoutSeconds * 60;

    id<Shortcut> shortcut = [application.shortcuts objectWithID:identifier];
    // Reading a property is what forces the specifier to resolve; `objectWithID:` alone
    // only builds one, and never fails.
    if (shortcut.name.length == 0) {
        application.delegate = nil;
        if (error) {
            *error = observer.lastError
                         ? [self translatedError:observer.lastError]
                         : [self errorWithCode:ShortcutsBridgeErrorShortcutNotFound
                                       message:@"The library no longer holds a shortcut with "
                                                "that identifier."];
        }
        return nil;
    }

    // The shortcut is named by a typed object specifier and the input by a typed
    // parameter. There is no script source to splice either into, which is the injection
    // guarantee shelling out to /usr/bin/shortcuts would give up.
    id output = [shortcut runWithInput:input];

    application.delegate = nil;
    if (observer.lastError) {
        if (error) *error = [self translatedError:observer.lastError];
        return nil;
    }

    NSString *text = [self textFrom:output];
    return @{
        // Told apart so a shortcut that returned nothing reads differently from one that
        // returned something this server cannot render.
        @"hasResult": @(output != nil && output != NSNull.null),
        @"result": text ?: @"",
        @"resultIsText": @(text != nil),
    };
}

@end
