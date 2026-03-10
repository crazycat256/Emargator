import 'year.dart';

/// Represents a formation (e.g. "CyberDéfense").
class EnsiFormation {
  final String name;
  final List<EnsiYear> years;

  EnsiFormation(this.name, this.years);

  factory EnsiFormation.fromJson(String name, Map<String, dynamic> json) {
    List<EnsiYear> years = [];
    for (var yearName in json.keys.toList()) {
      years.add(EnsiYear.fromJson(yearName, json[yearName]));
    }
    EnsiFormation formation = EnsiFormation(name, years);
    for (var year in years) {
      year.formation = formation;
    }
    return formation;
  }

  @override
  String toString() => name;
}
