import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../utils/formatters.dart';

/// Intervalul de index facturat, aliniat la dreapta: valorile, apoi tipul
/// citirii și perioada. Nu ocupă loc dacă factura nu are index cunoscut.
class BillIndexBadge extends StatelessWidget {
  final Bill bill;

  const BillIndexBadge({super.key, required this.bill});

  static bool hasIndex(Bill bill) =>
      bill.indexFrom != null || bill.indexTo != null;

  @override
  Widget build(BuildContext context) {
    final from = bill.indexFrom;
    final to = bill.indexTo;
    if (from == null && to == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final small = textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    String n(double v) =>
        v == v.roundToDouble() ? indexFormat.format(v) : formatNumber(v);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('Index', style: small),
          Text(
            from != null && to != null
                ? '${n(from)} → ${n(to)}'
                : n((to ?? from)!),
            textAlign: TextAlign.end,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (bill.readingType.isNotEmpty)
            Text(
              bill.readingType.toLowerCase(),
              textAlign: TextAlign.end,
              style: small,
            ),
          if (bill.indexPeriod.isNotEmpty)
            Text(bill.indexPeriod, textAlign: TextAlign.end, style: small),
        ],
      ),
    );
  }
}
