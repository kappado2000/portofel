import 'package:intl/intl.dart';

import '../models/account.dart';
import '../models/bill.dart';

final _ronFormat = NumberFormat.currency(
  locale: 'ro_RO',
  symbol: 'lei',
  decimalDigits: 2,
);
final _eurFormat = NumberFormat.currency(
  locale: 'ro_RO',
  symbol: '€',
  decimalDigits: 2,
);
final _numberFormat = NumberFormat('#,##0.00', 'ro_RO');
final indexFormat = NumberFormat('#,##0', 'ro_RO');
final dateFormat = DateFormat('dd.MM.yyyy');
final dateTimeFormat = DateFormat('dd.MM.yyyy HH:mm');

String formatAmount(double amount, AccountCurrency currency) {
  return currency == AccountCurrency.ron
      ? _ronFormat.format(amount)
      : _eurFormat.format(amount);
}

/// Formatează o sumă cu separator de mii (punct) și 2 zecimale, fără
/// simbol de valută — pentru locurile unde valuta e adăugată manual alături.
String formatNumber(double amount) => _numberFormat.format(amount);

String currencyLabel(AccountCurrency c) =>
    c == AccountCurrency.ron ? 'RON' : 'EUR';

/// Textul cu intervalul de index facturat, sau `null` dacă nu e cunoscut.
String? billIndexLine(Bill bill) {
  final to = bill.indexTo;
  final from = bill.indexFrom;
  if (to == null && from == null) return null;
  String n(double v) =>
      v == v.roundToDouble() ? indexFormat.format(v) : formatNumber(v);
  final range = from != null && to != null
      ? 'Index ${n(from)} → ${n(to)}'
      : 'Index ${n((to ?? from)!)}';
  final extra = [
    if (bill.readingType.isNotEmpty) bill.readingType.toLowerCase(),
    if (bill.indexPeriod.isNotEmpty) bill.indexPeriod,
  ].join(', ');
  return extra.isEmpty ? range : '$range ($extra)';
}

/// „Factura din data de … scadentă la …”, cu părțile cunoscute.
String billDatesLine(Bill bill) {
  final issued = bill.issueDate;
  final due = bill.dueDate;
  return [
    issued == null
        ? 'Factura'
        : 'Factura din data de ${dateFormat.format(issued)}',
    if (due != null) 'scadentă la ${dateFormat.format(due)}',
  ].join(' ');
}
