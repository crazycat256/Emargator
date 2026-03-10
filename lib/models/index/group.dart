import 'year.dart';

/// Represents a TP group in ENSIBS.
class EnsiGroup {
  final String name;
  final List<int> adeIds;
  late EnsiYear year;

  EnsiGroup(this.name, this.adeIds);

  @override
  String toString() => name;
}
