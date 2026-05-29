/**
 * Flowey — macOS Speech Recognition helper
 *
 * Thin C API over SFSpeechRecognizer so Rust can call into the Speech
 * framework without needing objc2 bindings.  Compiled with -fobjc-arc via
 * the `cc` build crate so all ObjC memory management is automatic.
 */

#import <Speech/Speech.h>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <stdlib.h>
#include <unistd.h>

// ── Accessibility (needed for CGEventTap / global hotkeys) ────

/// Check Accessibility trust and return the result WITHOUT showing the OS prompt.
/// Returns 1 if trusted, 0 otherwise.
///
/// We deliberately never call AXIsProcessTrustedWithOptions(kAXTrustedCheckOptionPrompt:YES)
/// here.  Showing the OS prompt at startup is the wrong UX because:
///   • macOS re-evaluates trust against the code signature on every launch.
///   • Debug/development builds are re-signed on every `cargo build`, so the
///     prompt fires every launch even when the user has already granted access
///     to a previous binary.
///   • The settings UI already shows a callout banner when trust is absent.
///
/// Users grant access through the in-app banner or through the NSAlert that
/// appears the first time keystroke injection is attempted (flowey_type_text).
int flowey_request_accessibility(void) {
    return AXIsProcessTrusted() ? 1 : 0;
}

/// Returns 1 if Accessibility is currently granted, 0 otherwise.
int flowey_is_accessibility_trusted(void) {
    return AXIsProcessTrusted() ? 1 : 0;
}

// ── Authorization ─────────────────────────────────────────────

/// Fire-and-forget: trigger the system authorization dialog if needed.
/// Safe to call multiple times; the OS ignores subsequent calls once a
/// decision has been recorded.
void flowey_request_speech_auth(void) {
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus s) {
        (void)s; // caller checks status separately; we just trigger the dialog
    }];
}

/// Returns 1 if the user has granted speech recognition access, 0 otherwise.
int flowey_speech_is_authorized(void) {
    return [SFSpeechRecognizer authorizationStatus]
        == SFSpeechRecognizerAuthorizationStatusAuthorized ? 1 : 0;
}

// ── Transcription ─────────────────────────────────────────────

/**
 * Transcribe a WAV file at `wav_path` using SFSpeechRecognizer.
 *
 * Returns a malloc-allocated UTF-8 C string on success (caller must call
 * flowey_free_str on it).  Returns NULL if recognition fails or is unavailable.
 *
 * Blocks the calling thread until recognition completes or the 60 s timeout
 * expires.  Call only from a background thread (the pipeline thread), never
 * from the main thread, to avoid blocking the UI / run loop.
 */
char* flowey_transcribe(const char* wav_path) {
    @autoreleasepool {
        NSURL* url = [NSURL fileURLWithPath:
            [NSString stringWithUTF8String:wav_path]];

        // Use the device locale so on-device recognition is selected when
        // available.  Don't gate on isAvailable — it can be NO on first use
        // while the recognizer initialises; the task will fail naturally.
        SFSpeechRecognizer* rec = [[SFSpeechRecognizer alloc]
            initWithLocale:[NSLocale currentLocale]];
        if (!rec) { return NULL; }

        SFSpeechURLRecognitionRequest* req =
            [[SFSpeechURLRecognitionRequest alloc] initWithURL:url];
        if (!req) { return NULL; }
        req.shouldReportPartialResults = NO;

        __block char*          result = NULL;
        dispatch_semaphore_t   sem    = dispatch_semaphore_create(0);

        SFSpeechRecognitionTask* task =
            [rec recognitionTaskWithRequest:req
                              resultHandler:^(SFSpeechRecognitionResult* r,
                                              NSError*                   err) {
                // Signal on *either* a final result OR any error so the
                // semaphore never hangs.  (If err != nil and r != nil the
                // old code never signalled, causing a silent 60-second stall.)
                if (r.isFinal || err != nil) {
                    if (r != nil && r.bestTranscription.formattedString.length > 0) {
                        result = strdup(r.bestTranscription.formattedString.UTF8String);
                    }
                    dispatch_semaphore_signal(sem);
                }
            }];

        // Wait up to 60 s (file-based recognition is usually < 5 s).
        dispatch_time_t deadline =
            dispatch_time(DISPATCH_TIME_NOW, 60LL * NSEC_PER_SEC);

        if (dispatch_semaphore_wait(sem, deadline) != 0) {
            // Timed out — cancel the task to release resources.
            [task cancel];
        }

        return result; // NULL if nothing was produced
    }
}

/// Free a string returned by flowey_transcribe.
void flowey_free_str(char* s) {
    free(s);
}

// ── Focus tracking ────────────────────────────────────────────

/// The app that was frontmost when recording started.
/// We re-activate it before pasting so the text lands in the right window
/// even if the overlay briefly stole keyboard focus.
static NSRunningApplication* sCapturedApp = nil;

