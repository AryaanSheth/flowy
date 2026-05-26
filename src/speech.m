/**
 * Flowey — macOS Speech Recognition helper
 *
 * Thin C API over SFSpeechRecognizer so Rust can call into the Speech
 * framework without needing objc2 bindings.  Compiled with -fobjc-arc via
 * the `cc` build crate so all ObjC memory management is automatic.
 */

#import <Speech/Speech.h>
#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#include <stdlib.h>

// ── Accessibility (needed for CGEventTap / global hotkeys) ────

/// Opens System Settings → Accessibility for this process and prompts
/// the user to grant access.  Returns 1 if already trusted, 0 if not.
int flowey_request_accessibility(void) {
    NSDictionary* opts = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts) ? 1 : 0;
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
