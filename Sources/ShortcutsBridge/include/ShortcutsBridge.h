#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ShortcutsBridgeErrorDomain;

/// Typed because Swift imports an `NSError **` method as `throws`, which would otherwise
/// flatten "that shortcut is gone" — an ordinary outcome, since the owner can rename or
/// delete one at any moment — into the same channel as a real failure.
typedef NS_ERROR_ENUM(ShortcutsBridgeErrorDomain, ShortcutsBridgeError){
    ShortcutsBridgeErrorNotInstalled = 1,
    ShortcutsBridgeErrorNotReachable,
    ShortcutsBridgeErrorNotPermitted,
    ShortcutsBridgeErrorShortcutNotFound,
    /// The shortcut itself stopped with an error, possibly after some of its actions ran.
    ShortcutsBridgeErrorRunFailed,
    ShortcutsBridgeErrorTimedOut,
    /// Any other failed event: nothing says the shortcut was at fault.
    ShortcutsBridgeErrorEventFailed,
    /// Reading the library used up its time budget before every shortcut was read.
    ShortcutsBridgeErrorScanStopped,
};

/// Everything this project sends to Shortcuts, in Objective-C.
///
/// Objective-C rather than Swift on purpose, and not for taste. Scripting Bridge creates
/// its classes at runtime, so their metadata symbols do not exist at link time; a Swift
/// metatype cast against one aborts the process, a limitation open since 2016
/// (swiftlang/swift#43407). In Objective-C a cast to a protocol is a compile-time
/// annotation, nothing is looked up, and no `unsafeBitCast` is needed anywhere. The
/// alternative — driving Shortcuts through `NSAppleScript` — is the one thing Apple's own
/// guide tells you not to do: "You should not use NSAppleScript to execute a script merely
/// to result in sending an Apple event."
///
/// The target is **Shortcuts Events**, the faceless helper at
/// `/System/Library/CoreServices/Shortcuts Events.app`, not Shortcuts.app. Its dictionary
/// says why: "To run a shortcut in the background, without opening the Shortcuts app, tell
/// 'Shortcuts Events' instead of 'Shortcuts'." Nothing here ever brings a window to the
/// front.
///
/// Shelling out to `/usr/bin/shortcuts` would reach the same shortcuts, and is rejected on
/// purpose: it means building a command line out of the caller's strings and reading a
/// result back out of a pipe. Here the shortcut is addressed by its identifier as a typed
/// Apple event parameter, and there is no shell, no argument vector and no text to quote.
///
/// Everything crosses back to Swift as Foundation types, so no Scripting Bridge object
/// ever escapes this file. Policy — which shortcuts are in scope, how a name resolves,
/// what a result may contain, how it is formatted — stays in Swift, where the tests can
/// reach it.
@interface ShortcutsBridge : NSObject

/// Turns the error of a failed Apple event into one of this bridge's cases.
///
/// Public so the mapping can be tested with a synthetic `NSError`; no event is sent.
+ (NSError *)translatedError:(NSError *)error;

/// Whether the Shortcuts Events helper exists on this Mac.
///
/// It ships with macOS, so a `NO` here means the install is unusual rather than that the
/// owner has to fix something.
@property (class, readonly) BOOL isShortcutsEventsInstalled;

/// Every shortcut in the library, as
/// `{name, id, subtitle, folder, acceptsInput, actionCount}`.
///
/// `folder` is absent for a shortcut that sits at the top level. The whole library is
/// read, because there is no query language to push a filter into: the dictionary offers
/// elements and properties, nothing else. Filtering happens in Swift.
///
/// `timeBudgetSeconds` bounds both one event and the walk as a whole. A library that is
/// not read in full within it fails with `ShortcutsBridgeErrorScanStopped` rather than
/// returning the shortcuts read so far: resolving a name against a partial library could
/// miss a second shortcut of the same name and run the wrong one.
+ (nullable NSArray<NSDictionary<NSString *, id> *> *)
    shortcutsWithTimeBudget:(NSInteger)timeBudgetSeconds
                      error:(NSError **)error;

/// Runs one shortcut by identifier and returns `{result, hasResult}`.
///
/// Addressed by identifier rather than by name because a name can be changed by the owner
/// between the moment the caller read it and the moment this runs, and two shortcuts may
/// carry the same name. Resolution from a name happens above this bridge, against a list
/// this same process fetched.
///
/// `input` is passed as the `with input` parameter when non-nil. It is text: the parameter
/// accepts `any`, but a file or an image cannot be built here from what a tool call can
/// carry.
///
/// `timeoutSeconds` bounds the wait. A shortcut can block forever — on a confirmation
/// dialog, on a network call, on a device that is not home — and the default Apple event
/// timeout would take the whole server down with it, silently, mid-session.
///
/// Irreversible in the general case: this cannot know what the shortcut does.
+ (nullable NSDictionary<NSString *, id> *)runShortcutWithIdentifier:(NSString *)identifier
                                                               input:(nullable NSString *)input
                                                      timeoutSeconds:(NSInteger)timeoutSeconds
                                                               error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
