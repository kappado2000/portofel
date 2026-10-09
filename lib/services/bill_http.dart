import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Eroare afișabilă utilizatorului, apărută la preluarea facturilor.
class BillFetchException implements Exception {
  final String message;
  BillFetchException(this.message);

  @override
  String toString() => message;
}

class JsonResponse {
  final int status;
  final dynamic body;
  JsonResponse(this.status, this.body);

  Map<String, dynamic> get map =>
      body is Map ? Map<String, dynamic>.from(body as Map) : const {};
}

/// Client HTTP minimal pentru API-urile furnizorilor: trimite/primește JSON
/// și ține minte cookie-urile sesiunii (E.ON se bazează pe ele la
/// reînnoirea tokenului), ca să poată fi salvate între porniri.
class JsonHttp {
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);
  final Map<String, String> cookies = {};

  Future<JsonResponse> send(
    String method,
    String url, {
    Map<String, String> headers = const {},
    Object? body,
  }) async {
    try {
      final request = await _client.openUrl(method, Uri.parse(url));
      headers.forEach(request.headers.set);
      if (cookies.isNotEmpty) {
        request.headers.set(
          HttpHeaders.cookieHeader,
          cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
        );
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      for (final c in response.cookies) {
        cookies[c.name] = c.value;
      }
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 30));
      dynamic decoded;
      try {
        decoded = text.isEmpty ? null : jsonDecode(text);
      } on FormatException {
        decoded = null;
      }
      return JsonResponse(response.statusCode, decoded);
    } on SocketException {
      throw BillFetchException('Fără conexiune la internet.');
    } on TimeoutException {
      throw BillFetchException('Serverul furnizorului nu a răspuns la timp.');
    } on HandshakeException {
      throw BillFetchException('Conexiune securizată eșuată cu furnizorul.');
    } on HttpException {
      throw BillFetchException('Eroare de comunicare cu furnizorul.');
    }
  }

  void close() => _client.close(force: true);
}

/// Parsează o sumă venită fie ca număr, fie ca text în format românesc
/// ("1.234,56") sau standard ("1234.56").
double parseAmount(dynamic value) {
  if (value is num) return value.toDouble();
  if (value == null) return 0;
  var s = value.toString().trim().replaceAll(RegExp(r'[^0-9,.\-]'), '');
  if (s.isEmpty) return 0;
  if (s.contains(',')) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (!RegExp(r'^-?\d+(\.\d{1,2})?$').hasMatch(s)) {
    s = s.replaceAll('.', '');
  }
  return double.tryParse(s) ?? 0;
}

/// Parsează o dată în formatele folosite de furnizori: ISO, `yyyyMMdd`,
/// `dd/MM/yyyy` sau `dd.MM.yyyy`.
DateTime? parseBillDate(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  if (RegExp(r'^\d{8}$').hasMatch(s)) {
    return DateTime.tryParse(
      '${s.substring(0, 4)}-${s.substring(4, 6)}-${s.substring(6, 8)}',
    );
  }
  final dmy = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})').firstMatch(s);
  if (dmy != null) {
    return DateTime(
      int.parse(dmy.group(3)!),
      int.parse(dmy.group(2)!),
      int.parse(dmy.group(1)!),
    );
  }
  final iso = DateTime.tryParse(s);
  return iso == null ? null : DateTime(iso.year, iso.month, iso.day);
}
