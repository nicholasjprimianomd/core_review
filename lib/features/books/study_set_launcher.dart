import '../../models/book_models.dart';

typedef StudySetLauncher = Future<void> Function(
  String title,
  List<BookQuestion> questions,
);
