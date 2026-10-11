import 'package:flutter/material.dart';

import '../models/account.dart';
import '../models/bill.dart';

/// Gradient de fundal pentru cardul unui cont, pe baza tipului/valutei —
/// mai viu decât un fundal neutru plat, dar suficient de aproape de
/// culoarea originală (indigo/teal/maro) încât identitatea vizuală pe tip
/// de cont rămâne recognoscibilă.
LinearGradient accountCardGradient(Account account) {
  final isBank = account.kind == AccountKind.bank;
  final isEur = account.currency == AccountCurrency.eur;
  final List<Color> colors = isBank
      ? (isEur
            ? [Colors.red.shade400, Colors.deepPurple.shade600]
            : [Colors.indigo.shade300, Colors.indigo.shade600])
      : (isEur
            ? [Colors.teal.shade300, Colors.teal.shade600]
            : [Colors.orange.shade300, Colors.orange.shade700]);
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: colors,
  );
}

/// Gradient "hero" pentru cardurile de total (Total estimat, Total
/// familie, soldul unui cont) — aceeași pereche de culori peste tot, ca
/// toate să se simtă parte din același sistem vizual.
const heroCardGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF00897B), Color(0xFF3949AB)],
);

BoxDecoration heroCardDecoration({double radius = 20}) => BoxDecoration(
  gradient: heroCardGradient,
  borderRadius: BorderRadius.circular(radius),
  boxShadow: [
    BoxShadow(
      color: const Color(0xFF3949AB).withValues(alpha: 0.25),
      blurRadius: 12,
      offset: const Offset(0, 6),
    ),
  ],
);

/// Paleta unui furnizor de utilități, derivată pentru tema curentă, ca
/// secțiunile lor să se deosebească dintr-o privire. Roșul rămâne rezervat
/// restanțelor.
ColorScheme billProviderScheme(BuildContext context, BillProvider provider) =>
    ColorScheme.fromSeed(
      seedColor: switch (provider) {
        BillProvider.hidroelectrica => const Color(0xFF1565C0),
        BillProvider.eon => const Color(0xFFEF6C00),
        BillProvider.electrica => const Color(0xFF2E7D32),
      },
      brightness: Theme.of(context).brightness,
    );

/// Culorile cardului unui furnizor: titlu închis, corp deschis în aceeași
/// nuanță — albastru la Hidroelectrica, portocaliu la E.ON, verde la
/// Electrica.
class BillCardColors {
  /// Fundalul titlului (nuanța închisă) și culoarea accentelor.
  final Color header;

  /// Textul de pe titlu.
  final Color onHeader;

  /// Fundalul restului cardului (nuanța deschisă).
  final Color body;

  /// Fundalul antetelor de adresă, între cele două.
  final Color strip;

  const BillCardColors(this.header, this.onHeader, this.body, this.strip);
}

BillCardColors billCardColors(BuildContext context, BillProvider provider) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (provider) {
    BillProvider.hidroelectrica =>
      dark
          ? const BillCardColors(
              Color(0xFF0D47A1),
              Colors.white,
              Color(0xFF13233F),
              Color(0xFF1B3560),
            )
          : const BillCardColors(
              Color(0xFF0D47A1),
              Colors.white,
              Color(0xFFDCEBFF),
              Color(0xFFBBD6FA),
            ),
    BillProvider.eon =>
      dark
          ? const BillCardColors(
              Color(0xFFD84315),
              Colors.white,
              Color(0xFF3A1F10),
              Color(0xFF57301A),
            )
          : const BillCardColors(
              Color(0xFFD84315),
              Colors.white,
              Color(0xFFFFE9D9),
              Color(0xFFFFD2B3),
            ),
    BillProvider.electrica =>
      dark
          ? const BillCardColors(
              Color(0xFF1B5E20),
              Colors.white,
              Color(0xFF14301A),
              Color(0xFF1F4A27),
            )
          : const BillCardColors(
              Color(0xFF1B5E20),
              Colors.white,
              Color(0xFFDDF2DE),
              Color(0xFFBFE3C1),
            ),
  };
}

/// Fundalul paginilor de facturi: galben pal (în tema luminoasă).
Color? billsPageBackground(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? null
    : const Color(0xFFFFF8DC);
