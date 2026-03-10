import 'dart:async';
import 'dart:io';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import '../models/moodle_signed_session.dart';
import 'utils.dart';

const String _baseUrl = 'https://moodle.univ-ubs.fr';
const String _loginUrl =
    'https://cas.univ-ubs.fr/login?service=https%3A%2F%2Fidp.univ-ubs.fr%2Fidp%2FAuthn%2FExternal%3Fconversation%3De1s1%26entityId%3Dhttps%3A%2F%2Fmoodle.univ-ubs.fr%2Fshibboleth';

class AttendanceService {
  AttendanceService(
    this.studentId,
    this.password, {
    this.cachedAttendanceId,
    this.onError,
  });

  final String studentId;
  final String password;
  String? cachedAttendanceId;
  final Function(String context, Object error, StackTrace? stackTrace)? onError;

  final Session session = Session();

  Future<AttendanceResult> signAttendance() async {
    try {
      final String attendanceId;
      if (cachedAttendanceId == null) {
        var res1 = await session.get(
          '$_baseUrl/course/view.php?id=10731',
          allowRedirects: false,
        );

        if (res1.statusCode != 200) {
          final loginResult = await tryLogin();
          if (loginResult != LoginResult.success) {
            return AttendanceResult.loginError;
          }

          res1 = await session.get(
            '$_baseUrl/course/view.php?id=10731',
            allowRedirects: false,
          );

          if (res1.statusCode != 200) {
            return AttendanceResult.coursePageError;
          }
        }

        try {
          final doc = html_parser.parse(res1.body);
          final link = doc.querySelector(
            "a[href^='https://moodle.univ-ubs.fr/mod/attendance/view.php?id=']",
          );

          if (link == null) {
            return AttendanceResult.attendanceIdError;
          }

          final href = link.attributes['href'] ?? '';
          final regex = RegExp(r'id=(\d+)');
          final match = regex.firstMatch(href);

          if (match == null) {
            return AttendanceResult.parseError;
          }

          cachedAttendanceId = match.group(1);
          attendanceId = cachedAttendanceId!;
        } catch (e, stackTrace) {
          onError?.call('SignAttendance - Parse ID', e, stackTrace);
          return AttendanceResult.parseError;
        }
      } else {
        attendanceId = cachedAttendanceId!;
      }

      var res2 = await session.get(
        '$_baseUrl/mod/attendance/view.php?id=$attendanceId',
        allowRedirects: false,
      );

      if (res2.statusCode != 200) {
        final loginResult = await tryLogin();
        if (loginResult != LoginResult.success) {
          return AttendanceResult.loginError;
        }
        res2 = await session.get(
          '$_baseUrl/mod/attendance/view.php?id=$attendanceId',
          allowRedirects: false,
        );
        if (res2.statusCode != 200) {
          return AttendanceResult.attendancePageError;
        }
      }

      try {
        final doc1 = html_parser.parse(res2.body);
        final link = doc1.querySelector(
          "a[href^='https://moodle.univ-ubs.fr/mod/attendance/attendance.php']",
        );

        if (link == null) {
          return AttendanceResult.alreadySignedIn;
        }

        final attendanceUrl = link.attributes['href'] ?? '';
        if (attendanceUrl.isEmpty) {
          return AttendanceResult.parseError;
        }

        final res = await session.get(attendanceUrl, allowRedirects: true);
        final doc2 = html_parser.parse(res.body);
        final alert = doc2.querySelector(
          'div.alert.alert-info.alert-block.fade.in.alert-dismissible',
        );

        if (alert == null) {
          return AttendanceResult.alreadySignedIn;
        }

        final msg = alert.text.trim();
        if (msg.contains(
              'Your attendance in this session has been recorded.',
            ) ||
            msg.contains('Votre présence à cette session a été enregistrée.')) {
          return AttendanceResult.success;
        }

        onError?.call(
          'SignAttendance - Ensure Success',
          'Invalid success msg $msg',
          null,
        );
        return AttendanceResult.unknownError;
      } catch (e, stackTrace) {
        onError?.call('SignAttendance - Parse Page', e, stackTrace);
        return AttendanceResult.parseError;
      }
    } catch (e, stackTrace) {
      if (e is SocketException || e is TimeoutException) {
        return AttendanceResult.networkError;
      }
      onError?.call('SignAttendance - Other', e, stackTrace);
      return AttendanceResult.unknownError;
    }
  }

  /// Fetch all attendance sessions from Moodle and return those that are self-recorded.
  Future<List<MoodleSignedSession>> fetchSignedSessions() async {
    try {
      String? attendanceId = cachedAttendanceId;

      if (attendanceId == null) {
        var res = await session.get(
          '$_baseUrl/course/view.php?id=10731',
          allowRedirects: false,
        );

        if (res.statusCode != 200) {
          final loginResult = await tryLogin();
          if (loginResult != LoginResult.success) return [];
          res = await session.get(
            '$_baseUrl/course/view.php?id=10731',
            allowRedirects: false,
          );
          if (res.statusCode != 200) return [];
        }

        final doc = html_parser.parse(res.body);
        final link = doc.querySelector(
          "a[href^='https://moodle.univ-ubs.fr/mod/attendance/view.php?id=']",
        );
        if (link == null) return [];

        final href = link.attributes['href'] ?? '';
        final match = RegExp(r'id=(\d+)').firstMatch(href);
        if (match == null) return [];

        cachedAttendanceId = match.group(1);
        attendanceId = cachedAttendanceId!;
      }

      var res = await session.get(
        '$_baseUrl/mod/attendance/view.php?id=$attendanceId&view=5',
        allowRedirects: false,
      );

      if (res.statusCode != 200) {
        final loginResult = await tryLogin();
        if (loginResult != LoginResult.success) return [];
        res = await session.get(
          '$_baseUrl/mod/attendance/view.php?id=$attendanceId&view=5',
          allowRedirects: false,
        );
        if (res.statusCode != 200) return [];
      }

      return _parseSignedSessions(res.body);
    } catch (e, stackTrace) {
      onError?.call('FetchSignedSessions', e, stackTrace);
      return [];
    }
  }

