import 'dart:convert';
import 'dart:typed_data';

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
  List<Map>? _accounts;
  final Map<String, List<Map>> _history = {};

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

  /// Facturile emise pentru un loc de consum, din istoricul de facturare.
  /// Întoarce o listă goală dacă istoricul nu poate fi citit.
  Future<List<Map>> _billingHistory(Map entry) async {
    try {
      final resp = await _post('/Service/Billing/GetBillingHistoryList', {
        'LanguageCode': 'RO',
        'UserID': _userId,
        'UtilityAccountNumber': (entry['UtilityAccountNumber'] ?? '')
            .toString()
            .trim(),
        'AccountNumber': (entry['AccountNumber'] ?? '').toString(),
        'FromDate': '',
        'ToDate': '',
      });
      final result = resp.map['result'];
      if (resp.status != 200 || result is! Map) return const [];
      final list = result['objBillingHistoryEntity'];
      if (list is List) return list.whereType<Map>().toList();
      return _dataList(resp, 'objBillingHistoryData');
    } on BillFetchException {
      return const [];
    }
  }

  static String _invoiceKey(dynamic number) =>
      '${number ?? ''}'.trim().replaceFirst(RegExp(r'^0+'), '');

  /// Întoarce facturile fiecărui loc de consum: cea cu sold de plată și,
  /// pentru locurile de consum prezente în [since], toate facturile emise
  /// după data respectivă (data ultimei facturi salvate în istoric), chiar
  /// dacă sunt deja achitate la furnizor. Apelează [login] înainte.
  Future<List<Bill>> fetchOpenBills({
    Map<String, DateTime> since = const {},
  }) async {
    final bills = <Bill>[];
    final now = DateTime.now();

    for (final entry in await _fetchAccounts()) {
      final uan = (entry['UtilityAccountNumber'] ?? '').toString().trim();
      final address = (entry['Address'] ?? '').toString().trim();
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
      final current = result is Map ? result : const {};
      final balance = parseAmount(current['rembalance']);
      final currentNumber = (current['invoicenumber'] ?? '').toString().trim();
      final currentAmount = parseAmount(current['billamount']);

      final history = await _billingHistory(entry);
      // Factura curentă, regăsită în istoric: după număr sau, dacă numerele
      // au alt format, după sumă.
      Map? currentInHistory = history
          .where(
            (h) =>
                currentNumber.isNotEmpty &&
                (_invoiceKey(h['exbel']) == _invoiceKey(currentNumber) ||
                    _invoiceKey(h['invoiceId']) == _invoiceKey(currentNumber)),
          )
          .firstOrNull;
      currentInHistory ??= history
          .where(
            (h) =>
                currentAmount > 0 && parseAmount(h['amount']) == currentAmount,
          )
          .firstOrNull;

      final accountBills = <Bill>[];
      if (balance > 0) {
        accountBills.add(
          Bill(
            id: Bill.buildId(BillProvider.hidroelectrica, uan, currentNumber),
            provider: BillProvider.hidroelectrica,
            contractCode: uan,
            address: address,
            invoiceNumber: currentNumber,
            amount: currentAmount > 0 ? currentAmount : balance,
            balance: balance,
            issueDate: parseBillDate(currentInHistory?['invoiceDate']),
            dueDate:
                parseBillDate(current['duedate']) ??
                parseBillDate(currentInHistory?['dueDate']),
            fetchedAt: now,
          ),
        );
      }

      final from = since[uan];
      if (from != null) {
        for (final h in history) {
          if (identical(h, currentInHistory) && balance > 0) continue;
          final issued = parseBillDate(h['invoiceDate']);
          final amount = parseAmount(h['amount']);
          if (issued == null || !issued.isAfter(from) || amount <= 0) continue;
          final number = '${h['exbel'] ?? h['invoiceId'] ?? ''}'.trim();
          final id = Bill.buildId(
            BillProvider.hidroelectrica,
            uan,
            identical(h, currentInHistory) && currentNumber.isNotEmpty
                ? currentNumber
                : number,
          );
          if (accountBills.any((b) => b.id == id)) continue;
          accountBills.add(
            Bill(
              id: id,
              provider: BillProvider.hidroelectrica,
              contractCode: uan,
              address: address,
              invoiceNumber: number,
              amount: amount,
              balance: amount,
              issueDate: issued,
              dueDate: parseBillDate(h['dueDate']),
              fetchedAt: now,
              openAtProvider: false,
            ),
          );
        }
      }

      // Intervalul de index e cunoscut doar pentru cele mai recente citiri,
      // deci se atașează celei mai noi facturi.
      if (accountBills.isNotEmpty) {
        final newest = accountBills.reduce(
          (a, b) =>
              (b.issueDate ?? DateTime(0)).isAfter(a.issueDate ?? DateTime(0))
              ? b
              : a,
        );
        final target = balance > 0 && accountBills.first.issueDate == null
            ? accountBills.first
            : newest;
        final interval = await _lastInterval(entry);
        if (interval != null) {
          target
            ..indexFrom = interval.$1
            ..indexTo = interval.$2
            ..readingType = interval.$3
            ..indexPeriod = interval.$4;
        }
      }
      bills.addAll(accountBills);
    }
    return bills;
  }

  /// Istoricul citirilor unui loc de consum (o singură cerere per sesiune).
  Future<List<Map>> _readHistory(Map entry) async {
    final uan = (entry['UtilityAccountNumber'] ?? '').toString().trim();
    final cached = _history[uan];
    if (cached != null) return cached;

    final podsResp = await _post('/Service/SelfMeterReading/GetPods', {
      'MeterType': 'E',
      'UserID': _userId,
      'UtilityAccountNumber': uan,
      'AccountNumber': (entry['AccountNumber'] ?? '').toString(),
    });
    final pods = _dataList(podsResp, 'objPodData');
    if (pods.isEmpty) return _history[uan] = const [];
    final installation = '${pods.first['installation'] ?? ''}'.trim();
    final pod = '${pods.first['pod'] ?? pods.first['podValue'] ?? ''}'.trim();
    if (installation.isEmpty || pod.isEmpty) return _history[uan] = const [];

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
    return _history[uan] = _dataList(historyResp, 'objMeterReadHistoryData')
        .where((r) => parseBillDate(r['Date']) != null && r['Index'] != null)
        .toList();
  }

  /// Ultimele două citiri ale registrului de consum: (index vechi, index
  /// nou, tipul ultimei citiri, perioada). Hidroelectrica nu leagă citirile
  /// de o factură anume, deci acesta e intervalul cel mai recent, nu neapărat
  /// exact cel de pe factură. Întoarce `null` dacă nu poate fi determinat.
  Future<(double?, double, String, String)?> _lastInterval(Map entry) async {
    try {
      final rows = (await _readHistory(entry))
          .where((r) => !'${r['Registers'] ?? ''}'.endsWith('_P'))
          .toList();
      if (rows.isEmpty) return null;
      rows.sort(
        (a, b) =>
            parseBillDate(b['Date'])!.compareTo(parseBillDate(a['Date'])!),
      );
      final last = rows.first;
      final previous = rows
          .skip(1)
          .where(
            (r) =>
                r['Registers'] == last['Registers'] &&
                r['CounterSeries'] == last['CounterSeries'] &&
                parseBillDate(r['Date'])!
                    .isBefore(parseBillDate(last['Date'])!),
          )
          .firstOrNull;
      String day(Map r) {
        final d = parseBillDate(r['Date'])!;
        String two(int v) => v.toString().padLeft(2, '0');
        return '${two(d.day)}.${two(d.month)}.${d.year}';
      }

      return (
        previous == null ? null : parseAmount(previous['Index']),
        parseAmount(last['Index']),
        '${last['ReadingType'] ?? ''}'.trim(),
        previous == null ? day(last) : '${day(previous)} – ${day(last)}',
      );
    } catch (_) {
      return null;
    }
  }

  /// PDF-ul facturii curente a unui loc de consum, sau `null` dacă
  /// Hidroelectrica nu îl oferă. Apelează [login] înainte.
  Future<Uint8List?> fetchCurrentBillPdf(String contractCode) async {
    final entry = (await _fetchAccounts())
        .where(
          (e) =>
              (e['UtilityAccountNumber'] ?? '').toString().trim() ==
              contractCode,
        )
        .firstOrNull;
    if (entry == null) return null;
    final resp = await _post('/Service/Billing/GetBill', {
      'LanguageCode': 'RO',
      'UserID': _userId,
      'IsBillPDF': '1',
      'UtilityAccountNumber': contractCode,
      'AccountNumber': (entry['AccountNumber'] ?? '').toString(),
    });
    return resp.status == 200 ? findPdf(resp) : null;
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
