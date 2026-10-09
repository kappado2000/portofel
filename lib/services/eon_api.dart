import 'dart:typed_data';

import '../models/bill.dart';
import 'bill_http.dart';

/// E.ON cere un cod de verificare (email/SMS) pentru a finaliza logarea.
class EonMfaRequired implements Exception {
  final String uuid;
  final String type;
  final String recipient;
  EonMfaRequired(this.uuid, this.type, this.recipient);
}

/// Preia facturile neachitate din contul E.ON Myline, prin API-ul folosit
/// de portalul lor web. Sesiunea (token + cookie-uri) se poate salva cu
/// [exportSession] și reîncărca cu [restoreSession], ca să nu fie cerut
/// codul de verificare la fiecare actualizare.
class EonApi {
  static const _base = 'https://api2.eon.ro';
  static const _headers = {
    'Accept': 'application/json, text/plain, */*',
    'Ocp-Apim-Subscription-Key': '674e9032df9d456fa371e17a4097a5b8',
    'Origin': 'https://www.eon.ro',
    'Referer': 'https://www.eon.ro/myline/login',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36',
    'x-client-source': 'mylineWeb',
  };

  final JsonHttp _http = JsonHttp();
  String? _accessToken;
  DateTime? _expiresAt;
  List<Map>? _contracts;

  /// Contractele contului (cod → adresă), cunoscute după [fetchOpenBills].
  final Map<String, String> locations = {};

  bool get hasSession => _accessToken != null;

  Map<String, dynamic>? exportSession() => _accessToken == null
      ? null
      : {
          'accessToken': _accessToken,
          'expiresAt': _expiresAt?.toIso8601String(),
          'cookies': Map<String, String>.from(_http.cookies),
        };

  void restoreSession(Map<String, dynamic>? session) {
    if (session == null) return;
    _accessToken = session['accessToken'] as String?;
    final exp = session['expiresAt'];
    _expiresAt = exp is String ? DateTime.tryParse(exp) : null;
    final cookies = session['cookies'];
    if (cookies is Map) {
      cookies.forEach((k, v) => _http.cookies['$k'] = '$v');
    }
  }

  void _applyToken(Map<String, dynamic> data) {
    final token = data['access_token'] ?? data['accessToken'] ?? data['token'];
    if (token == null) return;
    var raw = token.toString().trim();
    if (raw.toLowerCase().startsWith('bearer ')) raw = raw.substring(7).trim();
    _accessToken = raw;
    final expires = data['expires_in'] ?? data['expiresIn'];
    final seconds = expires is num ? expires.toInt() : 1800;
    _expiresAt = DateTime.now().add(Duration(seconds: seconds));
  }

  /// Aruncă [EonMfaRequired] dacă E.ON cere cod de verificare.
  Future<void> login(String username, String password) async {
    for (final rememberMe in const [true, false]) {
      final resp = await _http.send(
        'POST',
        '$_base/users/v1/userauth/login',
        headers: _headers,
        body: {
          'username': username,
          'password': password,
          'rememberMe': rememberMe,
        },
      );
      final data = resp.map;
      if (resp.status == 200) {
        _applyToken(data);
        if (_accessToken != null) return;
        throw BillFetchException('E.ON: răspuns de logare fără token.');
      }
      final code = '${data['code'] ?? ''}';
      if (resp.status == 400 && code == '6054') {
        throw EonMfaRequired(
          '${data['description'] ?? ''}',
          '${data['secondFactorType'] ?? 'EMAIL'}'.toUpperCase(),
          '${data['secondFactorRecipient'] ?? ''}',
        );
      }
      // Unele conturi resping varianta cu rememberMe=true cu „Bad
      // credentials”; se reîncearcă o dată fără.
      if (resp.status == 400 && code == '6101' && rememberMe) continue;
      if (code == '6101') {
        throw BillFetchException(
          'E.ON: autentificare eșuată. Verifică emailul și parola.',
        );
      }
      throw BillFetchException(
        'E.ON: autentificare eșuată (cod ${resp.status}'
        '${code.isEmpty ? '' : ' / $code'}).',
      );
    }
  }

  Future<void> completeMfa(String uuid, String code) async {
    final resp = await _http.send(
      'POST',
      '$_base/users/v1/second-factor-auth/login',
      headers: _headers,
      body: {'uuid': uuid, 'code': code.trim()},
    );
    if (resp.status == 200) {
      _applyToken(resp.map);
      if (_accessToken != null) return;
    }
    throw BillFetchException('E.ON: codul de verificare nu a fost acceptat.');
  }

