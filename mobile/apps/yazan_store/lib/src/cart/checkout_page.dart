import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../config.dart';
import 'cart.dart';
import 'cart_controller.dart';
import 'cart_scope.dart';
import 'order_placed_page.dart';
import 'store_api.dart';

/// Delivery details and cash-on-delivery checkout. Online only: the server validates the address,
/// checks stock and creates the order; a retry reuses the same idempotency key (see [StoreApi]).
class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key, required this.controller, required this.cart});

  final CartController controller;

  /// The cart being checked out: prefills the address and supplies the country.
  final Cart cart;

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _form = GlobalKey<FormState>();
  late final _firstName = TextEditingController(text: _prefill('first_name'));
  late final _lastName = TextEditingController(text: _prefill('last_name'));
  late final _phone = TextEditingController(text: _prefill('phone'));
  late final _email = TextEditingController(text: _prefill('email'));
  late final _address = TextEditingController(text: _prefill('address_1'));
  late final _city = TextEditingController(text: _prefill('city'));
  late final _region = TextEditingController(text: _prefill('state'));
  late final _postcode = TextEditingController(text: _prefill('postcode'));
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  String get _country => widget.cart.countryOr(AppConfig.defaultCountry);

  String _prefill(String key) {
    final b = widget.cart.billing[key];
    if (b != null && b.isNotEmpty) return b;
    return widget.cart.shipping[key] ?? '';
  }

  @override
  void dispose() {
    for (final c in [
      _firstName,
      _lastName,
      _phone,
      _email,
      _address,
      _city,
      _region,
      _postcode,
      _note,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  CheckoutDetails _details() => CheckoutDetails(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        address: _address.text.trim(),
        city: _city.text.trim(),
        state: _region.text.trim(),
        postcode: _postcode.text.trim(),
        country: _country,
        note: _note.text.trim(),
      );

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final form = _form.currentState;
    if (_busy || form == null || !form.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final details = _details();
      final order = await widget.controller.placeOrder(details);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => OrderPlacedPage(order: order, email: details.email),
        ),
      );
    } on StoreApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.isNetwork ? l.checkoutOffline : storeErrorMessage(l, e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l.genericError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cod = widget.cart.acceptsCashOnDelivery;
    final error = _error;
    String? requiredValidator(String? v) => (v == null || v.trim().isEmpty) ? l.requiredField : null;

    Widget field(
      TextEditingController controller,
      String label, {
      bool isRequired = false,
      TextInputType? keyboard,
      Iterable<String>? autofill,
      TextDirection? direction,
      int maxLines = 1,
    }) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          decoration: InputDecoration(labelText: label),
          keyboardType: keyboard,
          autofillHints: autofill,
          textDirection: direction,
          maxLines: maxLines,
          enabled: !_busy,
          validator: isRequired ? requiredValidator : null,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.checkout)),
      body: Form(
        key: _form,
        child: AutofillGroup(
          child: ListView(
            padding: const EdgeInsetsDirectional.all(16),
            children: [
              Text(l.deliveryDetails, style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              field(_firstName, l.firstName,
                  isRequired: true, autofill: const [AutofillHints.givenName]),
              field(_lastName, l.lastName,
                  isRequired: true, autofill: const [AutofillHints.familyName]),
              field(_phone, l.phone,
                  isRequired: true,
                  keyboard: TextInputType.phone,
                  autofill: const [AutofillHints.telephoneNumber],
                  direction: TextDirection.ltr),
              field(_email, l.emailAddress,
                  isRequired: true,
                  keyboard: TextInputType.emailAddress,
                  autofill: const [AutofillHints.email],
                  direction: TextDirection.ltr),
              field(_address, l.addressLine,
                  isRequired: true, autofill: const [AutofillHints.streetAddressLine1]),
              field(_city, l.city, isRequired: true, autofill: const [AutofillHints.addressCity]),
              field(_region, l.region, autofill: const [AutofillHints.addressState]),
              field(_postcode, l.postcode, autofill: const [AutofillHints.postalCode]),
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 12),
                child: InputDecorator(
                  decoration: InputDecoration(labelText: l.country),
                  child: Text(_country),
                ),
              ),
              field(_note, l.orderNote, maxLines: 3),
              const SizedBox(height: 8),
              Text(l.paymentMethod, style: theme.textTheme.titleMedium),
              if (cod)
                ListTile(
                  contentPadding: EdgeInsetsDirectional.zero,
                  leading: const Icon(Icons.payments_outlined),
                  title: Text(l.cashOnDelivery),
                  trailing: Icon(Icons.check_circle, color: theme.colorScheme.primary),
                )
              else
                Padding(
                  padding: const EdgeInsetsDirectional.symmetric(vertical: 12),
                  child: Text(
                    l.codUnavailable,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null) ...[
                Text(
                  error,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                onPressed: _busy || !cod ? null : _submit,
                child: Text(l.placeOrder),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
