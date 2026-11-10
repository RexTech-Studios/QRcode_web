import '../models/assignment_model.dart';
import '../models/shop_model.dart';

final RegExp _demoName = RegExp(r'^Demo QR\d+$', caseSensitive: false);

/// True for the placeholder name a printed demo QR starts with ("Demo QR123").
/// Once a client's real name is saved, it is no longer a placeholder.
bool isDemoShopName(String name) => _demoName.hasMatch(name.trim());

/// Where a QR code stands, from the admin's point of view.
enum QrStock {
  /// Set up for a client: a sales person saved it, or its shop already has a
  /// real client's name.
  sold,

  /// Not sold yet, and a sales person is holding it.
  withSalesPerson,

  /// Not sold yet, and nobody holds it. Free to assign.
  free,

  /// Its shop could not be found, so it can't be told.
  unknown,
}

QrStock qrStockOf({required ShopModel? shop, required Assignment? assignment}) {
  if (assignment != null && assignment.isSold) return QrStock.sold;
  if (shop == null) return QrStock.unknown;
  if (!isDemoShopName(shop.shopName)) return QrStock.sold;
  return assignment != null ? QrStock.withSalesPerson : QrStock.free;
}

/// How many QR codes are in each state.
class QrStockCounts {
  final int sold;
  final int withSalesPerson;
  final int free;
  final int unknown;

  const QrStockCounts({
    this.sold = 0,
    this.withSalesPerson = 0,
    this.free = 0,
    this.unknown = 0,
  });

  /// Everything still left to sell.
  int get notSold => withSalesPerson + free;
  int get total => sold + notSold + unknown;

  factory QrStockCounts.of(Iterable<QrStock> states) {
    var sold = 0, withSales = 0, free = 0, unknown = 0;
    for (final s in states) {
      switch (s) {
        case QrStock.sold:
          sold++;
        case QrStock.withSalesPerson:
          withSales++;
        case QrStock.free:
          free++;
        case QrStock.unknown:
          unknown++;
      }
    }
    return QrStockCounts(
      sold: sold,
      withSalesPerson: withSales,
      free: free,
      unknown: unknown,
    );
  }
}