  Future<bool> _refresh() async {
    final token = _accessToken;
    if (token == null) return false;
    final resp = await _http.send(
      'POST',
      '$_base/users/v1/userauth/refresh-token',
      headers: {..._headers, 'Referer': 'https://www.eon.ro/myline/dashboard'},
      body: {'token': token},
    );
    final data = resp.map;
    final hasToken =
        data['access_token'] ?? data['accessToken'] ?? data['token'];
    if (resp.status != 200 || hasToken == null) return false;
    _applyToken(data);
    return true;
  }

  /// Asigură o sesiune validă: token salvat, apoi reînnoire, apoi logare
  /// completă (care poate arunca [EonMfaRequired]).
  Future<void> ensureSession(String username, String password) async {
    final exp = _expiresAt;
    if (_accessToken != null &&
        exp != null &&
        exp.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return;
    }
    if (await _refresh()) return;
    _accessToken = null;
    await login(username, password);
  }

  Future<JsonResponse> _get(String url) => _http.send(
    'GET',
    url,
    headers: {..._headers, 'Authorization': 'Bearer $_accessToken'},
  );

  /// Ca [_get], dar la 401 încearcă o reînnoire a tokenului și, dacă nu
  /// merge, o logare completă.
  Future<JsonResponse> _authedGet(
    String url,
    String username,
    String password,
  ) async {
    var resp = await _get(url);
    if (resp.status != 401) return resp;
    if (!await _refresh()) {
      _accessToken = null;
      await login(username, password);
    }
    resp = await _get(url);
    return resp;
  }

