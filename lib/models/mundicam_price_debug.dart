import 'mundicam_user_context.dart';

class MundicamPriceDebug {
  final MundicamUserContext context;
  final Map<String, dynamic> debug;
  final String expectedRule;

  const MundicamPriceDebug({
    required this.context,
    required this.debug,
    required this.expectedRule,
  });

  factory MundicamPriceDebug.fromJson(Map<String, dynamic> json) {
    return MundicamPriceDebug(
      context: MundicamUserContext.fromJson(
        (json['context'] as Map?)?.map(
              (key, value) => MapEntry(key.toString(), value),
            ) ??
            const <String, dynamic>{},
      ),
      debug: (json['debug'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value),
          ) ??
          const <String, dynamic>{},
      expectedRule: json['expected_rule']?.toString() ?? '',
    );
  }

  int get productId => _asInt(debug['product_id']);
  String get sku => debug['sku']?.toString() ?? '';
  String get name => debug['name']?.toString() ?? '';
  double? get price => _asDouble(debug['price']);
  double? get regularPrice => _asDouble(debug['regular_price']);
  double? get salePrice => _asDouble(debug['sale_price']);
  String get priceHtml => debug['price_html']?.toString() ?? '';

  String get displayPriceText {
    if (price == null || price! <= 0) return 'Consultar';
    return '${price!.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '.'));
  }
}
