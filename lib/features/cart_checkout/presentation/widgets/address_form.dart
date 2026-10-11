import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme.dart';
import '../../../../core/utilities/validators.dart';
import '../../../catalog/domain/physical_models.dart';

typedef AddressResult = ({ShippingAddress address, bool save});

/// Full-screen delivery address form (India). Returns the address and
/// whether to save it for next time.
Future<AddressResult?> showAddressForm(BuildContext context, {ShippingAddress? initial}) =>
    Navigator.of(context).push<AddressResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AddressFormScreen(initial: initial),
      ),
    );

class AddressFormScreen extends StatefulWidget {
  const AddressFormScreen({super.key, this.initial});
  final ShippingAddress? initial;

  @override
  State<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends State<AddressFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _phone = TextEditingController(text: widget.initial?.phone);
  late final _line1 = TextEditingController(text: widget.initial?.line1);
  late final _line2 = TextEditingController(text: widget.initial?.line2);
  late final _city = TextEditingController(text: widget.initial?.city);
  late final _pin = TextEditingController(text: widget.initial?.pinCode);
  late String? _state = indianStates.contains(widget.initial?.state) ? widget.initial!.state : null;
  bool _save = true;

  @override
  void dispose() {
    for (final c in [_name, _phone, _line1, _line2, _city, _pin]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop((
      address: ShippingAddress(
        id: widget.initial?.id,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        line1: _line1.text.trim(),
        line2: _line2.text.trim().isEmpty ? null : _line2.text.trim(),
        city: _city.text.trim(),
        state: _state!,
        pinCode: _pin.text.trim(),
      ),
      save: _save,
    ));
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: AppSpacing.md);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery address'),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: AppSpacing.page,
          children: [
            TextFormField(
              controller: _name,
              autofillHints: const [AutofillHints.name],
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (v) => Validators.required(v, 'Name'),
            ),
            gap,
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91 '),
              validator: ShippingValidators.mobile,
            ),
            gap,
            TextFormField(
              controller: _line1,
              autofillHints: const [AutofillHints.streetAddressLine1],
              decoration: const InputDecoration(labelText: 'Address line 1', hintText: 'House / building, street'),
              validator: (v) => Validators.required(v, 'Address'),
            ),
            gap,
            TextFormField(
              controller: _line2,
              autofillHints: const [AutofillHints.streetAddressLine2],
              decoration: const InputDecoration(labelText: 'Address line 2 (optional)', hintText: 'Area, landmark'),
            ),
            gap,
            TextFormField(
              controller: _city,
              autofillHints: const [AutofillHints.addressCity],
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'City / town'),
              validator: (v) => Validators.required(v, 'City'),
            ),
            gap,
            DropdownButtonFormField<String>(
              initialValue: _state,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'State / UT'),
              items: [
                for (final s in indianStates) DropdownMenuItem(value: s, child: Text(s)),
              ],
              onChanged: (v) => setState(() => _state = v),
              validator: (v) => v == null ? 'State is required' : null,
            ),
            gap,
            TextFormField(
              controller: _pin,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.postalCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(labelText: 'PIN code'),
              validator: ShippingValidators.pinCode,
            ),
            gap,
            const InputDecorator(
              decoration: InputDecoration(labelText: 'Country'),
              child: Text('India'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _save,
              onChanged: (v) => setState(() => _save = v ?? false),
              title: const Text('Save this address on this device'),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: _submit, child: const Text('Use this address')),
          ],
        ),
      ),
    );
  }
}
