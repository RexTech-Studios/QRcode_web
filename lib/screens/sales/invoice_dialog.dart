import 'package:flutter/material.dart';

import '../../models/assignment_model.dart';
import '../../models/invoice_model.dart';
import '../../services/sales_repository.dart';
import '../../utils/app_colors.dart';
import '../../utils/date_format.dart';
import '../../widgets/section_card.dart';

/// Issues the invoice from what was typed. Throws [SalesException] with a
/// message to show if it can't be done.
typedef CreateInvoiceAction = Future<Invoice> Function({
  required String clientName,
  required String clientPhone,
  required String clientAddress,
  required String price,
});

/// Collects the client's details and the price, then issues the invoice for
/// one sold QR. Pops with the new [Invoice] so the caller can download it.
///
/// The admin types the price. A sales person sees the admin's fixed price and
/// cannot change it ([priceLocked]).
class CreateInvoiceDialog extends StatefulWidget {
  final Assignment assignment;

  /// The shop's current name, used as the client name to start with.
  final String? shopName;

  /// What the price box starts with.
  final int? initialPrice;
  final bool priceLocked;
  final CreateInvoiceAction onCreate;

  const CreateInvoiceDialog({
    super.key,
    required this.assignment,
    required this.onCreate,
    this.shopName,
    this.initialPrice,
    this.priceLocked = false,
  });

  @override
  State<CreateInvoiceDialog> createState() => _CreateInvoiceDialogState();
}

class _CreateInvoiceDialogState extends State<CreateInvoiceDialog> {
  late final TextEditingController _name;
  final _phone = TextEditingController();
  final _address = TextEditingController();
  late final TextEditingController _price;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final name = widget.shopName ?? '';
    // A "Demo QR123" placeholder is not a client name.
    _name = TextEditingController(
      text: RegExp(r'^Demo QR\d+$', caseSensitive: false).hasMatch(name.trim())
          ? ''
          : name,
    );
    final price = widget.initialPrice;
    _price = TextEditingController(text: price == null ? '' : '$price');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final invoice = await widget.onCreate(
        clientName: _name.text,
        clientPhone: _phone.text,
        clientAddress: _address.text,
        price: _price.text,
      );
      if (mounted) Navigator.pop(context, invoice);
    } on SalesException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail('Could not create the invoice. Check your connection and try again.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.assignment;
    final soldOn = a.soldAt == null ? '' : '  -  set up ${formatShortDate(a.soldAt!)}';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Invoice for ${a.qrCode}',
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sold by ${a.assignedToName}$soldOn',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              const FieldLabel('Client name'),
              TextField(
                controller: _name,
                enabled: !_saving,
                autofocus: _name.text.isEmpty,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'e.g. Sunrise Bakery',
                  prefixIcon: Icon(Icons.storefront_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 14),
              const FieldLabel('Client phone (optional)'),
              TextField(
                controller: _phone,
                enabled: !_saving,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  hintText: 'e.g. 98765 43210',
                  prefixIcon: Icon(Icons.phone_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 14),
              const FieldLabel('Client address (optional)'),
              TextField(
                controller: _address,
                enabled: !_saving,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Shop address',
                  prefixIcon: Icon(Icons.place_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 14),
              const FieldLabel('Price (Rs.)'),
              TextField(
                controller: _price,
                enabled: !_saving && !widget.priceLocked,
                autofocus: _name.text.isNotEmpty && !widget.priceLocked,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'e.g. 1500',
                  prefixIcon: Icon(Icons.currency_rupee_rounded, size: 20),
                ),
                onSubmitted: (_) => _saving ? null : _create(),
              ),
              const SizedBox(height: 6),
              Text(
                widget.priceLocked
                    ? 'This is the fixed price set by Full Star QR. No GST is added. The invoice gets the next number, and this QR can only be invoiced once.'
                    : 'No GST is added. The invoice gets the next number, and this QR can only be invoiced once.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _create,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Create invoice'),
        ),
      ],
    );
  }
}
