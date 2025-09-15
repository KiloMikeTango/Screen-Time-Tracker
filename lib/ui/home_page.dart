import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/db.dart';
import '../tracking/tracker_isolate.dart';
import '../utils/formatters.dart';
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
  double _totalSec = 0;

  @override
  void initState() {
    super.initState();
    _startTracker();
    _loadAggregated();
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
          await _loadAggregated();
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
    final total = rows.fold<int>(0, (p, e) => p + (e['total_sec'] as int));

    setState(() {
      _aggregated = rows;
      _totalSec = total.toDouble();
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Screen Time Tracker',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.blueGrey[900],
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 900) {
            return _buildDesktopLayout();
          } else if (constraints.maxWidth > 600) {
            return _buildTabletLayout();
          } else {
            return _buildCompactLayout();
          }
        },
      ),
    );
  }

  Widget _buildCompactLayout() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        children: [
          _buildTotalTimeCard(fontSize: 28, padding: 24),
          const SizedBox(height: 16),
          Expanded(child: _buildUsageList(itemPadding: 12)),
        ],
      ),
    );
  }

  Widget _buildTabletLayout() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: _buildTotalTimeCard(fontSize: 36, padding: 32),
          ),
          const SizedBox(width: 20),
          Expanded(flex: 3, child: _buildUsageList(itemPadding: 16)),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: _buildTotalTimeCard(fontSize: 48, padding: 40),
          ),
          const SizedBox(width: 32),
          Expanded(flex: 3, child: _buildUsageList(itemPadding: 20)),
        ],
      ),
    );
  }

  Widget _buildTotalTimeCard({
    required double fontSize,
    required double padding,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2E3B4E),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            //TODO:

            //width: 900, height: 720
            //width: 600, height 720
            Text(
              MediaQuery.of(context).size.width.toString(),
              style: TextStyle(color: Colors.white),
            ),
            Text(
              MediaQuery.of(context).size.height.toString(),
              style: TextStyle(color: Colors.white),
            ),
            Text(
              'Total Screen Time Today',

              style: GoogleFonts.poppins(
                fontSize: fontSize * 0.4,
                color: Colors.white70,
                fontWeight: FontWeight.w400,
              ),
            ),
            SizedBox(height: padding / 2),
            Text(
              formatDurationSeconds(_totalSec.toInt()),
              style: GoogleFonts.poppins(
                fontSize: fontSize,
                fontWeight: FontWeight.w300,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsageList({required double itemPadding}) {
    if (_aggregated.isEmpty) {
      return Center(
        child: Text(
          'No activity recorded for today.',
          style: GoogleFonts.poppins(
            fontStyle: FontStyle.italic,
            color: Colors.grey,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: _aggregated.length,
        itemBuilder: (context, index) {
          final row = _aggregated[index];
          final name = row['app_name'] as String;
          final secs = row['total_sec'] as int;
          final percentage = _totalSec > 0 ? (secs / _totalSec) : 0.0;
          return _buildAppListItem(name, secs, percentage, itemPadding);
        },
      ),
    );
  }

  Widget _buildAppListItem(
    String name,
    int secs,
    double percentage,
    double padding,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: padding * 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.desktop_windows, color: Colors.blueGrey[600]),
              SizedBox(width: padding * 0.6),
              Expanded(
                child: Text(
                  name,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 16 + padding * 0.05,
                  ),
                ),
              ),
              Text(
                formatDurationSeconds(secs),
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF4CAF50), // A new deep green color
                  fontSize: 13.5 + padding * 0.05,
                ),
              ),
            ],
          ),
          SizedBox(height: padding),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: percentage,
              minHeight: 8,
              backgroundColor: Colors.grey[200],
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF4CAF50),
              ), // The same new green
            ),
          ),
          SizedBox(height: padding * 0.2),
          Text(
            '${(percentage * 100).toStringAsFixed(1)}% of total time',
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
          ),
          Divider(height: padding),
        ],
      ),
    );
  }
}
