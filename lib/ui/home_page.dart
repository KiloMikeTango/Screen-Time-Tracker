import 'dart:async';
import 'package:flutter/material.dart';
import '../data/db.dart';
import '../tracking/tracker_isolate.dart';
// import '../data/models.dart';
import '../utils/formatters.dart';
// import 'package:isolate/isolate.dart' as isolate_pkg; // not necessary but keep imports clean
import 'dart:isolate';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _trackerStarted = false;
  List<Map<String, dynamic>> _aggregated = [];
  Timer? _refreshTimer;
  ReceivePort? _receivePort;
  Isolate? _isolate;

  @override
  void initState() {
    super.initState();
    _startTracker();
    _loadAggregated();
    // periodic refresh so UI updates even if DB change is missed
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadAggregated(),
    );
  }

  Future<void> _startTracker() async {
    if (_trackerStarted) return;
    _receivePort = ReceivePort();
    _receivePort!.listen((message) async {
      if (message is Map && message['type'] == 'session') {
        try {
          final start = DateTime.parse(message['start']).toUtc();
          final end = DateTime.parse(message['end']).toUtc();
          final dur = end.difference(start).inSeconds;
          final map = {
            'app_name': message['app_name'],
            'window_title': message['window_title'],
            'process_name': message['process_name'],
            'start_ts': start.millisecondsSinceEpoch,
            'end_ts': end.millisecondsSinceEpoch,
            'duration_sec': dur,
            'date': start.toIso8601String().split('T')[0],
          };
          await DB.insertSessionMap(map);
          await _loadAggregated(); // update UI
        } catch (e) {
          // ignore write error for now
        }
      } else if (message is Map && message['type'] == 'error') {
        // optionally show debug
        // print('Tracker isolate error: ${message['message']}');
      }
    });

    _isolate = await Isolate.spawn(trackerIsolateEntry, _receivePort!.sendPort);
    _trackerStarted = true;
  }

  Future<void> _loadAggregated() async {
    final rows = await DB.getAggregatedForDate(DateTime.now());
    setState(() {
      _aggregated = rows;
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _receivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalSec = _aggregated.fold<int>(
      0,
      (p, e) => p + (e['total_sec'] as int),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Screen Time Tracker')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Card(
              child: ListTile(
                title: const Text('Today total'),
                subtitle: Text(formatDurationSeconds(totalSec)),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _aggregated.isEmpty
                  ? const Center(child: Text('No usage yet'))
                  : ListView.separated(
                      itemCount: _aggregated.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final row = _aggregated[index];
                        final name = row['app_name'] as String;
                        final secs = row['total_sec'] as int;
                        return ListTile(
                          title: Text(name),
                          trailing: Text(formatDurationSeconds(secs)),
                        );
                      },
                    ),
            ),
            ElevatedButton(
              onPressed: () async {
                final csv = await DB.exportDateToCsv(DateTime.now());
                // For now just print CSV; later save to file using path_provider
                // print(csv);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('CSV generated (check console)'),
                  ),
                );
              },
              child: const Text('Export CSV (dev)'),
            ),
          ],
        ),
      ),
    );
  }
}
