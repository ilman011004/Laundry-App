import '../../core/format.dart';

class PosService {
  const PosService({
    required this.id,
    required this.name,
    required this.pricingType,
    required this.price,
  });

  final int id;
  final String name;
  final String pricingType; // PER_KG, PER_ITEM, PACKAGE
  final int price;

  String get unit => switch (pricingType) {
        'PER_KG' => 'kg',
        'PER_ITEM' => 'item',
        _ => 'paket',
      };

  factory PosService.fromJson(Map<String, dynamic> j) => PosService(
        id: j['id'] as int,
        name: j['name'] as String,
        pricingType: j['pricingType'] as String,
        price: j['price'] as int,
      );
}

class PosOption {
  const PosOption({
    required this.id,
    required this.name,
    required this.priceMode,
    required this.price,
    this.durationHours,
  });

  final int id;
  final String name;
  final String priceMode; // FIXED atau PERCENT
  final int price;
  final int? durationHours;

  /// "+25%", "gratis", atau "+Rp 3.000"
  String get tariffLabel {
    if (priceMode == 'PERCENT') return '+$price%';
    if (price == 0) return 'gratis';
    return '+${formatRupiah(price)}';
  }

  String? get durationLabel {
    final h = durationHours;
    if (h == null) return null;
    if (h >= 24 && h % 24 == 0) return '${h ~/ 24} hari';
    return '$h jam';
  }

  factory PosOption.fromJson(Map<String, dynamic> j) => PosOption(
        id: j['id'] as int,
        name: j['name'] as String,
        priceMode: j['priceMode'] as String,
        price: j['price'] as int,
        durationHours: j['durationHours'] as int?,
      );
}

class PosCatalog {
  const PosCatalog({
    required this.services,
    required this.speeds,
    required this.addons,
    required this.fulfillments,
  });

  final List<PosService> services;
  final List<PosOption> speeds;
  final List<PosOption> addons;
  final List<PosOption> fulfillments;

  factory PosCatalog.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) f) =>
        ((j[key] as List?) ?? [])
            .map((e) => f(e as Map<String, dynamic>))
            .toList();

    return PosCatalog(
      services: list('services', PosService.fromJson),
      speeds: list('speeds', PosOption.fromJson),
      addons: list('addons', PosOption.fromJson),
      fulfillments: list('fulfillments', PosOption.fromJson),
    );
  }
}

class PreviewAddon {
  const PreviewAddon({required this.name, required this.amount});
  final String name;
  final int amount;
}

class PreviewLine {
  const PreviewLine({
    required this.serviceName,
    required this.quantity,
    required this.lineTotal,
    required this.addons,
  });

  final String serviceName;
  final double quantity;
  final int lineTotal;
  final List<PreviewAddon> addons;
}

class PricePreview {
  const PricePreview({
    required this.lines,
    required this.servicesSubtotal,
    required this.addonsTotal,
    required this.speedFee,
    required this.deliveryFee,
    required this.discount,
    required this.total,
    this.speedName,
    this.fulfillmentName,
    this.estimatedDoneAt,
  });

  final List<PreviewLine> lines;
  final int servicesSubtotal;
  final int addonsTotal;
  final int speedFee;
  final int deliveryFee;
  final int discount;
  final int total;
  final String? speedName;
  final String? fulfillmentName;
  final DateTime? estimatedDoneAt;

  factory PricePreview.fromJson(Map<String, dynamic> j) {
    final speed = j['speed'] as Map<String, dynamic>?;
    final fulfillment = j['fulfillment'] as Map<String, dynamic>?;
    return PricePreview(
      lines: ((j['items'] as List?) ?? []).map((e) {
        final m = e as Map<String, dynamic>;
        return PreviewLine(
          serviceName: m['serviceName'] as String,
          quantity: (m['quantity'] as num).toDouble(),
          lineTotal: m['lineTotal'] as int,
          addons: ((m['addons'] as List?) ?? []).map((a) {
            final am = a as Map<String, dynamic>;
            return PreviewAddon(
              name: am['name'] as String,
              amount: am['amount'] as int,
            );
          }).toList(),
        );
      }).toList(),
      servicesSubtotal: j['servicesSubtotal'] as int,
      addonsTotal: j['addonsTotal'] as int,
      speedFee: j['speedFee'] as int,
      deliveryFee: j['deliveryFee'] as int,
      discount: j['discount'] as int,
      total: j['total'] as int,
      speedName: speed?['name'] as String?,
      fulfillmentName: fulfillment?['name'] as String?,
      estimatedDoneAt: parseApiDate(j['estimatedDoneAt'] as String?),
    );
  }
}

/// 2.0 -> "2", 2.5 -> "2,5"
String formatQty(double q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  return q.toString().replaceAll('.', ',');
}