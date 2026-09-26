/// Mirrors of the backend inventory entities (backend/Inventory.cs).
const stockUnits = ['kg', 'g', 'L', 'ml', 'pcs', 'dozen', 'pack'];

double _d(Object? v) => (v as num? ?? 0).toDouble();

class Item {
  const Item({required this.id, required this.name, required this.unit, required this.isActive});

  final int id;
  final String name;
  final String unit;
  final bool isActive;

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        unit: j['unit'] as String? ?? 'kg',
        isActive: j['isActive'] as bool? ?? true,
      );
}

/// One row of a stock-on-hand view (admin/owner).
class OnHandRow {
  const OnHandRow({
    required this.itemId,
    required this.name,
    required this.unit,
    required this.lastCountDate,
    required this.lastCountQty,
    required this.bought,
    required this.used,
    required this.expected,
    required this.avgUnitCost,
    required this.value,
  });

  final int itemId;
  final String name;
  final String unit;
  final String? lastCountDate;
  final double? lastCountQty;
  final double bought;
  final double used;
  final double expected;
  final double avgUnitCost;
  final double value;

  factory OnHandRow.fromJson(Map<String, dynamic> j) => OnHandRow(
        itemId: (j['itemId'] as num).toInt(),
        name: j['name'] as String? ?? '',
        unit: j['unit'] as String? ?? '',
        lastCountDate: j['lastCountDate'] as String?,
        lastCountQty: j['lastCountQty'] == null ? null : _d(j['lastCountQty']),
        bought: _d(j['bought']),
        used: _d(j['used']),
        expected: _d(j['expected']),
        avgUnitCost: _d(j['avgUnitCost']),
        value: _d(j['value']),
      );
}

class StockReportRow {
  const StockReportRow({
    required this.name,
    required this.unit,
    required this.boughtQty,
    required this.spend,
    required this.avgUnitCost,
    required this.usedQty,
    required this.counts,
    required this.shortageQty,
    required this.shortageValue,
  });

  final String name;
  final String unit;
  final double boughtQty;
  final double spend;
  final double avgUnitCost;
  final double usedQty;
  final int counts;

  /// Negative when counts found less than expected.
  final double shortageQty;
  final double shortageValue;

  factory StockReportRow.fromJson(Map<String, dynamic> j) => StockReportRow(
        name: j['name'] as String? ?? '',
        unit: j['unit'] as String? ?? '',
        boughtQty: _d(j['boughtQty']),
        spend: _d(j['spend']),
        avgUnitCost: _d(j['avgUnitCost']),
        usedQty: _d(j['usedQty']),
        counts: (j['counts'] as num? ?? 0).toInt(),
        shortageQty: _d(j['shortageQty']),
        shortageValue: _d(j['shortageValue']),
      );
}

class StockReport {
  const StockReport({required this.totalSpend, required this.totalShortageValue, required this.items});

  final double totalSpend;
  final double totalShortageValue;
  final List<StockReportRow> items;

  factory StockReport.fromJson(Map<String, dynamic> j) => StockReport(
        totalSpend: _d(j['totalSpend']),
        totalShortageValue: _d(j['totalShortageValue']),
        items: [
          for (final r in (j['items'] as List? ?? const []))
            StockReportRow.fromJson(r as Map<String, dynamic>)
        ],
      );
}

class CountResult {
  const CountResult({
    required this.name,
    required this.unit,
    required this.counted,
    required this.expected,
    required this.variance,
  });

  final String name;
  final String unit;
  final double counted;
  final double expected;
  final double variance;

  factory CountResult.fromJson(Map<String, dynamic> j) => CountResult(
        name: j['name'] as String? ?? '',
        unit: j['unit'] as String? ?? '',
        counted: _d(j['counted']),
        expected: _d(j['expected']),
        variance: _d(j['variance']),
      );
}

/// What is already saved for a day (usage or count), keyed by item.
class DayEntry {
  const DayEntry({required this.quantity, required this.note});

  final double quantity;
  final String note;
}

/// Formats a quantity without trailing zeros: 7 -> "7", 2.5 -> "2.5", 0.125 -> "0.125".
String qty(double v) {
  final s = v.toStringAsFixed(3);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}
