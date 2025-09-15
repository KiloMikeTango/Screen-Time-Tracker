// Runs inside an isolate. Polls active window and sends finished sessions
// to the main isolate via the provided SendPort.

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Entry point for the isolate.
/// `sendPort` is the main isolate's ReceivePort.sendPort
void trackerIsolateEntry(SendPort sendPort) {
  const pollSeconds = 3; // poll interval (tweakable)
  const idleThresholdMs = 60 * 1000; // user considered idle after this (60s)

  String currentApp = '';
  String currentTitle = '';
  DateTime? currentStart;

  // Simple helper: get active window title (UTF-16)
  // Get active window title (UTF-16)
  // Get active window title (UTF-16)
  String getActiveWindowTitle() {
    final hwnd = GetForegroundWindow();
    if (hwnd == 0) return '';

    final length = GetWindowTextLength(hwnd);
    if (length <= 0) return '';

    // allocate as Uint16 and cast to Utf16 when calling / converting
    final buffer = calloc<Uint16>(length + 1);
    try {
      final read = GetWindowText(hwnd, buffer.cast<Utf16>(), length + 1);
      if (read <= 0) return '';
      return buffer.cast<Utf16>().toDartString();
    } finally {
      calloc.free(buffer);
    }
  }

  // Idle detection using GetLastInputInfo
  int getIdleMilliseconds() {
    final lastInputInfo = calloc<LASTINPUTINFO>();
    try {
      lastInputInfo.ref.cbSize = sizeOf<LASTINPUTINFO>();
      final ok = GetLastInputInfo(lastInputInfo);
      if (ok == 0) return 0;
      final last = lastInputInfo.ref.dwTime;
      final now = GetTickCount();
      return now - last;
    } finally {
      calloc.free(lastInputInfo);
    }
  }

  String simplifyAppNameFromTitle(String title) {
    // naive heuristic: take first token or part before ' - ' which many browsers use
    if (title.contains(' - ')) {
      return title
          .split(' - ')
          .last
          .trim(); // "Google Chrome" or website name - adjust if desired
    }
    if (title.length > 40) {
      return title.substring(0, 40) + '...';
    }
    return title;
  }

  Timer.periodic(Duration(seconds: pollSeconds), (timer) {
    try {
      final idle = getIdleMilliseconds();
      if (idle >= idleThresholdMs) {
        // user idle — close any open session
        if (currentApp.isNotEmpty && currentStart != null) {
          final end = DateTime.now().toUtc();
          sendPort.send({
            'type': 'session',
            'app_name': currentApp,
            'window_title': currentTitle,
            'process_name': null,
            'start': currentStart!.toIso8601String(),
            'end': end.toIso8601String(),
          });
          currentApp = '';
          currentTitle = '';
          currentStart = null;
        }
        return;
      }

      final title = getActiveWindowTitle();
      if (title.isEmpty) return;

      final app = simplifyAppNameFromTitle(title);

      if (app != currentApp) {
        // close previous session
        if (currentApp.isNotEmpty && currentStart != null) {
          final end = DateTime.now().toUtc();
          sendPort.send({
            'type': 'session',
            'app_name': currentApp,
            'window_title': currentTitle,
            'process_name': null,
            'start': currentStart!.toIso8601String(),
            'end': end.toIso8601String(),
          });
        }
        // start new session
        currentApp = app;
        currentTitle = title;
        currentStart = DateTime.now().toUtc();
      }
    } catch (e) {
      // If the isolate throws, send error message to main for debug
      sendPort.send({'type': 'error', 'message': e.toString()});
    }
  });
}
