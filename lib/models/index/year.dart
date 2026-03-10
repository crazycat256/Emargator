import 'group.dart';
import 'formation.dart';

/// Represents a year (e.g. "3ème année").
class EnsiYear {
  final String name;
  final List<EnsiGroup> groups;
  late EnsiFormation formation;

  EnsiYear(this.name, this.groups);

  factory EnsiYear.fromJson(String name, Map<String, dynamic> json) {
    List<EnsiGroup> groups = [];
    for (var groupName in json.keys.toList()) {
      groups.add(EnsiGroup(groupName, List<int>.from(json[groupName])));
    }
    EnsiYear year = EnsiYear(name, groups);
    for (var group in groups) {
      group.year = year;
    }
    return year;
  }

  @override
  String toString() => name;
}