  /// Intervalul de index de pe o factură: (index vechi, index nou, tipul
  /// citirii, perioada de consum). Întoarce `null` dacă E.ON nu îl oferă.
  Future<(double?, double?, String, String)?> _invoiceInterval(
    String invoiceNumber,
    String username,
    String password,
  ) async {
    try {
      final resp = await _authedGet(
        '$_base/invoices/v1/invoices/invoice-meter-details/$invoiceNumber',
        username,
        password,
      );
      final details = resp.map['meterDetails'];
      if (resp.status != 200 || details is! List) return null;
      for (final item in details.whereType<Map>()) {
        final from = item['oldIndex'];
        final to = item['newIndex'];
        if ('${from ?? ''}'.isEmpty && '${to ?? ''}'.isEmpty) continue;
        String text(List<String> keys) => keys
            .map((k) => '${item[k] ?? ''}'.trim())
            .firstWhere((v) => v.isNotEmpty, orElse: () => '');
        return (
          '${from ?? ''}'.isEmpty ? null : parseAmount(from),
          '${to ?? ''}'.isEmpty ? null : parseAmount(to),
          text(const [
            'readingType',
            'newIndexType',
            'indexType',
            'readingTypeDescription',
          ]),
          text(const ['consumptionPeriod']),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Contractele contului (o singură cerere per sesiune).
  Future<List<Map>> _fetchContracts(String username, String password) async {
    final cached = _contracts;
    if (cached != null) return cached;
    final resp = await _authedGet(
      '$_base/partners/v2/account-contracts/list',
      username,
      password,
    );
    if (resp.status != 200) {
      throw BillFetchException(
        'E.ON: nu am putut citi contractele (cod ${resp.status}).',
      );
    }
    return _contracts = _asList(resp.body);
  }

  /// Întoarce facturile neachitate de pe toate contractele contului și,
  /// pentru contractele prezente în [since], toate facturile emise după data
  /// respectivă (data ultimei facturi salvate în istoric), chiar dacă sunt
  /// deja achitate la furnizor. Contractele din [skip] nu sunt interogate.
  Future<List<Bill>> fetchOpenBills(
    String username,
    String password, {
    Map<String, DateTime> since = const {},
    Set<String> skip = const {},
  }) async {
    await ensureSession(username, password);

    final contracts = await _fetchContracts(username, password);
    final bills = <Bill>[];
    final seen = <String>{};
    final now = DateTime.now();

    Future<void> add(Map item, String code, String address, bool open) async {
      final issued = parseAmount(item['issuedValue']);
      final rest = !open
          ? issued
          : item.containsKey('balanceValue')
          ? parseAmount(item['balanceValue'])
          : issued;
      if (rest <= 0) return;
      final number = '${item['invoiceNumber'] ?? item['fiscalNumber'] ?? ''}'
          .trim();
      final id = Bill.buildId(
        BillProvider.eon,
        code,
        number.isEmpty ? '${item['maturityDate'] ?? ''}' : number,
      );
      if (!seen.add(id)) return;
      final interval = number.isEmpty
          ? null
          : await _invoiceInterval(number, username, password);
      bills.add(
        Bill(
          id: id,
          provider: BillProvider.eon,
          contractCode: code,
          address: address,
          invoiceNumber: number,
          amount: issued > 0 ? issued : rest,
          balance: rest,
          issueDate: parseBillDate(item['emissionDate']),
          dueDate: parseBillDate(item['maturityDate']),
          fetchedAt: now,
          openAtProvider: open,
          indexFrom: interval?.$1,
          indexTo: interval?.$2,
          readingType: interval?.$3 ?? '',
          indexPeriod: interval?.$4 ?? '',
        ),
      );
    }

    for (final contract in contracts) {
      final code = '${contract['accountContract'] ?? ''}'.trim();
      if (code.isEmpty) continue;
      final address = _address(contract['consumptionPointAddress']);
      locations[code] = address;
      if (skip.contains(code)) continue;

      final invResp = await _authedGet(
        '$_base/invoices/v1/invoices/list?accountContract=$code&status=unpaid',
        username,
        password,
      );
      if (invResp.status != 200) {
        throw BillFetchException(
          'E.ON: nu am putut citi facturile pentru $code '
          '(cod ${invResp.status}).',
        );
      }
      for (final item in _asList(invResp.body)) {
        await add(item, code, address, true);
      }

      final from = since[code];
      if (from == null) continue;
      // Facturile achitate vin paginat, cele mai noi primele; ne oprim la
      // prima pagină fără nicio factură mai nouă decât [from].
      for (var page = 1; page <= 6; page++) {
        final paidResp = await _authedGet(
          '$_base/invoices/v1/invoices/list-paid'
          '?accountContract=$code&status=paid&page=$page',
          username,
          password,
        );
        if (paidResp.status != 200) break;
        final items = _asList(paidResp.body);
        var anyNewer = false;
        for (final item in items) {
          final issued = parseBillDate(item['emissionDate']);
          if (issued == null || !issued.isAfter(from)) continue;
          anyNewer = true;
          await add(item, code, address, false);
        }
        if (!anyNewer || paidResp.map['hasNext'] != true) break;
      }
    }
    return bills;
  }

  /// PDF-ul unei facturi, sau `null` dacă E.ON nu îl oferă. Poate arunca
  /// [EonMfaRequired] dacă sesiunea a expirat.
  Future<Uint8List?> fetchInvoicePdf(
    String invoiceNumber,
    String username,
    String password,
  ) async {
    await ensureSession(username, password);
    final resp = await _authedGet(
      '$_base/invoices/v1/invoices/$invoiceNumber/pdf',
      username,
      password,
    );
    return resp.status == 200 ? findPdf(resp) : null;
  }

  void close() => _http.close();

  static List<Map> _asList(dynamic body) {
    if (body is List) return body.whereType<Map>().toList();
    if (body is Map && body['list'] is List) {
      return (body['list'] as List).whereType<Map>().toList();
    }
    return const [];
  }

  static String _address(dynamic a) {
    if (a is String) return a.trim();
    if (a is! Map) return '';
    final parts = <String>[];
    final street = a['street'];
    if (street is Map) {
      final type = street['streetType'];
      final label = type is Map ? '${type['label'] ?? ''}'.trim() : '';
      final name = '${street['streetName'] ?? ''}'.trim();
      final nr = '${a['streetNumber'] ?? ''}'.trim();
      final full = [label, name, nr].where((s) => s.isNotEmpty).join(' ');
      if (full.isNotEmpty) parts.add(full);
    }
    final ap = '${a['apartment'] ?? ''}'.trim();
    if (ap.isNotEmpty && ap != '0') parts.add('ap. $ap');
    final locality = a['locality'];
    if (locality is Map) {
      final city = '${locality['localityName'] ?? ''}'.split('(').first.trim();
      if (city.isNotEmpty) parts.add(city);
    }
    return parts.join(', ');
  }
}
