import 'dart:convert';

import '../models/bill.dart';
import '../models/meter_reading.dart';
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
  List<Map>? _accounts;

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

  /// Locurile de consum ale contului (o singură cerere per sesiune).
  Future<List<Map>> _fetchAccounts() async {
    final cached = _accounts;
    if (cached != null) return cached;
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
    final accounts = <Map>[];
    for (final tableKey in const ['Table1', 'Table2']) {
      final rows = data[tableKey];
      if (rows is! List) continue;
      for (final entry in rows.whereType<Map>()) {
        final uan = (entry['UtilityAccountNumber'] ?? '').toString().trim();
        if (uan.isNotEmpty && seen.add(uan)) accounts.add(entry);
      }
    }
    return _accounts = accounts;
  }

  /// Întoarce câte o factură pentru fiecare loc de consum care are sold de
  /// plată. Apelează [login] înainte.
  Future<List<Bill>> fetchOpenBills() async {
    final bills = <Bill>[];
    final now = DateTime.now();

    for (final entry in await _fetchAccounts()) {
      final uan = (entry['UtilityAccountNumber'] ?? '').toString().trim();
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
    return bills;
  }

  /// Întoarce ultimul index înregistrat pentru fiecare registru de contor
  /// (consum și, la prosumatori, producție). Apelează [login] înainte.
  Future<List<MeterReading>> fetchMeterReadings() async {
    final readings = <MeterReading>[];

    for (final entry in await _fetchAccounts()) {
      final uan = (entry['UtilityAccountNumber'] ?? '').toString().trim();
      final podsResp = await _post('/Service/SelfMeterReading/GetPods', {
        'MeterType': 'E',
        'UserID': _userId,
        'UtilityAccountNumber': uan,
        'AccountNumber': (entry['AccountNumber'] ?? '').toString(),
      });
      final pods = _dataList(podsResp, 'objPodData');
      if (pods.isEmpty) continue;
      final installation = '${pods.first['installation'] ?? ''}'.trim();
      final pod = '${pods.first['pod'] ?? pods.first['podValue'] ?? ''}'.trim();
      if (installation.isEmpty || pod.isEmpty) continue;

      final historyResp = await _post(
        '/Service/IndexHistory/GetMeterReadHistory',
        {
          'utilityAccountNumber': uan,
          'podValue': pod,
          'LanguageCode': 'RO',
          'InstallationNumber': installation,
          'SerialNumber': const <String>[],
        },
      );
      // Cea mai recentă citire pentru fiecare registru.
      final latest = <String, (DateTime, Map)>{};
      for (final row in _dataList(historyResp, 'objMeterReadHistoryData')) {
        final date = parseBillDate(row['Date']);
        if (date == null || row['Index'] == null) continue;
        final register = '${row['Registers'] ?? ''}';
        final current = latest[register];
        if (current == null || date.isAfter(current.$1)) {
          latest[register] = (date, row);
        }
      }
      for (final item in latest.values) {
        final row = item.$2;
        readings.add(
          MeterReading(
            provider: BillProvider.hidroelectrica,
            contractCode: uan,
            address: (entry['Address'] ?? '').toString().trim(),
            meterNumber: '${row['CounterSeries'] ?? ''}'.trim(),
            label: '${row['RegisterDescription'] ?? ''}'.trim(),
            value: parseAmount(row['Index']),
            date: item.$1,
          ),
        );
      }
    }
    return readings;
  }

  void close() => _http.close();

  static Map<String, dynamic> _data(JsonResponse r) {
    final result = r.map['result'];
    final data = result is Map ? result['Data'] : null;
    return data is Map ? Map<String, dynamic>.from(data) : const {};
  }

  /// `result.Data` ca listă — direct sau sub cheia [key].
  static List<Map> _dataList(JsonResponse r, String key) {
    final result = r.map['result'];
    final data = result is Map ? result['Data'] : null;
    final list = data is Map ? data[key] : data;
    return list is List ? list.whereType<Map>().toList() : const [];
  }

  static String _stamp(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.month)}/${two(d.day)}/${d.year} '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }
}
