/// A travel companion.
class Person {
  final String id;
  final String name;
  final String? avatarPath;

  const Person({
    required this.id,
    required this.name,
    this.avatarPath,
  });
}
