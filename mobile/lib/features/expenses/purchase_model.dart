/// Mirror of the backend `Purchase` / `PurchaseAttachment` (shown as
/// "Expenses" in the apps). Categories match the web Expenses screen.
const expenseCategories = [
  'Food & Beverage',
  'Cleaning',
  'Equipment',
  'Utilities',
  'Salary',
  'Rent',
  'Packaging',
  'Other',
];

class Attachment {
  const Attachment({required this.id, required this.imagePath});

  final int id;
  final String imagePath;

  factory Attachment.fromJson(Map<String, dynamic> j) =>
      Attachment(id: (j['id'] as num).toInt(), imagePath: j['imagePath'] as String? ?? '');
}

/// One itemised line on a bill (backend `PurchaseItem`). Name and unit are snapshots.
class BillLine {
  const BillLine({
    required this.itemId,
    required this.itemName,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  final int itemId;
  final String itemName;
  final String unit;
  final double quantity;
  final double unitPrice;
  final double lineTotal;

  factory BillLine.fromJson(Map<String, dynamic> j) => BillLine(
        itemId: (j['itemId'] as num).toInt(),
        itemName: j['itemName'] as String? ?? '',
        unit: j['unit'] as String? ?? '',
        quantity: (j['quantity'] as num? ?? 0).toDouble(),
        unitPrice: (j['unitPrice'] as num? ?? 0).toDouble(),
        lineTotal: (j['lineTotal'] as num? ?? 0).toDouble(),
      );
}

/// A line as sent to the server when saving a bill.
class BillLineInput {
  const BillLineInput({required this.itemId, required this.quantity, required this.unitPrice});

  final int itemId;
  final double quantity;
  final double unitPrice;

  Map<String, dynamic> toJson() => {'itemId': itemId, 'quantity': quantity, 'unitPrice': unitPrice};
}

class Purchase {
  const Purchase({
    required this.id,
    required this.date,
    required this.supplier,
    required this.description,
    required this.totalAmount,
    required this.category,
    required this.attachments,
    this.items = const [],
  });

  final int id;

  /// Calendar date only. The server stores it as UTC-midnight of the chosen
  /// day, so it must NOT be shifted to UAE/local time — take the date part.
  final DateTime date;
  final String supplier;
  final String description;
  final double totalAmount;
  final String category;
  final List<Attachment> attachments;

  /// Itemised bill lines; empty for older bills that only have a total.
  final List<BillLine> items;

  factory Purchase.fromJson(Map<String, dynamic> j) {
    final raw = (j['date'] as String? ?? '').split('T').first;
    final p = raw.split('-').map(int.tryParse).toList();
    final date = p.length == 3 && !p.contains(null)
        ? DateTime(p[0]!, p[1]!, p[2]!)
        : DateTime.now();
    return Purchase(
      id: (j['id'] as num).toInt(),
      date: date,
      supplier: j['supplier'] as String? ?? '',
      description: j['description'] as String? ?? '',
      totalAmount: (j['totalAmount'] as num? ?? 0).toDouble(),
      category: j['category'] as String? ?? 'General',
      attachments: [
        for (final a in (j['attachments'] as List? ?? const []))
          Attachment.fromJson(a as Map<String, dynamic>)
      ],
      items: [
        for (final i in (j['items'] as List? ?? const []))
          BillLine.fromJson(i as Map<String, dynamic>)
      ],
    );
  }
}
