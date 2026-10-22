// The shipping and tax settings as the web dashboard reads them, kept for offline viewing.
// Parsing never throws: a field the server leaves out reads as empty.

/// One shipping method on a zone (`zones[].methods[]` of `GET /yazan/v1/shipping/zones`).
class ShippingMethodInfo {
  const ShippingMethodInfo({
    required this.instanceId,
    required this.methodId,
    required this.title,
    required this.methodTitle,
    required this.enabled,
    required this.values,
    required this.labels,
  });

  final int instanceId;

  /// WooCommerce's method type: `flat_rate`, `free_shipping`, `local_pickup`, `yazan_live_rates`…
  final String methodId;

  /// The name customers see at checkout.
  final String title;

  /// The method type's own name ("Flat rate").
  final String methodTitle;
  final bool enabled;

  /// The method's settings by key (`cost`, `min_amount`, `requires`, `class_cost_12`…), as text.
  final Map<String, String> values;

  /// The server's label of each settings key.
  final Map<String, String> labels;

  String value(String key) => (values[key] ?? '').trim();

  /// Per-shipping-class costs that are set (`class_cost_<id>` and `no_class_cost`), in server order.
  List<MapEntry<String, String>> get classCosts => [
        for (final e in values.entries)
          if ((e.key.startsWith('class_cost_') || e.key == 'no_class_cost') && e.value.trim().isNotEmpty)
            MapEntry(labels[e.key] ?? e.key, e.value.trim()),
      ];

  factory ShippingMethodInfo.fromServer(Map<String, dynamic> j) {
    final values = <String, String>{};
    final labels = <String, String>{};
    final fields = j['fields'];
    if (fields is List) {
      for (final f in fields) {
        if (f is! Map) continue;
        final key = '${f['key'] ?? ''}';
        if (key.isEmpty) continue;
        final v = f['value'];
        values[key] = v == null || v is Map || v is List ? '' : '$v';
        labels[key] = '${f['label'] ?? key}';
      }
    }
    return ShippingMethodInfo(
      instanceId: _int(j['instance_id']) ?? 0,
      methodId: '${j['method_id'] ?? ''}',
      title: '${j['title'] ?? ''}',
      methodTitle: '${j['method_title'] ?? ''}',
      enabled: _bool(j['enabled']),
      values: values,
      labels: labels,
    );
  }

  factory ShippingMethodInfo.fromJson(Map<String, dynamic> j) => ShippingMethodInfo(
        instanceId: _int(j['instance_id']) ?? 0,
        methodId: '${j['method_id'] ?? ''}',
        title: '${j['title'] ?? ''}',
        methodTitle: '${j['method_title'] ?? ''}',
        enabled: _bool(j['enabled']),
        values: _strings(j['values']),
        labels: _strings(j['labels']),
      );

  Map<String, dynamic> toJson() => {
        'instance_id': instanceId,
        'method_id': methodId,
        'title': title,
        'method_title': methodTitle,
        'enabled': enabled,
        'values': values,
        'labels': labels,
      };
}

/// One shipping zone with its methods.
class ShippingZoneInfo {
  const ShippingZoneInfo({
    required this.id,
    required this.name,
    required this.isFallback,
    required this.regionText,
    required this.methods,
  });

  final int id;
  final String name;

  /// Zone 0, "Rest of the world": catches every address no other zone matches.
  final bool isFallback;

  /// WooCommerce's own summary of the zone's regions ("Saudi Arabia, Yemen").
  final String regionText;
  final List<ShippingMethodInfo> methods;

  factory ShippingZoneInfo.fromServer(Map<String, dynamic> j) => ShippingZoneInfo(
        id: _int(j['id']) ?? 0,
        name: '${j['name'] ?? ''}',
        isFallback: _bool(j['is_fallback']),
        regionText: '${j['region_text'] ?? ''}',
        methods: [
          for (final m in (j['methods'] is List ? j['methods'] as List : const []))
            if (m is Map) ShippingMethodInfo.fromServer(Map<String, dynamic>.from(m)),
        ],
      );

  factory ShippingZoneInfo.fromJson(Map<String, dynamic> j) => ShippingZoneInfo(
        id: _int(j['id']) ?? 0,
        name: '${j['name'] ?? ''}',
        isFallback: _bool(j['is_fallback']),
        regionText: '${j['region_text'] ?? ''}',
        methods: [
          for (final m in (j['methods'] is List ? j['methods'] as List : const []))
            if (m is Map) ShippingMethodInfo.fromJson(Map<String, dynamic>.from(m)),
        ],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'is_fallback': isFallback,
        'region_text': regionText,
        'methods': [for (final m in methods) m.toJson()],
      };
}

