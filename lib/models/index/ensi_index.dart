import 'formation.dart';

/// The ENSIBS index parsed from the remote JSON.
/// Contains all formations, years, and groups.
class EnsiIndex {
  static List<EnsiFormation> formations = [];
  static int projectId = 1;

  /// Parse the ENSIBS section from the full index JSON.
  static void fromJson(Map<String, dynamic> fullJson) {
    final ensibs = fullJson['ENSIBS'] as Map<String, dynamic>?;
    if (ensibs == null) return;

    formations = [];
    for (var formationName in ensibs.keys.toList()) {
      // PEI students don't need to sign attendance
      if (formationName == 'PEI') continue;
      formations.add(
        EnsiFormation.fromJson(formationName, ensibs[formationName]),
      );
    }
  }
}
