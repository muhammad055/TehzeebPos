import '../../core/format.dart';

/// Mirror of the `Order` / `OrderItem` entities returned by `/api/orders`.
class OrderItemLine {
  const OrderItemLine({
    required this.dishName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String dishName;
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  factory OrderItemLine.fromJson(Map<String, dynamic> j) => OrderItemLine(
        dishName: j['dishName'] as String? ?? '',
        quantity: (j['quantity'] as num? ?? 0).toInt(),
        unitPrice: (j['unitPrice'] as num? ?? 0).toDouble(),
        lineTotal: (j['lineTotal'] as num? ?? 0).toDouble(),
      );
}

class PosOrder {
  const PosOrder({
    required this.id,
    required this.orderDate,
    required this.tokenNumber,
    required this.paymentMethod,
    required this.subTotal,
    required this.discount,
    required this.taxTotal,
    required this.grandTotal,
    required this.items,
    required this.isCancelled,
    this.cancelledAt,
    this.cancelReason,
  });

  final int id;
  final DateTime orderDate; // UTC
  final int tokenNumber;
  final String paymentMethod;
  final double subTotal;
  final double discount;
  final double taxTotal;
  final double grandTotal;
  final List<OrderItemLine> items;
  final bool isCancelled;
  final DateTime? cancelledAt; // UTC
  final String? cancelReason;

  factory PosOrder.fromJson(Map<String, dynamic> j) {
    double d(String k) => (j[k] as num? ?? 0).toDouble();
    final cancelledAt = j['cancelledAt'] as String?;
    return PosOrder(
      id: (j['id'] as num).toInt(),
      orderDate: parseUtc(j['orderDate'] as String),
      tokenNumber: (j['tokenNumber'] as num? ?? 0).toInt(),
      paymentMethod: j['paymentMethod'] as String? ?? '',
      subTotal: d('subTotal'),
      discount: d('discount'),
      taxTotal: d('taxTotal'),
      grandTotal: d('grandTotal'),
      items: [
        for (final i in (j['items'] as List? ?? const []))
          OrderItemLine.fromJson(i as Map<String, dynamic>)
      ],
      isCancelled: j['isCancelled'] as bool? ?? false,
      cancelledAt: cancelledAt == null ? null : parseUtc(cancelledAt),
      cancelReason: j['cancelReason'] as String?,
    );
  }
}
