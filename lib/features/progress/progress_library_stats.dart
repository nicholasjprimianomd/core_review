import '../../models/book_models.dart';
import '../../models/progress_models.dart';

/// Metrics restricted to question IDs that exist in the current [BookContent].
///
/// Stored progress can include extra keys (e.g. after re-extracts); those are
/// reported as [orphanedRecords].
class ProgressLibraryStats {
  const ProgressLibraryStats({
    required this.answeredInLibrary,
    required this.correctInLibrary,
    required this.revealedInLibrary,
    required this.orphanedRecords,
  });

  final int answeredInLibrary;
  final int correctInLibrary;
  final int revealedInLibrary;
  final int orphanedRecords;

  double get accuracy {
    if (revealedInLibrary == 0) {
      return 0;
    }
    return correctInLibrary / revealedInLibrary;
  }

  static ProgressLibraryStats compute(
    BookContent content,
    StudyProgress progress,
  ) {
    final libraryIds = content.questions.map((q) => q.id).toSet();
    var answeredInLibrary = 0;
    var correctInLibrary = 0;
    var revealedInLibrary = 0;

    for (final question in content.questions) {
      final qp = progress.answers[question.id];
      if (qp == null) {
        continue;
      }
      answeredInLibrary++;
      if (qp.isRevealed) {
        revealedInLibrary++;
        if (qp.isCorrect) {
          correctInLibrary++;
        }
      }
    }

    final matchedKeys =
        progress.answers.keys.where(libraryIds.contains).length;
    final orphanedRecords = progress.answers.length - matchedKeys;

    return ProgressLibraryStats(
      answeredInLibrary: answeredInLibrary,
      correctInLibrary: correctInLibrary,
      revealedInLibrary: revealedInLibrary,
      orphanedRecords: orphanedRecords,
    );
  }
}