static void flowey_capture_focus_on_main(void);
static int flowey_type_text_on_main(const char* utf8_text);
static int flowey_insert_with_accessibility(NSString* str);
static int flowey_type_string(NSString* str);

/// Call this just before recording starts.  Saves whatever app currently has
/// focus so we can restore it after transcription.
void flowey_capture_focus(void) {
    if ([NSThread isMainThread]) {
        flowey_capture_focus_on_main();
        return;
    }

    dispatch_sync(dispatch_get_main_queue(), ^{
        flowey_capture_focus_on_main();
    });
}

static void flowey_capture_focus_on_main(void) {
    @autoreleasepool {
        sCapturedApp = [[NSWorkspace sharedWorkspace] frontmostApplication];
    }
}

// ── Keystroke injection ───────────────────────────────────────

// Guard so we only nag the user once per session, not on every dictation.
static volatile BOOL sAccessibilityAlertShown = NO;

/**
 * Deliver `utf8_text` into the currently-focused window by:
 *   1. Checking Accessibility permission; prompt + alert if missing.
 *   2. Writing the text to NSPasteboard.
 *   3. Posting a Cmd+V key-down/up pair via CGEventPost.
 *
 * This is the same technique used by WhisperFlow and similar dictation apps.
 * It handles arbitrary Unicode text reliably and only requires two synthetic
 * key events instead of one per character.
 *
 * Requires Accessibility permission (System Settings → Privacy → Accessibility).
 * Returns 1 on success, 0 on failure (including permission denied).
 *
 * Virtual key code for V: 0x09 (stable ABI, part of IOKit HID usage tables).
 */
int flowey_type_text(const char* utf8_text) {
    if (!utf8_text) return 0;

    if ([NSThread isMainThread]) {
        return flowey_type_text_on_main(utf8_text);
    }

    __block int result = 0;
    dispatch_sync(dispatch_get_main_queue(), ^{
        result = flowey_type_text_on_main(utf8_text);
    });
    return result;
}

static int flowey_type_text_on_main(const char* utf8_text) {
    @autoreleasepool {
        if (!utf8_text) return 0;

        // ── 0. Accessibility check ────────────────────────────
        // NOTE: We do NOT call AXIsProcessTrustedWithOptions(prompt=YES) here.
        // The system permission dialog is shown exactly once at app startup
        // (flowey_request_accessibility).  Calling it here would re-prompt on
        // every recording when running unsigned debug builds, because macOS
        // re-evaluates trust after each recompile.
        if (!AXIsProcessTrusted()) {
            // Show our own in-app alert once per session — no system dialog.
            if (!sAccessibilityAlertShown) {
                sAccessibilityAlertShown = YES;
                dispatch_async(dispatch_get_main_queue(), ^{
                    @autoreleasepool {
                        NSAlert* alert = [[NSAlert alloc] init];
                        alert.messageText     = @"Accessibility Permission Required";
                        alert.informativeText =
                            @"Flowey needs Accessibility access to paste transcribed text into other apps.\n\n"
                            @"Open System Settings → Privacy & Security → Accessibility, then:\n\n"
                            @"• If Flowey is NOT listed → click + and add it.\n"
                            @"• If Flowey IS listed with the toggle ON but this alert still appears → "
                            @"click − to remove it, then + to re-add it. "
                            @"macOS clears Accessibility trust whenever the app binary changes "
                            @"(e.g. after a rebuild), so the existing entry becomes stale.\n\n"
                            @"Restart Flowey after making changes.\n\n"
                            @"Until then, transcriptions are copied to your clipboard — "
                            @"paste manually with ⌘V.";
                        alert.alertStyle = NSAlertStyleWarning;
                        [alert addButtonWithTitle:@"Open Accessibility Settings"];
                        [alert addButtonWithTitle:@"Later"];
                        NSModalResponse r = [alert runModal];
                        if (r == NSAlertFirstButtonReturn) {
                            [[NSWorkspace sharedWorkspace] openURL:
                                [NSURL URLWithString:
                                    @"x-apple.systempreferences:"
                                    @"com.apple.preference.security?Privacy_Accessibility"]];
                        }
                    }
                });
            }
            return 0;
        }

        // ── 1. Re-activate the app that had focus before recording ──
        // This ensures the Cmd+V goes to the right window even if the
        // floating overlay stole keyboard focus while recording.
        if (sCapturedApp && ![sCapturedApp isTerminated]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            // activateWithOptions: is deprecated on macOS 14+ but still works.
            // Passing 0 activates the app without side effects.
            [sCapturedApp activateWithOptions:NSApplicationActivateIgnoringOtherApps];
#pragma clang diagnostic pop
            usleep(150000); // let activation settle before posting Cmd+V
            sCapturedApp = nil;
        }

        // ── 2. Put text on the pasteboard ────────────────────
        NSString* str = [NSString stringWithUTF8String:utf8_text];
        if (!str || str.length == 0) return 0;

        NSPasteboard* pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        BOOL ok = [pb setString:str forType:NSPasteboardTypeString];
        if (!ok) return 0;

        // ── 3. Insert through Accessibility when possible ────
        // This avoids depending on target apps accepting synthetic keyboard
        // events. It works for standard text fields/editors that expose a
        // writable focused AX element.
        if (flowey_insert_with_accessibility(str)) return 1;

        // ── 4. Type the text directly ────────────────────────
        // A synthetic Cmd+V is ignored by some apps and some macro setups.
        // Unicode keyboard events are the last active fallback before the
        // user-visible clipboard fallback in Rust.
        return flowey_type_string(str);
    }
}

