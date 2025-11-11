import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class HttpResponse {
  HttpResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
    this.setCookies = const <String>[],
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
  final List<String> setCookies;
}

class Session {
  Session() : creationTime = DateTime.now().millisecondsSinceEpoch;

  final int creationTime;
  final http.Client _client = _ManualRedirectClient();
  final List<Cookie> _cookies = <Cookie>[];

  Future<HttpResponse> get(String url, {bool allowRedirects = true}) {
    return _send('GET', Uri.parse(url), allowRedirects: allowRedirects);
  }

  Future<HttpResponse> post(String url, Map<String, String> data,
      {bool allowRedirects = true}) {
    return _send('POST', Uri.parse(url),
        formData: data, allowRedirects: allowRedirects);
  }

  Future<HttpResponse> _send(
    String initialMethod,
    Uri initialUri, {
    Map<String, String>? formData,
    required bool allowRedirects,
  }) async {
    var method = initialMethod;
    var uri = initialUri;
    Map<String, String>? currentData = formData;

    for (var redirectCount = 0; redirectCount < 10; redirectCount++) {
      final response = await _execute(method, uri, currentData);
      if (response.setCookies.isNotEmpty) {
        _storeCookies(response.setCookies, uri);
      }

      if (!allowRedirects) {
        return response;
      }

      if (response.statusCode < 300 || response.statusCode >= 400) {
        return response;
      }

      final location = response.headers['location'];
      if (location == null || location.isEmpty) {
        return response;
      }

      uri = _resolveRedirectUri(uri, location);

      if (response.statusCode == 303 ||
          ((response.statusCode == 301 || response.statusCode == 302) &&
              method != 'GET' &&
              method != 'HEAD')) {
        method = 'GET';
        currentData = null;
      }
    }

    throw Exception('Too many redirects');
  }

  Future<HttpResponse> _execute(
      String method, Uri uri, Map<String, String>? data) async {
    final request = http.Request(method, uri);

    final cookieHeader = _cookieHeaderFor(uri);
    if (cookieHeader != null) {
      request.headers['Cookie'] = cookieHeader;
    }

    if (data != null) {
      request.headers['Content-Type'] = 'application/x-www-form-urlencoded';
      request.bodyFields = data;
    }

    final streamed = await _client.send(request);
    final bodyBytes = await streamed.stream.toBytes();
    final body = utf8.decode(bodyBytes);

    final headers = <String, String>{};
    streamed.headers.forEach((key, value) {
      headers[key.toLowerCase()] = value;
    });

    final setCookies = streamed is _ManualStreamedResponse
        ? (streamed.headersAll['set-cookie'] ?? const <String>[])
        : <String>[];

    return HttpResponse(
      statusCode: streamed.statusCode,
      body: body,
      headers: headers,
      setCookies: setCookies,
    );
  }

  void _storeCookies(List<String> rawSetCookie, Uri uri) {
    if (rawSetCookie.isEmpty) {
      return;
    }

    for (final headerValue in rawSetCookie) {
      for (final cookieString in _splitSetCookieHeader(headerValue)) {
        if (cookieString.isEmpty) {
          continue;
        }

        Cookie cookie;
        try {
          cookie = Cookie.fromSetCookieValue(cookieString);
        } catch (_) {
          continue;
        }

        cookie.domain ??= uri.host;
        cookie.path ??= _defaultPath(uri);

        if (cookie.expires != null &&
            cookie.expires!.isBefore(DateTime.now())) {
          _cookies
              .removeWhere((existing) => _sameCookie(existing, cookie, uri));
          continue;
        }

        final index = _cookies
            .indexWhere((existing) => _sameCookie(existing, cookie, uri));
        if (index >= 0) {
          _cookies[index] = cookie;
        } else {
          _cookies.add(cookie);
        }
      }
    }
  }

  String? _cookieHeaderFor(Uri uri) {
    final nowDate = DateTime.now();
    final host = uri.host;
    final path = uri.path.isEmpty ? '/' : uri.path;

    final values = <String>[];

    _cookies.removeWhere((cookie) =>
        cookie.expires != null && cookie.expires!.isBefore(nowDate));

    for (final cookie in _cookies) {
      final domain = (cookie.domain ?? host).toLowerCase();
      final cookiePath = cookie.path ?? '/';

      if (!_domainMatches(domain, host.toLowerCase())) {
        continue;
      }

      if (!_pathMatches(cookiePath, path)) {
        continue;
      }

      values.add('${cookie.name}=${cookie.value}');
    }

    if (values.isEmpty) {
      return null;
    }

    return values.join('; ');
  }

