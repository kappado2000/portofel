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

  /// Locurile de consum ale contului (cod → adresă), cunoscute după
  /// [fetchOpenBills].
  final Map<String, String> locations = {};
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
    // Fără interval de date, serverul întoarce un istoric gol.
    final now = DateTime.now();
    String day(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    try {
      final resp = await _post('/Service/Billing/GetBillingHistoryList', {
        'LanguageCode': 'RO',
        'UserID': _userId,
        'UtilityAccountNumber': (entry['UtilityAccountNumber'] ?? '')
            .toString()
            .trim(),
        'AccountNumber': (entry['AccountNumber'] ?? '').toString(),
        'FromDate': day(now.subtract(const Duration(days: 730))),
        'ToDate': day(now),
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

  /// „176,Mihai Viteazul,REGHIN,MS,545300” → „Mihai Viteazul 176, Reghin”.
  static String _address(dynamic raw) {
    final text = '${raw ?? ''}'.trim();
    final parts = text.split(',').map((p) => p.trim()).toList();
    if (parts.length < 3 || parts[1].isEmpty) return text;
    String cap(String v) => v
        .toLowerCase()
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
    final street = [parts[1], parts[0]].where((p) => p.isNotEmpty).join(' ');
    return '$street, ${cap(parts[2])}';
  }

  /// Un număr de factură afișabil: doar litere și cifre, altfel [fallback].
  static String _readable(String number, {String fallback = ''}) {
    final n = number.trim();
    return RegExp(r'^[A-Za-z0-9 ./-]{1,24}$').hasMatch(n) ? n : fallback;
  }

  static String _invoiceKey(dynamic number) =>
      '${number ?? ''}'.trim().replaceFirst(RegExp(r'^0+'), '');

  /// Întoarce facturile fiecărui loc de consum: cea cu sold de plată și,
  /// pentru locurile de consum prezente în [since], toate facturile emise
  /// după data respectivă (data ultimei facturi salvate în istoric), chiar
  /// dacă sunt deja achitate la furnizor. Apelează [login] înainte.
  ///
  /// Locurile de consum din [skip] nu sunt interogate.
  Future<List<Bill>> fetchOpenBills({
    Map<String, DateTime> since = const {},
    DateTime? sinceDefault,
    Set<String> skip = const {},
  }) async {
    final bills = <Bill>[];
    final now = DateTime.now();

    for (final entry in await _fetchAccounts()) {
      final uan = (entry['UtilityAccountNumber'] ?? '').toString().trim();
      final address = _address(entry['Address']);
      locations[uan] = address;
      if (skip.contains(uan)) continue;
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

      // Dacă nici așa nu se regăsește, factura cu sold e cea mai recentă.
      if (currentInHistory == null && balance > 0 && history.isNotEmpty) {
        currentInHistory = history.reduce(
          (a, b) =>
              (parseBillDate(b['invoiceDate']) ?? DateTime(0)).isAfter(
                parseBillDate(a['invoiceDate']) ?? DateTime(0),
              )
              ? b
              : a,
        );
      }
      // GetBill întoarce numărul facturii codat; cel lizibil e în istoric.
      final shownNumber = _readable(
        '${currentInHistory?['exbel'] ?? currentInHistory?['invoiceId'] ?? ''}',
        fallback: _readable(currentNumber),
      );

      final accountBills = <Bill>[];
      if (balance > 0) {
        accountBills.add(
          Bill(
            id: Bill.buildId(BillProvider.hidroelectrica, uan, currentNumber),
            provider: BillProvider.hidroelectrica,
            contractCode: uan,
            address: address,
            invoiceNumber: shownNumber,
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

      final from = since[uan] ?? sinceDefault;
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

  /// PDF-ul unei facturi, căutat după numărul ei ([invoiceNumber], cel din
  /// istoricul de facturare). Întoarce `null` dacă nu se găsește.
  ///
  /// TEMPORAR: parametrul exact cerut de `GetBillPDF` nu e cunoscut, așa că
  /// se încearcă pe rând mai multe variante, iar [log] reține ce a răspuns
  /// serverul la fiecare (formă, nu conținut). Apelează [login] înainte.
  Future<Uint8List?> fetchBillPdf(
    String contractCode,
    String invoiceNumber,
    StringBuffer log,
  ) async {
    log.writeln('PDF Hidroelectrica ${DateTime.now()} factura=$invoiceNumber');
    final entry = (await _fetchAccounts())
        .where(
          (e) =>
              (e['UtilityAccountNumber'] ?? '').toString().trim() ==
              contractCode,
        )
        .firstOrNull;
    if (entry == null) {
      log.writeln('loc de consum negăsit');
      return null;
    }
    final base = <String, dynamic>{
      'LanguageCode': 'RO',
      'UserID': _userId,
      'UtilityAccountNumber': contractCode,
      'AccountNumber': (entry['AccountNumber'] ?? '').toString(),
      'IsBillPDF': '1',
    };

    final row = (await _billingHistory(entry))
        .where(
          (h) =>
              invoiceNumber.isNotEmpty &&
              _invoiceKey(h['exbel']) == _invoiceKey(invoiceNumber),
        )
        .firstOrNull;
    final encrypted = '${row?['invoiceId'] ?? ''}';
    final exbel = '${row?['exbel'] ?? invoiceNumber}';
    log.writeln(
      'în istoric: ${row != null}, invoiceId len=${encrypted.length}, '
      'exbel=$exbel',
    );

    void describe(String indent, dynamic node, int depth) {
      if (node is Map) {
        node.forEach((k, v) {
          if (v is Map || v is List) {
            out(log, '$indent$k: ${v is Map ? 'Map' : 'List'}');
            if (depth < 4) {
              describe(
                '$indent  ',
                v is List ? (v.isEmpty ? null : v.first) : v,
                depth + 1,
              );
            }
          } else {
            final text = '$v';
            final short = text.length <= 60
                ? text
                : '${text.substring(0, 24)}…';
            out(log, '$indent$k: ${v.runtimeType} len=${text.length} "$short"');
          }
        });
      }
    }

    Future<Uint8List?> attempt(String label, Map<String, dynamic> extra) async {
      log.writeln('\n== $label');
      try {
        final r = await _post('/Service/Billing/GetBillPDF', {
          ...base,
          ...extra,
        });
        var pdf = r.status == 200 ? findPdf(r) : null;
        // Răspunsul poate conține doar adresa fișierului.
        final url = pdf == null ? _findUrl(r.body) : null;
        if (url != null) {
          log.writeln('url găsit: ${Uri.tryParse(url)?.path}');
          final file = await _http.send('GET', url);
          pdf = findPdf(file);
        }
        log.writeln(
          'status=${r.status} bytes=${r.bytes.length} pdf=${pdf != null}',
        );
        final result = r.map['result'] ?? r.map['error'];
        describe('  ', result, 0);
        return pdf;
      } on BillFetchException catch (e) {
        log.writeln('eroare: $e');
        return null;
      }
    }

    final attempts = <(String, Map<String, dynamic>)>[
      if (encrypted.isNotEmpty)
        for (final key in const [
          'InvoiceId',
          'invoiceId',
          'BillingId',
          'InvoiceNumber',
          'BillId',
          'EncQuery',
        ])
          ('$key=invoiceId', {key: encrypted}),
      for (final key in const [
        'exbel',
        'InvoiceNumber',
        'InvoiceId',
        'BillingId',
        'BillNumber',
      ])
        ('$key=exbel', {key: exbel}),
    ];
    for (final (label, extra) in attempts) {
      final pdf = await attempt(label, extra);
      if (pdf != null) {
        log.writeln('\nREUȘIT cu: $label');
        return pdf;
      }
    }
    log.writeln('\nnicio variantă nu a întors PDF');
    return null;
  }

  static void out(StringBuffer log, String line) => log.writeln(line);

  /// Prima adresă web dintr-un răspuns JSON, dacă există.
  static String? _findUrl(dynamic node) {
    if (node is String) {
      final text = node.trim();
      return text.startsWith('http') && !text.contains(' ') ? text : null;
    }
    final children = node is Map
        ? node.values
        : node is List
        ? node
        : const [];
    for (final child in children) {
      final found = _findUrl(child);
      if (found != null) return found;
    }
    return null;
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
