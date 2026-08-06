import 'person.dart';

/// A trip groups a set of entries together.
class Trip {
  final String id;
  final String title;
  final DateTime startDate;
  final DateTime? endDate;
  final String? coverImagePath;
  final List<Person> companions;

  const Trip({
    required this.id,
    required this.title,
    required this.startDate,
    this.endDate,
    this.coverImagePath,
    this.companions = const [],
  });
}
