import 'dart:async';
import 'dart:io';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'utils.dart';

const String _baseUrl = 'https://moodle.univ-ubs.fr';
const String _loginUrl =
    'https://cas.univ-ubs.fr/login?service=https%3A%2F%2Fidp.univ-ubs.fr%2Fidp%2FAuthn%2FExternal%3Fconversation%3De1s1%26entityId%3Dhttps%3A%2F%2Fmoodle.univ-ubs.fr%2Fshibboleth';

class AttendanceService {
  AttendanceService(this.studentId, this.password, {this.cachedAttendanceId, this.onError});

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
        if (msg.startsWith(
          'Your attendance in this session has been recorded.',
        )) {
          return AttendanceResult.success;
        }

        onError?.call('SignAttendance - Ensure Success', 'Invalid success msg $msg', null);
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
