import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  final Uint8List bytes;
  JsonResponse(this.status, this.body, this.bytes);

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
      final builder = BytesBuilder(copy: false);
      await response.forEach(builder.add).timeout(const Duration(seconds: 60));
      final bytes = builder.takeBytes();
      dynamic decoded;
      try {
        decoded = bytes.isEmpty || isPdf(bytes)
            ? null
            : jsonDecode(utf8.decode(bytes));
      } on FormatException {
        decoded = null;
      }
      return JsonResponse(response.statusCode, decoded, bytes);
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

bool isPdf(List<int> bytes) =>
    bytes.length > 4 &&
    bytes[0] == 0x25 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x44 &&
    bytes[3] == 0x46;

/// Găsește un PDF în răspunsul unui furnizor, oriunde ar fi: ca octeți
/// bruți sau ca text base64 într-un câmp al JSON-ului. Întoarce `null`
/// dacă răspunsul nu conține un PDF.
Uint8List? findPdf(JsonResponse response) {
  if (isPdf(response.bytes)) return response.bytes;

  Uint8List? walk(dynamic node) {
    if (node is String) {
      var text = node.trim();
      final comma = text.indexOf('base64,');
      if (text.startsWith('data:') && comma > 0) {
        text = text.substring(comma + 7);
      }
      // „%PDF” codat base64 începe mereu cu „JVBER”.
      if (text.length < 100 || !text.startsWith('JVBER')) return null;
      try {
        final bytes = base64Decode(text.replaceAll(RegExp(r'\s'), ''));
        return isPdf(bytes) ? bytes : null;
      } on FormatException {
        return null;
      }
    }
    final children = node is Map
        ? node.values
        : node is List
        ? node
        : const [];
    for (final child in children) {
      final found = walk(child);
      if (found != null) return found;
    }
    return null;
  }

  return walk(response.body);
}
