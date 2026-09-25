/// Mirror of the backend `Dish` entity. Portion pricing:
///  - `SingleDouble`: price = Single, doublePrice = Double
///  - `QuarterHalfFull`: price = Quarter, doublePrice = Half, thirdPrice = Full
/// A null `doublePrice` means the dish only has one price.
enum PricingScheme {
  singleDouble('SingleDouble', ['Single', 'Double', '']),
  quarterHalfFull('QuarterHalfFull', ['Quarter', 'Half', 'Full']);

  const PricingScheme(this.wire, this.tierLabels);

  final String wire;
  final List<String> tierLabels;

  static PricingScheme parse(String? v) =>
      v == 'QuarterHalfFull' ? quarterHalfFull : singleDouble; // null ≈ SingleDouble
}

class Dish {
  const Dish({
    required this.id,
    required this.name,
    required this.price,
    required this.taxRate,
    required this.isActive,
    this.printName,
    this.imagePath,
    this.doublePrice,
    this.thirdPrice,
    this.pricingScheme,
  });

  final int id;
  final String name;
  final double price;
  final double taxRate;
  final bool isActive;
  final String? printName;
  final String? imagePath;
  final double? doublePrice;
  final double? thirdPrice;
  final String? pricingScheme;

  /// English name if there is one — glanceable on any phone font.
  String get label => (printName != null && printName!.isNotEmpty) ? printName! : name;

  factory Dish.fromJson(Map<String, dynamic> j) => Dish(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        price: (j['price'] as num? ?? 0).toDouble(),
        taxRate: (j['taxRate'] as num? ?? 0).toDouble(),
        isActive: j['isActive'] as bool? ?? true,
        printName: j['printName'] as String?,
        imagePath: j['imagePath'] as String?,
        doublePrice: (j['doublePrice'] as num?)?.toDouble(),
        thirdPrice: (j['thirdPrice'] as num?)?.toDouble(),
        pricingScheme: j['pricingScheme'] as String?,
      );
}

/// Body for POST/PUT `/api/dishes` (backend `DishDto`).
class DishInput {
  const DishInput({
    required this.name,
    required this.price,
    required this.taxRate,
    this.printName,
    this.doublePrice,
    this.thirdPrice,
    this.scheme = PricingScheme.singleDouble,
  });

  final String name;
  final double price;
  final double taxRate;
  final String? printName;
  final double? doublePrice;
  final double? thirdPrice;
  final PricingScheme scheme;

  /// Same normalisation as the web Menu Setup: a dish with no 2nd price has no
  /// scheme and no 3rd price; a 3rd price only exists for QuarterHalfFull.
  Map<String, dynamic> toJson() {
    final hasTier2 = doublePrice != null && doublePrice! > 0;
    final hasTier3 = hasTier2 &&
        scheme == PricingScheme.quarterHalfFull &&
        thirdPrice != null &&
        thirdPrice! > 0;
    return {
      'name': name,
      'price': price,
      'taxRate': taxRate,
      'printName': (printName == null || printName!.trim().isEmpty) ? null : printName!.trim(),
      'doublePrice': hasTier2 ? doublePrice : null,
      'thirdPrice': hasTier3 ? thirdPrice : null,
      'pricingScheme': hasTier2 ? scheme.wire : null,
    };
  }
}