/// `GET /yazan/v1/shipping/zones` as last seen (needs `shipping.view`).
class ShippingSnapshot {
  const ShippingSnapshot({required this.fetchedAt, required this.zones});

  final DateTime fetchedAt;

  /// In WooCommerce's matching order, the fallback zone last.
  final List<ShippingZoneInfo> zones;

  factory ShippingSnapshot.fromServer(Map<String, dynamic> j, {required DateTime fetchedAt}) =>
      ShippingSnapshot(
        fetchedAt: fetchedAt,
        zones: [
          for (final z in (j['zones'] is List ? j['zones'] as List : const []))
            if (z is Map) ShippingZoneInfo.fromServer(Map<String, dynamic>.from(z)),
        ],
      );

  factory ShippingSnapshot.fromJson(Map<String, dynamic> j) => ShippingSnapshot(
        fetchedAt: _time(j['fetched_at']),
        zones: [
          for (final z in (j['zones'] is List ? j['zones'] as List : const []))
            if (z is Map) ShippingZoneInfo.fromJson(Map<String, dynamic>.from(z)),
        ],
      );

  Map<String, dynamic> toJson() => {
        'fetched_at': fetchedAt.toIso8601String(),
        'zones': [for (final z in zones) z.toJson()],
      };
}

/// One store-wide tax option (`fields[]` of `GET /yazan/v1/tax`).
class TaxSetting {
  const TaxSetting({
    required this.option,
    required this.type,
    required this.label,
    required this.value,
    required this.choices,
  });

  /// The WooCommerce option name, e.g. `woocommerce_tax_based_on`.
  final String option;

  /// `bool_yesno`, `select` or `text`.
  final String type;
  final String label;

  /// Booleans are stored as `yes` / `no`.
  final String value;

  /// For a select: value -> the server's label.
  final Map<String, String> choices;

  bool get isBool => type == 'bool_yesno';

  factory TaxSetting.fromServer(Map<String, dynamic> j) {
    final type = '${j['type'] ?? 'text'}';
    final raw = j['value'];
    return TaxSetting(
      option: '${j['option'] ?? ''}',
      type: type,
      label: '${j['label'] ?? ''}',
      value: type == 'bool_yesno' ? (_bool(raw) ? 'yes' : 'no') : (raw == null ? '' : '$raw'),
      choices: _strings(j['choices']),
    );
  }

  factory TaxSetting.fromJson(Map<String, dynamic> j) => TaxSetting(
        option: '${j['option'] ?? ''}',
        type: '${j['type'] ?? 'text'}',
        label: '${j['label'] ?? ''}',
        value: '${j['value'] ?? ''}',
        choices: _strings(j['choices']),
      );

  Map<String, dynamic> toJson() =>
      {'option': option, 'type': type, 'label': label, 'value': value, 'choices': choices};
}

/// One row of a tax rate table (`items[]` of `GET /yazan/v1/tax/rates?class=`).
class TaxRateInfo {
  const TaxRateInfo({
    required this.id,
    required this.country,
    required this.state,
    required this.postcode,
    required this.city,
    required this.rate,
    required this.name,
    required this.priority,
    required this.compound,
    required this.shipping,
    required this.managed,
  });

  final int id;

  /// ISO code, or `*` for any.
  final String country;
  final String state;
  final String postcode;
  final String city;

  /// Percent as the server's decimal string ("8.8750").
  final String rate;
  final String name;
  final int priority;
  final bool compound;

  /// Also charged on shipping.
  final bool shipping;

  /// Written by the automatic state rates or Stripe Tax rather than typed by hand.
  final bool managed;

  /// "US · CA · 90210; 90211 · LOS ANGELES"; empty when the rate applies everywhere.
  String get location => [
        for (final part in [country, state, postcode, city])
          if (part.trim().isNotEmpty && part.trim() != '*') part.trim(),
      ].join(' · ');

  /// The rate without trailing zeros: "8.8750" -> "8.875", "5.0000" -> "5".
  String get percent {
    final r = rate.trim();
    if (!RegExp(r'^\d+\.\d+$').hasMatch(r)) return r;
    final trimmed = r.replaceFirst(RegExp(r'0+$'), '');
    return trimmed.endsWith('.') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }

