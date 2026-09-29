import 'package:flutter/material.dart';
import '../models/account.dart';

/// Gradient de fundal pentru cardul unui cont, pe baza tipului/valutei —
/// mai viu decât un fundal neutru plat, dar suficient de aproape de
/// culoarea originală (indigo/teal/maro) încât identitatea vizuală pe tip
/// de cont rămâne recognoscibilă.
LinearGradient accountCardGradient(Account account) {
  final isBank = account.kind == AccountKind.bank;
  final isEur = account.currency == AccountCurrency.eur;
  final List<Color> colors = isBank
      ? [Colors.indigo.shade300, Colors.indigo.shade600]
      : (isEur
          ? [Colors.teal.shade300, Colors.teal.shade600]
          : [Colors.brown.shade300, Colors.brown.shade600]);
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
