import 'dart:convert';

import '../models/bill.dart';
import 'bill_http.dart';

/// Preia soldul facturilor din contul Hidroelectrica (iHidro), prin API-ul
/// folosit de aplicația lor de mobil. Autentificarea are doi pași: `GetId`
/// (chei temporare) și `ValidateUserLogin` (UserID + SessionToken).
class HidroelectricaApi {
  static const _base = 'https://hidroelectrica-svc.smartcmobile.com';
  static const _userAgent = 'okhttp/4.9.0';

  final JsonHttp _http = JsonHttp();
  String? _userId;
  String? _sessionToken;

  Map<String, String> _headers(String sourceType, String user, String secret) =>
      {
        'SourceType': sourceType,
        'User-Agent': _userAgent,
        'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$secret'))}',
      };

  Future<void> login(String username, String password) async {
    final idResp = await _http.send(
      'POST',
      '$_base/API/UserLogin/GetId',
      headers: const {'SourceType': '0', 'User-Agent': _userAgent},
      body: const <String, dynamic>{},
    );
    final idData = _data(idResp);
    final key = idData['key']?.toString() ?? '';
    final tokenId = idData['tokenId']?.toString() ?? '';
    if (idResp.status != 200 || key.isEmpty || tokenId.isEmpty) {
      throw BillFetchException(
        'Hidroelectrica: serverul nu a pornit autentificarea '
        '(cod ${idResp.status}).',
      );
    }

    final now = _stamp(DateTime.now());
    final loginResp = await _http.send(
      'POST',
      '$_base/API/UserLogin/ValidateUserLogin',
      headers: _headers('0', key, tokenId),
      body: {
        'deviceType': 'MobileApp',
        'OperatingSystem': 'Android',
        'UpdatedDate': now,
        'Deviceid': '',
        'SessionCode': '',
        'LanguageCode': 'RO',
        'password': password,
        'UserId': username,
        'TFADeviceid': '',
        'OSVersion': 14,
        'TimeOffSet': '120',
        'LUpdHideShow': now,
        'Browser': 'NA',
      },
    );
    final table = _data(loginResp)['Table'];
    final row = table is List && table.isNotEmpty && table.first is Map
        ? table.first as Map
        : const {};
    _userId = row['UserID']?.toString();
    _sessionToken = row['SessionToken']?.toString();
    if ((_userId ?? '').isEmpty || (_sessionToken ?? '').isEmpty) {
      _userId = null;
      _sessionToken = null;
      throw BillFetchException(
        'Hidroelectrica: autentificare eșuată. Verifică utilizatorul și '
        'parola.',
      );
    }
  }

  Future<JsonResponse> _post(String path, Map<String, dynamic> body) =>
      _http.send(
        'POST',
        '$_base$path',
        headers: _headers('1', _userId!, _sessionToken!),
        body: body,
      );

  /// Întoarce câte o factură pentru fiecare loc de consum care are sold de
  /// plată. Apelează [login] înainte.
  Future<List<Bill>> fetchOpenBills() async {
    final settings = await _post('/API/UserLogin/GetUserSetting', {
      'UserID': _userId,
    });
    if (settings.status != 200) {
      throw BillFetchException(
        'Hidroelectrica: nu am putut citi locurile de consum '
        '(cod ${settings.status}).',
      );
    }
    final data = _data(settings);
    final seen = <String>{};
    final bills = <Bill>[];
    final now = DateTime.now();

    for (final tableKey in const ['Table1', 'Table2']) {
      final rows = data[tableKey];
      if (rows is! List) continue;
      for (final entry in rows.whereType<Map>()) {
        final uan = (entry['UtilityAccountNumber'] ?? '').toString().trim();
        if (uan.isEmpty || !seen.add(uan)) continue;

        final billResp = await _post('/Service/Billing/GetBill', {
          'LanguageCode': 'RO',
          'UserID': _userId,
          'IsBillPDF': '0',
          'UtilityAccountNumber': uan,
          'AccountNumber': (entry['AccountNumber'] ?? '').toString(),
        });
        if (billResp.status != 200) {
          throw BillFetchException(
            'Hidroelectrica: nu am putut citi factura pentru $uan '
            '(cod ${billResp.status}).',
          );
        }
        final result = billResp.map['result'];
        if (result is! Map) continue;
        final balance = parseAmount(result['rembalance']);
        if (balance <= 0) continue;

        final invoiceNumber = (result['invoicenumber'] ?? '').toString().trim();
        final amount = parseAmount(result['billamount']);
        bills.add(
          Bill(
            id: Bill.buildId(BillProvider.hidroelectrica, uan, invoiceNumber),
            provider: BillProvider.hidroelectrica,
            contractCode: uan,
            address: (entry['Address'] ?? '').toString().trim(),
            invoiceNumber: invoiceNumber,
            amount: amount > 0 ? amount : balance,
            balance: balance,
            dueDate: parseBillDate(result['duedate']),
            fetchedAt: now,
          ),
        );
      }
    }
    return bills;
  }

  void close() => _http.close();

  static Map<String, dynamic> _data(JsonResponse r) {
    final result = r.map['result'];
    final data = result is Map ? result['Data'] : null;
    return data is Map ? Map<String, dynamic>.from(data) : const {};
  }

  static String _stamp(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.month)}/${two(d.day)}/${d.year} '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }
}