  bool _sameCookie(Cookie a, Cookie b, Uri uri) {
    final host = uri.host;
    final domainA = (a.domain ?? host).toLowerCase();
    final domainB = (b.domain ?? host).toLowerCase();
    final pathA = a.path ?? '/';
    final pathB = b.path ?? '/';
    return a.name == b.name && domainA == domainB && pathA == pathB;
  }

  bool _domainMatches(String cookieDomain, String host) {
    final normalizedDomain =
        cookieDomain.startsWith('.') ? cookieDomain.substring(1) : cookieDomain;
    if (host == normalizedDomain) {
      return true;
    }
    return host.endsWith('.$normalizedDomain');
  }

  bool _pathMatches(String cookiePath, String requestPath) {
    final normalizedRequestPath = requestPath.isEmpty ? '/' : requestPath;
    final normalizedCookiePath = cookiePath.isEmpty ? '/' : cookiePath;

    if (normalizedCookiePath == '/') {
      return true;
    }

    if (normalizedRequestPath == normalizedCookiePath) {
      return true;
    }

    final cookiePrefix = normalizedCookiePath.endsWith('/')
        ? normalizedCookiePath
        : '$normalizedCookiePath/';
    return normalizedRequestPath.startsWith(cookiePrefix);
  }

  Uri _resolveRedirectUri(Uri base, String location) {
    final target = Uri.parse(location);
    if (target.isAbsolute) {
      return target;
    }
    return base.resolveUri(target);
  }

  String _defaultPath(Uri uri) {
    final path = uri.path;
    if (path.isEmpty || !path.startsWith('/')) {
      return '/';
    }
    final lastSlash = path.lastIndexOf('/');
    if (lastSlash <= 0) {
      return '/';
    }
    return path.substring(0, lastSlash);
  }

  List<String> _splitSetCookieHeader(String headerValue) {
    final result = <String>[];
    final lower = headerValue.toLowerCase();
    var start = 0;
    var inExpires = false;

    for (var i = 0; i < headerValue.length; i++) {
      if (!inExpires && lower.startsWith('expires=', i)) {
        inExpires = true;
      } else if (inExpires && headerValue[i] == ';') {
        inExpires = false;
      }

      if (headerValue[i] == ',' && !inExpires) {
        result.add(headerValue.substring(start, i).trim());
        start = i + 1;
      }
    }

    if (start < headerValue.length) {
      result.add(headerValue.substring(start).trim());
    }

    return result;
  }
}

class _ManualRedirectClient extends http.BaseClient {
  _ManualRedirectClient() : _inner = HttpClient();

  final HttpClient _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final ioRequest = await _inner.openUrl(request.method, request.url);

    request.headers.forEach((name, value) {
      ioRequest.headers.set(name, value);
    });

    ioRequest.followRedirects = false;

    if (request.contentLength != null) {
      ioRequest.contentLength = request.contentLength!;
    } else {
      ioRequest.contentLength = -1;
    }

    final stream = request.finalize();
    await for (final chunk in stream) {
      ioRequest.add(chunk);
    }

    final ioResponse = await ioRequest.close();

    final headersAll = <String, List<String>>{};
    ioResponse.headers.forEach((name, values) {
      headersAll[name.toLowerCase()] = List<String>.from(values);
    });

    final singleValueHeaders = <String, String>{};
    headersAll.forEach((name, values) {
      singleValueHeaders[name] = values.join(',');
    });

    return _ManualStreamedResponse(
      ioResponse,
      ioResponse.statusCode,
      headers: singleValueHeaders,
      headersAll: headersAll,
      isRedirect: ioResponse.isRedirect,
      reasonPhrase: ioResponse.reasonPhrase,
      persistentConnection: ioResponse.persistentConnection,
      request: request,
    );
  }

  @override
  void close() {
    _inner.close(force: true);
  }
}

class _ManualStreamedResponse extends http.StreamedResponse {
  _ManualStreamedResponse(
    Stream<List<int>> stream,
    int statusCode, {
    required Map<String, String> headers,
    required this.headersAll,
    bool isRedirect = false,
    http.BaseRequest? request,
    bool persistentConnection = true,
    String? reasonPhrase,
  }) : super(
          stream,
          statusCode,
          headers: headers,
          isRedirect: isRedirect,
          request: request,
          persistentConnection: persistentConnection,
          reasonPhrase: reasonPhrase,
        );

  final Map<String, List<String>> headersAll;
}