  static List<MoodleSignedSession> _parseSignedSessions(String html) {
    final doc = html_parser.parse(html);
    final rows = doc.querySelectorAll('table.generaltable tbody tr');
    final sessions = <MoodleSignedSession>[];

    for (final row in rows) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 5) continue;

      final remarkCell = cells[4];
      if (!remarkCell.text.contains('Self-recorded')) continue;

      final nobrs = cells[0].querySelectorAll('nobr');
      if (nobrs.length < 2) continue;

      final date = _parseMoodleDate(nobrs[0].text.trim());
      final times = _parseMoodleTimeRange(nobrs[1].text.trim());

      if (date != null && times != null) {
        sessions.add(
          MoodleSignedSession(
            date: date,
            startHour: times.$1,
            startMinute: times.$2,
            endHour: times.$3,
            endMinute: times.$4,
          ),
        );
      }
    }

    return sessions;
  }

  static DateTime? _parseMoodleDate(String text) {
    const months = {
      'Jan': 1,
      'Feb': 2,
      'Mar': 3,
      'Apr': 4,
      'May': 5,
      'Jun': 6,
      'Jul': 7,
      'Aug': 8,
      'Sep': 9,
      'Oct': 10,
      'Nov': 11,
      'Dec': 12,
    };
    final parts = text.split(' ');
    if (parts.length < 4) return null;
    final day = int.tryParse(parts[1]);
    final month = months[parts[2]];
    final year = int.tryParse(parts[3]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  /// Parse "8AM - 9:30AM" → (startHour, startMin, endHour, endMin)
  static (int, int, int, int)? _parseMoodleTimeRange(String text) {
    final parts = text.split(' - ');
    if (parts.length != 2) return null;
    final s = _parseMoodleTime(parts[0].trim());
    final e = _parseMoodleTime(parts[1].trim());
    if (s == null || e == null) return null;
    return (s.$1, s.$2, e.$1, e.$2);
  }

  static (int, int)? _parseMoodleTime(String text) {
    final isPM = text.toUpperCase().contains('PM');
    final cleaned = text.replaceAll(RegExp(r'[APap][Mm]'), '').trim();
    final parts = cleaned.split(':');
    var hour = int.tryParse(parts[0]);
    final minute = parts.length > 1 ? int.tryParse(parts[1]) : 0;
    if (hour == null || minute == null) return null;
    if (isPM && hour != 12) hour += 12;
    if (!isPM && hour == 12) hour = 0;
    return (hour, minute);
  }

  Future<LoginResult> tryLogin() async {
    try {
      await session.post('$_baseUrl/auth/shibboleth/login.php', {
        'idp': 'urn:mace:cru.fr:federation:univ-ubs.fr',
      });

      final res1 = await session.get(_loginUrl);

      try {
        final fm1 = html_parser.parse(res1.body).getElementById('fm1');
        if (fm1 == null) {
          return LoginResult.parseError;
        }

        var args = _createArgs(
          fm1,
          extras: {'username': studentId, 'password': password},
        );

        final res2 = await session.post(
          'https://cas.univ-ubs.fr/login',
          args,
          allowRedirects: true,
        );

        final form = html_parser.parse(res2.body).querySelector('form');
        if (form == null) {
          return LoginResult.invalidCredentials;
        }

        args = _createArgs(form);
        final action = (form.attributes['action'] ?? '').trim();

        if (action.isEmpty || action == 'https://cas.univ-ubs.fr/login') {
          return LoginResult.invalidCredentials;
        }

        await session.post(action, args, allowRedirects: true);
        return LoginResult.success;
      } catch (e, stackTrace) {
        onError?.call('TryLogin - Parse', e, stackTrace);
        return LoginResult.parseError;
      }
    } catch (e, stackTrace) {
      onError?.call('TryLogin - Network/Other', e, stackTrace);
      return LoginResult.networkError;
    }
  }

  Map<String, String> _createArgs(
    Element form, {
    Map<String, String> extras = const {},
  }) {
    final args = <String, String>{};
    for (final input in form.querySelectorAll('input')) {
      final name = input.attributes['name'];
      if (name != null && name.isNotEmpty) {
        args[name] = input.attributes['value'] ?? '';
      }
    }
    args.addAll(extras);
    return args;
  }
}

enum LoginResult {
  success('Connexion réussie'),
  alreadyLoggedIn('Déjà connecté'),
  invalidCredentials('Identifiants incorrects'),
  networkError('Erreur réseau - vérifiez votre connexion'),
  serverError('Erreur serveur'),
  parseError('Erreur d\'analyse - format de page inattendu'),
  unknownError('Erreur inconnue');

  const LoginResult(this.message);
  final String message;
}

enum AttendanceResult {
  success('Émargement réussi !'),
  alreadySignedIn('Déjà émargé pour ce créneau'),
  attendanceIdError('Erreur: ID d\'émargement introuvable'),
  loginError('Erreur de connexion SSO'),
  coursePageError('Erreur d\'accès à la page du cours'),
  attendancePageError('Erreur d\'accès à la page d\'émargement'),
  networkError('Erreur réseau - vérifiez votre connexion'),
  parseError('Erreur d\'analyse - format de page inattendu'),
  unknownError('Erreur inconnue');

  const AttendanceResult(this.message);
  final String message;
}
