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

// ── Accessibility (needed for CGEventTap / global hotkeys) ────

/// Check Accessibility trust.  If not yet granted, show the system prompt
/// (which opens System Settings → Accessibility) exactly once.
/// Returns 1 if already trusted (no dialog), 0 if the dialog was shown.
int flowey_request_accessibility(void) {
    // Fast path: already trusted — never show a dialog.
    if (AXIsProcessTrusted()) return 1;

    // Not trusted yet: show the OS prompt once so the user can grant access.
    NSDictionary* opts = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts);
    return 0;
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

/// Call this just before recording starts.  Saves whatever app currently has
/// focus so we can restore it after transcription.
void flowey_capture_focus(void) {
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
                            @"Flowey needs Accessibility access to paste transcribed text "
                            @"into other apps.\n\n"
                            @"1. Open System Settings → Privacy & Security → Accessibility\n"
                            @"2. Enable the toggle next to Flowey\n"
                            @"3. Restart Flowey\n\n"
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
            usleep(80000); // 80 ms — let activation settle
            sCapturedApp = nil;
        }

        // ── 2. Put text on the pasteboard ────────────────────
        NSString* str = [NSString stringWithUTF8String:utf8_text];
        if (!str || str.length == 0) return 0;

        NSPasteboard* pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        BOOL ok = [pb setString:str forType:NSPasteboardTypeString];
        if (!ok) return 0;

        // Brief pause so the pasteboard write propagates before the paste event.
        usleep(30000); // 30 ms

        // ── 3. Simulate Cmd+V ────────────────────────────────
        // Use kCGEventSourceStateHIDSystemState so the events look like real
        // hardware input and are accepted by sandboxed apps.
        CGEventSourceRef src =
            CGEventSourceCreate(kCGEventSourceStateHIDSystemState);

        // kVK_ANSI_V = 0x09
        CGEventRef keyDown = CGEventCreateKeyboardEvent(src, (CGKeyCode)0x09, true);
        CGEventSetFlags(keyDown, kCGEventFlagMaskCommand);
        CGEventPost(kCGAnnotatedSessionEventTap, keyDown);
        CFRelease(keyDown);

        CGEventRef keyUp = CGEventCreateKeyboardEvent(src, (CGKeyCode)0x09, false);
        CGEventSetFlags(keyUp, kCGEventFlagMaskCommand);
        CGEventPost(kCGAnnotatedSessionEventTap, keyUp);
        CFRelease(keyUp);

        if (src) CFRelease(src);

        return 1;
    }
}
