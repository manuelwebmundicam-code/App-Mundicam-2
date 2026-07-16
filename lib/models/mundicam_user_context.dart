class MundicamUserContext {
  final int wpUserId;
  final List<String> realRoles;
  final Map<String, String> realRoleNames;
  final bool isAdmin;
  final bool isCommercial;
  final bool isCustomer;
  final bool isBlocked;
  final bool canViewStock;
  final String? effectivePriceGroup;
  final String? effectivePriceRoleSlug;
  final String? effectivePriceRoleName;
  final String? priceRule;

  const MundicamUserContext({
    required this.wpUserId,
    required this.realRoles,
    required this.realRoleNames,
    required this.isAdmin,
    required this.isCommercial,
    required this.isCustomer,
    required this.isBlocked,
    required this.canViewStock,
    required this.effectivePriceGroup,
    required this.effectivePriceRoleSlug,
    required this.effectivePriceRoleName,
    required this.priceRule,
  });

  factory MundicamUserContext.fromJson(Map<String, dynamic> json) {
    final roleNamesRaw = json['real_role_names'];

    return MundicamUserContext(
      wpUserId: _asInt(json['wp_user_id']),
      realRoles: _asStringList(json['real_roles']),
      realRoleNames: roleNamesRaw is Map
          ? roleNamesRaw.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const <String, String>{},
      isAdmin: json['is_admin'] == true,
      isCommercial: json['is_commercial'] == true,
      isCustomer: json['is_customer'] == true,
      isBlocked: json['is_blocked'] == true,
      canViewStock: json['can_view_stock'] == true,
      effectivePriceGroup: _asNullableString(json['effective_price_group']),
      effectivePriceRoleSlug: _asNullableString(json['effective_price_role_slug']),
      effectivePriceRoleName: _asNullableString(json['effective_price_role_name']),
      priceRule: _asNullableString(json['price_rule']),
    );
  }

  bool get isAdminForcedTo52 => priceRule == 'admin_forced_to_52';

  String get roleSummary {
    if (isAdmin) return 'Administrador';
    if (isCommercial) return 'Comercial';
    if (isCustomer) return 'Cliente';
    return realRoles.isEmpty ? 'Usuario' : realRoles.join(', ');
  }

  String get effectivePriceLabel {
    if (effectivePriceGroup == null || effectivePriceGroup!.isEmpty) {
      return 'PVP';
    }
    return '$effectivePriceGroup%';
  }

  Map<String, dynamic> toJson() {
    return {
      'wp_user_id': wpUserId,
      'real_roles': realRoles,
      'real_role_names': realRoleNames,
      'is_admin': isAdmin,
      'is_commercial': isCommercial,
      'is_customer': isCustomer,
      'is_blocked': isBlocked,
      'can_view_stock': canViewStock,
      'effective_price_group': effectivePriceGroup,
      'effective_price_role_slug': effectivePriceRoleSlug,
      'effective_price_role_name': effectivePriceRoleName,
      'price_rule': priceRule,
    };
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String? _asNullableString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static List<String> _asStringList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return const <String>[];
  }
}
