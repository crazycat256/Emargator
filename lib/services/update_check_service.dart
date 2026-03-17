import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateCheckResult {
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String releaseUrl;

  const UpdateCheckResult({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
  });
}

class UpdateCheckService {
  static const _latestReleaseUrl =
      'https://api.github.com/repos/crazycat256/Emargator/releases/latest';

  static Future<UpdateCheckResult?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http.get(
        Uri.parse(_latestReleaseUrl),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'Emargator-App',
        },
      );

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String?) ?? '';
      final latestVersion = _sanitizeVersion(tagName);
      if (latestVersion.isEmpty) return null;
      final releaseUrl =
          (data['html_url'] as String?)?.trim().isNotEmpty == true
          ? (data['html_url'] as String).trim()
          : 'https://github.com/crazycat256/Emargator/releases/latest';

      final hasUpdate = _compareVersions(latestVersion, currentVersion) > 0;

      return UpdateCheckResult(
        hasUpdate: hasUpdate,
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        releaseUrl: releaseUrl,
      );
    } catch (_) {
      return null;
    }
  }

  static String _sanitizeVersion(String raw) {
    var cleaned = raw.trim();
    if (cleaned.startsWith('v') || cleaned.startsWith('V')) {
      cleaned = cleaned.substring(1);
    }

    final plusIdx = cleaned.indexOf('+');
    if (plusIdx >= 0) cleaned = cleaned.substring(0, plusIdx);

    final dashIdx = cleaned.indexOf('-');
    if (dashIdx >= 0) cleaned = cleaned.substring(0, dashIdx);

    return cleaned;
  }

  static int _compareVersions(String a, String b) {
    final pa = _sanitizeVersion(
      a,
    ).split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = _sanitizeVersion(
      b,
    ).split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final maxLen = pa.length > pb.length ? pa.length : pb.length;
    while (pa.length < maxLen) {
      pa.add(0);
    }
    while (pb.length < maxLen) {
      pb.add(0);
    }

    for (int i = 0; i < maxLen; i++) {
      if (pa[i] > pb[i]) return 1;
      if (pa[i] < pb[i]) return -1;
    }
    return 0;
  }
}
