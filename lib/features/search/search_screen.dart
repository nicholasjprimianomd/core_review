import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/book_models.dart';
import '../../models/progress_models.dart';
import '../../models/study_data_models.dart';
import '../books/study_set_launcher.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    required this.content,
    required this.progressListenable,
    required this.studyDataListenable,
    required this.themeMode,
    required this.onToggleTheme,
    required this.onStartStudySet,
    super.key,
  });

  final BookContent content;
  final ValueListenable<StudyProgress> progressListenable;
  final ValueListenable<StudyData> studyDataListenable;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;
  final StudySetLauncher onStartStudySet;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _queryController = TextEditingController();
  List<BookQuestion> _results = [];
  _SearchFilter _filter = _SearchFilter.all;
  bool _hasSearched = false;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _performSearch() {
    final query = _queryController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }

    final studyData = widget.studyDataListenable.value;
    final progress = widget.progressListenable.value;

    var candidates = widget.content.questions;

    if (_filter == _SearchFilter.flagged) {
      candidates = candidates
          .where((q) => studyData.forQuestion(q.id).isFlagged)
          .toList();
    } else if (_filter == _SearchFilter.withNotes) {
      candidates = candidates
          .where((q) => studyData.forQuestion(q.id).hasNote)
          .toList();
    } else if (_filter == _SearchFilter.incorrect) {
      candidates = candidates.where((q) {
        final p = progress.answers[q.id];
        return p != null && p.isRevealed && !p.isCorrect;
      }).toList();
    }

    final matches = candidates.where((q) {
      if (q.prompt.toLowerCase().contains(query)) return true;
      if (q.explanation.toLowerCase().contains(query)) return true;
      if (q.chapterTitle.toLowerCase().contains(query)) return true;
      if (q.bookTitle.toLowerCase().contains(query)) return true;
      if (q.topicTitle?.toLowerCase().contains(query) ?? false) return true;
      if (q.sectionTitle?.toLowerCase().contains(query) ?? false) return true;
      for (final choice in q.choices.values) {
        if (choice.toLowerCase().contains(query)) return true;
      }
      final noteText = studyData.forQuestion(q.id).note;
      if (noteText.toLowerCase().contains(query)) return true;
      return false;
    }).toList();

    setState(() {
      _results = matches;
      _hasSearched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Questions'),
        actions: [
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _queryController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search question stems, explanations, notes...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _queryController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _queryController.clear();
                          _performSearch();
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _performSearch(),
              onSubmitted: (_) => _performSearch(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final filter in _SearchFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(filter.label),
                        selected: _filter == filter,
                        onSelected: (selected) {
                          setState(() => _filter = selected ? filter : _SearchFilter.all);
                          _performSearch();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_hasSearched)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    '${_results.length} result${_results.length == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                  const Spacer(),
                  if (_results.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        widget.onStartStudySet(
                          'Search: ${_queryController.text.trim()}',
                          _results,
                        );
                      },
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Study these'),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _hasSearched && _results.isEmpty
                ? Center(
                    child: Text(
                      'No matching questions found.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  )
                : ValueListenableBuilder<StudyProgress>(
                    valueListenable: widget.progressListenable,
                    builder: (context, progress, _) {
                      return ValueListenableBuilder<StudyData>(
                        valueListenable: widget.studyDataListenable,
                        builder: (context, studyData, _) {
                          return ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _results.length,
                            itemBuilder: (context, index) {
                              final question = _results[index];
                              return _SearchResultCard(
                                question: question,
                                progress: progress.answers[question.id],
                                studyData: studyData.forQuestion(question.id),
                                query: _queryController.text.trim(),
                                onTap: () {
                                  widget.onStartStudySet(
                                    '${question.chapterNumber}. ${question.chapterTitle}',
                                    [question],
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

enum _SearchFilter {
  all('All'),
  flagged('Flagged'),
  withNotes('With notes'),
  incorrect('Incorrect');

  const _SearchFilter(this.label);
  final String label;
}

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.question,
    required this.progress,
    required this.studyData,
    required this.query,
    required this.onTap,
  });

  final BookQuestion question;
  final QuestionProgress? progress;
  final QuestionStudyData studyData;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAnswered = progress != null;
    final isCorrect = progress?.isRevealed == true && (progress?.isCorrect ?? false);
    final isIncorrect = progress?.isRevealed == true && !(progress?.isCorrect ?? true);

    Color? statusColor;
    IconData statusIcon = Icons.radio_button_unchecked;
    if (isCorrect) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (isIncorrect) {
      statusColor = Colors.red;
      statusIcon = Icons.cancel;
    } else if (isAnswered) {
      statusColor = Colors.blueGrey;
      statusIcon = Icons.check_circle_outline;
    }

    final snippet = _buildSnippet(question, query);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(statusIcon, size: 18, color: statusColor ?? Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Q${question.displayNumber} - ${question.bookTitle}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (studyData.isFlagged)
                    Icon(Icons.flag, size: 16, color: Colors.orange),
                  if (studyData.hasNote)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.sticky_note_2, size: 16, color: Colors.amber),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${question.chapterNumber}. ${question.chapterTitle}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
              const SizedBox(height: 6),
              Text.rich(
                snippet,
                style: theme.textTheme.bodySmall,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static TextSpan _buildSnippet(BookQuestion question, String query) {
    if (query.isEmpty) {
      return TextSpan(text: _truncate(question.prompt, 150));
    }

    final lowerQuery = query.toLowerCase();
    final sources = [
      question.prompt,
      question.explanation,
      ...question.choices.values,
    ];

    for (final source in sources) {
      final lowerSource = source.toLowerCase();
      final idx = lowerSource.indexOf(lowerQuery);
      if (idx >= 0) {
        final start = (idx - 40).clamp(0, source.length);
        final end = (idx + query.length + 80).clamp(0, source.length);
        final before = source.substring(start, idx);
        final match = source.substring(idx, idx + query.length);
        final after = source.substring(idx + query.length, end);

        return TextSpan(
          children: [
            if (start > 0) const TextSpan(text: '...'),
            TextSpan(text: before),
            TextSpan(
              text: match,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                backgroundColor: Color(0x33FFEB3B),
              ),
            ),
            TextSpan(text: after),
            if (end < source.length) const TextSpan(text: '...'),
          ],
        );
      }
    }

    return TextSpan(text: _truncate(question.prompt, 150));
  }

  static String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
}
