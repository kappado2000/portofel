import 'package:intl/intl.dart';
import '../models/account.dart';

final _ronFormat = NumberFormat.currency(locale: 'ro_RO', symbol: 'lei', decimalDigits: 2);
final _eurFormat = NumberFormat.currency(locale: 'ro_RO', symbol: '€', decimalDigits: 2);
final _numberFormat = NumberFormat('#,##0.00', 'ro_RO');
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

String currencyLabel(AccountCurrency c) => c == AccountCurrency.ron ? 'RON' : 'EUR';
