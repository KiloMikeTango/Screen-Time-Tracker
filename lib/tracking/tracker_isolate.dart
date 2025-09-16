// Runs inside an isolate. Polls active window and sends finished sessions
// to the main isolate via the provided SendPort.

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// psapi.dll for process name
final _psapi = DynamicLibrary.open('psapi.dll');
final _GetModuleFileNameExW = _psapi
    .lookupFunction<
      Uint32 Function(
        IntPtr hProcess,
        IntPtr hModule,
        Pointer<Utf16> lpFilename,
        Uint32 nSize,
      ),
      int Function(
        int hProcess,
        int hModule,
        Pointer<Utf16> lpFilename,
        int nSize,
      )
    >('GetModuleFileNameExW');

/// Entry point for the isolate.
void trackerIsolateEntry(SendPort sendPort) {
  const pollSeconds = 3; // poll interval
  const idleThresholdMs = 60 * 1000; // idle after 60s

  String currentApp = '';
  String currentTitle = '';
  DateTime? currentStart;
  DateTime currentDay = DateTime.now();

  // helper: send a completed session
  void sendSession(String app, String title, DateTime start, DateTime end) {
    final durationSec = end.difference(start).inSeconds;
    final dateStr = start.toIso8601String().split('T')[0];

    sendPort.send({
      'type': 'session',
      'app_name': app,
      'window_title': title,
      'process_name': app,
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
      'start_ts': start.millisecondsSinceEpoch,
      'end_ts': end.millisecondsSinceEpoch,
      'duration_sec': durationSec,
      'date': dateStr,
    });
  }

  // get active window title
  String getActiveWindowTitle() {
    final hwnd = GetForegroundWindow();
    if (hwnd == 0) return '';

    final length = GetWindowTextLength(hwnd);
    if (length <= 0) return '';

    final buffer = calloc<Uint16>(length + 1);
    try {
      final read = GetWindowText(hwnd, buffer.cast<Utf16>(), length + 1);
      if (read <= 0) return '';
      return buffer.cast<Utf16>().toDartString();
    } finally {
      calloc.free(buffer);
    }
  }

  // get active process name
  String getActiveProcessName() {
    final hwnd = GetForegroundWindow();
    if (hwnd == 0) return '';

    final pidPtr = calloc<Uint32>();
    try {
      GetWindowThreadProcessId(hwnd, pidPtr);
      final pid = pidPtr.value;
      if (pid == 0) return '';

      final hProcess = OpenProcess(
        PROCESS_QUERY_INFORMATION | PROCESS_VM_READ,
        FALSE,
        pid,
      );
      if (hProcess == 0) return '';

      final buffer = calloc<Uint16>(260); // MAX_PATH
      try {
        final len = _GetModuleFileNameExW(
          hProcess,
          0,
          buffer.cast<Utf16>(),
          260,
        );
        if (len == 0) return '';
        final fullPath = buffer.cast<Utf16>().toDartString();
        final exeName = fullPath.split(Platform.pathSeparator).last;
        return exeName;
      } finally {
        calloc.free(buffer);
        CloseHandle(hProcess);
      }
    } finally {
      calloc.free(pidPtr);
    }
  }

  // idle detection
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

  Timer.periodic(Duration(seconds: pollSeconds), (timer) {
    try {
      final now = DateTime.now();

      // --- handle midnight rollover ---
      if (now.day != currentDay.day ||
          now.month != currentDay.month ||
          now.year != currentDay.year) {
        // close previous session if active
        if (currentApp.isNotEmpty && currentStart != null) {
          sendSession(currentApp, currentTitle, currentStart!, now.toUtc());
        }

        // reset for new day and start fresh session if window exists
        currentDay = now;
        final proc = getActiveProcessName();
        final title = getActiveWindowTitle();
        if (proc.isNotEmpty) {
          currentApp = proc;
          currentTitle = title;
          currentStart = DateTime.now().toUtc();
        } else {
          currentApp = '';
          currentTitle = '';
          currentStart = null;
        }
        return;
      }

      // --- idle detection ---
      final idle = getIdleMilliseconds();
      if (idle >= idleThresholdMs) {
        if (currentApp.isNotEmpty && currentStart != null) {
          final end = DateTime.now().toUtc();
          sendSession(currentApp, currentTitle, currentStart!, end);
          currentApp = '';
          currentTitle = '';
          currentStart = null;
        }
        return;
      }

      // --- active window tracking ---
      final proc = getActiveProcessName();
      final title = getActiveWindowTitle();
      if (proc.isEmpty) return;

      if (proc != currentApp) {
        // close previous session
        if (currentApp.isNotEmpty && currentStart != null) {
          final end = DateTime.now().toUtc();
          sendSession(currentApp, currentTitle, currentStart!, end);
        }
        // start new session
        currentApp = proc;
        currentTitle = title;
        currentStart = DateTime.now().toUtc();
      }
    } catch (e) {
      sendPort.send({'type': 'error', 'message': e.toString()});
    }
  });
}
