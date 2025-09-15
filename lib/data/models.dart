class AppSession {
  final int? id;
  final String appName;
  final String windowTitle;
  final String? processName;
  final DateTime start;
  final DateTime end;
  final int durationSec;

  AppSession({
    this.id,
    required this.appName,
    required this.windowTitle,
    this.processName,
    required this.start,
    required this.end,
    required this.durationSec,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'app_name': appName,
      'window_title': windowTitle,
      'process_name': processName,
      'start_ts': start.millisecondsSinceEpoch,
      'end_ts': end.millisecondsSinceEpoch,
      'duration_sec': durationSec,
      'date': start.toIso8601String().split('T')[0],
    };
  }

  factory AppSession.fromMap(Map<String, dynamic> m) {
    final start = DateTime.fromMillisecondsSinceEpoch(m['start_ts'] as int);
    final end = DateTime.fromMillisecondsSinceEpoch(m['end_ts'] as int);
    return AppSession(
      id: m['id'] as int?,
      appName: m['app_name'] as String,
      windowTitle: m['window_title'] as String,
      processName: m['process_name'] as String?,
      start: start,
      end: end,
      durationSec: m['duration_sec'] as int,
    );
  }
}