static int flowey_insert_with_accessibility(NSString* str) {
    if (!str || str.length == 0) return 0;

    AXUIElementRef system = AXUIElementCreateSystemWide();
    if (!system) return 0;

    AXUIElementRef focused = NULL;
    AXError err = AXUIElementCopyAttributeValue(
        system,
        kAXFocusedUIElementAttribute,
        (CFTypeRef*)&focused
    );
    CFRelease(system);

    if (err != kAXErrorSuccess || !focused) return 0;

    err = AXUIElementSetAttributeValue(
        focused,
        kAXSelectedTextAttribute,
        (__bridge CFTypeRef)str
    );
    if (err == kAXErrorSuccess) {
        CFRelease(focused);
        return 1;
    }

    CFTypeRef value_ref = NULL;
    CFTypeRef range_ref = NULL;

    err = AXUIElementCopyAttributeValue(focused, kAXValueAttribute, &value_ref);
    if (err != kAXErrorSuccess || !value_ref || CFGetTypeID(value_ref) != CFStringGetTypeID()) {
        if (value_ref) CFRelease(value_ref);
        CFRelease(focused);
        return 0;
    }

    err = AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute, &range_ref);
    if (err != kAXErrorSuccess || !range_ref || CFGetTypeID(range_ref) != AXValueGetTypeID()) {
        if (range_ref) CFRelease(range_ref);
        CFRelease(value_ref);
        CFRelease(focused);
        return 0;
    }

    CFRange selected_range;
    if (!AXValueGetValue((AXValueRef)range_ref, kAXValueCFRangeType, &selected_range)) {
        CFRelease(range_ref);
        CFRelease(value_ref);
        CFRelease(focused);
        return 0;
    }

    NSString* value = (__bridge NSString*)value_ref;
    NSUInteger value_len = value.length;
    if (selected_range.location < 0 || (NSUInteger)selected_range.location > value_len) {
        CFRelease(range_ref);
        CFRelease(value_ref);
        CFRelease(focused);
        return 0;
    }

    NSUInteger location = (NSUInteger)selected_range.location;
    NSUInteger length = MAX((CFIndex)0, selected_range.length);
    if (location + length > value_len) {
        length = value_len - location;
    }

    NSMutableString* next_value = [value mutableCopy];
    [next_value replaceCharactersInRange:NSMakeRange(location, length) withString:str];

    err = AXUIElementSetAttributeValue(
        focused,
        kAXValueAttribute,
        (__bridge CFTypeRef)next_value
    );

    if (err == kAXErrorSuccess) {
        CFRange next_range = CFRangeMake((CFIndex)(location + str.length), 0);
        AXValueRef next_range_ref = AXValueCreate(kAXValueCFRangeType, &next_range);
        if (next_range_ref) {
            AXUIElementSetAttributeValue(
                focused,
                kAXSelectedTextRangeAttribute,
                next_range_ref
            );
            CFRelease(next_range_ref);
        }
    }

    CFRelease(range_ref);
    CFRelease(value_ref);
    CFRelease(focused);

    return err == kAXErrorSuccess ? 1 : 0;
}

static int flowey_type_string(NSString* str) {
    if (!str || str.length == 0) return 0;

    CGEventSourceRef src =
        CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);
    if (!src) return 0;

    NSUInteger len = str.length;
    NSUInteger offset = 0;
    int ok = 1;

    while (offset < len) {
        NSUInteger chunk_len = MIN((NSUInteger)20, len - offset);
        unichar chars[20];
        [str getCharacters:chars range:NSMakeRange(offset, chunk_len)];

        CGEventRef keyDown = CGEventCreateKeyboardEvent(src, 0, true);
        CGEventRef keyUp = CGEventCreateKeyboardEvent(src, 0, false);
        if (!keyDown || !keyUp) {
            ok = 0;
            if (keyDown) CFRelease(keyDown);
            if (keyUp) CFRelease(keyUp);
            break;
        }

        CGEventKeyboardSetUnicodeString(keyDown, chunk_len, chars);
        CGEventKeyboardSetUnicodeString(keyUp, 0, NULL);
        CGEventPost(kCGSessionEventTap, keyDown);
        CGEventPost(kCGSessionEventTap, keyUp);

        CFRelease(keyDown);
        CFRelease(keyUp);

        offset += chunk_len;
        usleep(5000);
    }

    CFRelease(src);
    return ok;
}
