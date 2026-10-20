import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:yazan_admin/l10n/app_localizations.dart';

/// A localised app around [home], with no network anywhere.
Widget customersHost(Locale locale, Widget home) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: home),
    );

/// The `/me` answer for a staff member holding [slugs].
Map<String, dynamic> customersMe(List<String> slugs) => {
      'id': 1,
      'scope': 'admin',
      'permissions': {for (final s in slugs) s: true},
    };

/// Rows as `GET /yazan/v1/customers?stats=1` sends them.
const List<Map<String, dynamic>> customerRows = [
  {
    'id': 11,
    'name': 'Layla Hassan',
    'email': 'layla@example.test',
    'registered': '2026-01-05',
    'order_count': 3,
    'total_spent': '450.00',
  },
  {
    'id': 12,
    'name': 'Omar Saleh',
    'email': 'omar@example.test',
    'phone': '+966 55-512 3456',
    'registered': '2026-02-10',
    'order_count': 0,
    'total_spent': '0.00',
  },
  {
    'id': 13,
    'name': 'ليلى الحداد',
    'email': 'laila.h@example.test',
    'registered': '2026-03-01',
    'order_count': 1,
    'total_spent': '95.50',
  },
];

/// `GET /yazan/v1/customers/{id}` for customer 11.
Map<String, dynamic> customerDetailBody({bool withBilling = true, bool withLastOrder = true}) => {
      'id': 11,
      'name': 'Layla Hassan',
      'email': 'layla@example.test',
      'registered': '2026-01-05',
      'order_count': 3,
      'total_spent': '450.00',
      'currency_symbol': '\$',
      if (withBilling)
        'billing': {
          'first_name': 'Layla',
          'last_name': 'Hassan',
          'company': '',
          'address_1': '12 Palm Street',
          'address_2': '',
          'city': 'Riyadh',
          'state': '',
          'postcode': '11564',
          'country': 'SA',
          'email': 'layla@example.test',
          'phone': '+966501234567',
        },
      'last_order': withLastOrder
          ? {'id': 901, 'number': '901', 'date': '2026-10-01', 'status': 'processing', 'total': '150.00'}
          : null,
    };