  factory TaxRateInfo.fromJson(Map<String, dynamic> j) => TaxRateInfo(
        id: _int(j['id']) ?? 0,
        country: '${j['country'] ?? '*'}',
        state: '${j['state'] ?? '*'}',
        postcode: '${j['postcode'] ?? ''}',
        city: '${j['city'] ?? ''}',
        rate: '${j['rate'] ?? ''}',
        name: '${j['name'] ?? ''}',
        priority: _int(j['priority']) ?? 1,
        compound: _bool(j['compound']),
        shipping: _bool(j['shipping']),
        managed: _bool(j['managed']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'country': country,
        'state': state,
        'postcode': postcode,
        'city': city,
        'rate': rate,
        'name': name,
        'priority': priority,
        'compound': compound,
        'shipping': shipping,
        'managed': managed,
      };
}

/// A tax class and its rate table. The Standard class has the empty slug.
class TaxClassRates {
  const TaxClassRates({required this.slug, required this.name, required this.rates});

  final String slug;
  final String name;
  final List<TaxRateInfo> rates;

  bool get isStandard => slug.isEmpty;

  factory TaxClassRates.fromJson(Map<String, dynamic> j) => TaxClassRates(
        slug: '${j['slug'] ?? ''}',
        name: '${j['name'] ?? ''}',
        rates: _rates(j['rates']),
      );

  Map<String, dynamic> toJson() => {
        'slug': slug,
        'name': name,
        'rates': [for (final r in rates) r.toJson()],
      };
}

/// `GET /yazan/v1/tax` plus one `GET /yazan/v1/tax/rates?class=` per class, as last seen (both need
/// `tax.view`).
class TaxSnapshot {
  const TaxSnapshot({
    required this.fetchedAt,
    required this.enabled,
    required this.settings,
    required this.classes,
  });

  final DateTime fetchedAt;

  /// Whether WooCommerce calculates tax at all.
  final bool enabled;
  final List<TaxSetting> settings;
  final List<TaxClassRates> classes;

  /// The `classes` of a `GET /tax` answer as (slug, name, rate count or null when not given).
  static List<({String slug, String name, int? count})> classesOf(Map<String, dynamic> tax) => [
        for (final c in (tax['classes'] is List ? tax['classes'] as List : const []))
          if (c is Map) (slug: '${c['slug'] ?? ''}', name: '${c['name'] ?? ''}', count: _int(c['rates'])),
      ];

  /// [tax] is the `GET /tax` answer; [rates] maps a class slug to the `items` of its rate table.
  factory TaxSnapshot.fromServer(
    Map<String, dynamic> tax,
    Map<String, List<dynamic>> rates, {
    required DateTime fetchedAt,
  }) =>
      TaxSnapshot(
        fetchedAt: fetchedAt,
        enabled: _bool(tax['enabled']),
        settings: [
          for (final f in (tax['fields'] is List ? tax['fields'] as List : const []))
            if (f is Map) TaxSetting.fromServer(Map<String, dynamic>.from(f)),
        ],
        classes: [
          for (final c in classesOf(tax))
            TaxClassRates(slug: c.slug, name: c.name, rates: _rates(rates[c.slug])),
        ],
      );

  factory TaxSnapshot.fromJson(Map<String, dynamic> j) => TaxSnapshot(
        fetchedAt: _time(j['fetched_at']),
        enabled: _bool(j['enabled']),
        settings: [
          for (final f in (j['settings'] is List ? j['settings'] as List : const []))
            if (f is Map) TaxSetting.fromJson(Map<String, dynamic>.from(f)),
        ],
        classes: [
          for (final c in (j['classes'] is List ? j['classes'] as List : const []))
            if (c is Map) TaxClassRates.fromJson(Map<String, dynamic>.from(c)),
        ],
      );

  Map<String, dynamic> toJson() => {
        'fetched_at': fetchedAt.toIso8601String(),
        'enabled': enabled,
        'settings': [for (final s in settings) s.toJson()],
        'classes': [for (final c in classes) c.toJson()],
      };
}

List<TaxRateInfo> _rates(Object? v) => v is List
    ? [for (final e in v) if (e is Map) TaxRateInfo.fromJson(Map<String, dynamic>.from(e))]
    : const [];

/// A JSON object of scalars as strings. PHP sends an empty object as `[]`, which reads as empty.
Map<String, String> _strings(Object? v) => v is Map
    ? {for (final e in v.entries) '${e.key}': e.value == null ? '' : '${e.value}'}
    : const {};

DateTime _time(Object? v) =>
    DateTime.tryParse('${v ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);

bool _bool(Object? v) => v == true || v == 1 || v == '1' || v == 'yes' || v == 'true';

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}');
}
