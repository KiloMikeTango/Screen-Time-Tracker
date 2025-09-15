// import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'models.dart';

class DB {
  static late Database db;

  static Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = join(dir.path, 'screen_time.db');
    db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            app_name TEXT,
            window_title TEXT,
            process_name TEXT,
            start_ts INTEGER,
            end_ts INTEGER,
            duration_sec INTEGER,
            date TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
      },
    );
  }

  static Future<void> insertSessionMap(Map<String, dynamic> m) async {
    await db.insert(
      'sessions',
      m,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<AppSession>> getSessionsForDate(DateTime day) async {
    final dateStr = day.toIso8601String().split('T')[0];
    final rows = await db.query(
      'sessions',
      where: 'date = ?',
      whereArgs: [dateStr],
      orderBy: 'start_ts DESC',
    );
    return rows.map((r) => AppSession.fromMap(r)).toList();
  }

  // Aggregated totals per app for a date
  static Future<List<Map<String, dynamic>>> getAggregatedForDate(
    DateTime day,
  ) async {
    final dateStr = day.toIso8601String().split('T')[0];
    final rows = await db.rawQuery(
      '''
      SELECT app_name, SUM(duration_sec) AS total_sec
      FROM sessions
      WHERE date = ?
      GROUP BY app_name
      ORDER BY total_sec DESC
    ''',
      [dateStr],
    );
    return rows;
  }

  // simple export to CSV (returns CSV text)
  static Future<String> exportDateToCsv(DateTime day) async {
    final sessions = await getSessionsForDate(day);
    final sb = StringBuffer();
    sb.writeln('app_name,window_title,process_name,start,end,duration_sec');
    for (final s in sessions) {
      sb.writeln(
        '"${s.appName}","${s.windowTitle}","${s.processName ?? ""}","${s.start.toIso8601String()}","${s.end.toIso8601String()}",${s.durationSec}',
      );
    }
    return sb.toString();
  }
}
