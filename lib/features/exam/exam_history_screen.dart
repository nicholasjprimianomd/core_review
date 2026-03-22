import 'package:flutter/material.dart';

import 'exam_history_models.dart';
import 'exam_session_models.dart';

class ExamHistoryScreen extends StatefulWidget {
  const ExamHistoryScreen({
    required this.loadEntries,
    required this.onOpenEntry,
    required this.themeMode,
    required this.onToggleTheme,
    super.key,
  });

  final Future<List<ExamHistoryEntry>> Function() loadEntries;
  final ValueChanged<ExamHistoryEntry> onOpenEntry;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  @override
  State<ExamHistoryScreen> createState() => _ExamHistoryScreenState();
}

class _ExamHistoryScreenState extends State<ExamHistoryScreen> {
  late Future<List<ExamHistoryEntry>> _future = widget.loadEntries();

  Future<void> _reload() async {
    setState(() {
      _future = widget.loadEntries();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Past exams'),
        actions: [
          IconButton(
            onPressed: _reload,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: widget.onToggleTheme,
            tooltip: widget.themeMode == ThemeMode.dark
                ? 'Switch to light mode'
                : 'Switch to dark mode',
            icon: Icon(
              widget.themeMode == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<ExamHistoryEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load exam history.\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final entries = snapshot.data ?? <ExamHistoryEntry>[];
          if (entries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No past exams yet. Finish a custom exam to see it here.',
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final modeLabel =
                  entry.examMode == ExamMode.test ? 'Test' : 'Tutor';
              final subtitle =
                  '${entry.questionIds.length} questions · $modeLabel · '
                  '${_formatEnded(entry.endedAt)}';
              return Card(
                child: ListTile(
                  title: Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => widget.onOpenEntry(entry),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static String _formatEnded(DateTime endedAt) {
    final local = endedAt.toLocal();
    final y = local.year;
    final mo = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$min';
  }
}
