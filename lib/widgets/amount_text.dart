import 'package:flutter/material.dart';

/// Afișează o sumă deja formatată (ex: "1.234,56 lei") cu partea de
/// zecimale (virgulă + 2 cifre + simbol valută) într-un font mai mic decât
/// partea întreagă, ca în aplicațiile bancare.
class AmountText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final double decimalScale;
  final TextAlign? textAlign;

  const AmountText(
    this.text, {
    super.key,
    this.style,
    this.decimalScale = 0.7,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = DefaultTextStyle.of(context).style.merge(style);
    final idx = text.lastIndexOf(',');
    if (idx == -1) {
      return Text(text, style: baseStyle, textAlign: textAlign);
    }

    final main = text.substring(0, idx);
    final decimals = text.substring(idx);
    final smallStyle = baseStyle.copyWith(
      fontSize: (baseStyle.fontSize ?? 14) * decimalScale,
    );

    return Text.rich(
      TextSpan(
        text: main,
        style: baseStyle,
        children: [TextSpan(text: decimals, style: smallStyle)],
      ),
      textAlign: textAlign,
    );
  }
}
