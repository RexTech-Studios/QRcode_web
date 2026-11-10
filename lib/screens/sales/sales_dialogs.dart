import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/sales_user_model.dart';
import '../../providers/qr_provider.dart';
import '../../providers/sales_admin_provider.dart';
import '../../providers/shop_provider.dart';
import '../../services/sales_repository.dart';
import '../../utils/app_colors.dart';
import '../../utils/qr_ranges.dart';
import '../../widgets/section_card.dart';
import 'sales_widgets.dart';

/// Where sales people sign in. Shown to the admin to pass on with the login.
const String salesLoginUrl = 'https://fullstarqr.com/app/';

String generatePassword([int length = 10]) {
  // No look-alike characters (0/O, 1/l/I), since this gets read out or typed.
  const alphabet = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = Random.secure();
  return List.generate(
    length,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}

// ---------------------------------------------------------------------------
// Add a sales person
// ---------------------------------------------------------------------------

class AddSalesPersonDialog extends StatefulWidget {
  const AddSalesPersonDialog({super.key});

  @override
  State<AddSalesPersonDialog> createState() => _AddSalesPersonDialogState();
}

class _AddSalesPersonDialogState extends State<AddSalesPersonDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _saving = false;
  String? _error;

  /// Set once the login exists. The password is only ever visible here.
  ({String name, String email, String password})? _created;

  @override
  void initState() {
    super.initState();
    _password.text = generatePassword();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final user = await context.read<SalesAdminProvider>().addSalesPerson(
        name: _name.text,
        email: _email.text,
        password: _password.text,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _created = (
          name: user.name,
          email: user.email,
          password: _password.text,
        );
      });
    } on SalesException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail('Could not create the login. Check your connection and try again.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = message;
    });
  }

  Future<void> _copyDetails() async {
    final c = _created!;
    await Clipboard.setData(
      ClipboardData(
        text:
            'Full Star QR sales login\n'
            'Sign in at: $salesLoginUrl\n'
            'Email: ${c.email}\n'
            'Password: ${c.password}',
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Login details copied.'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final created = _created;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        created == null ? 'Add sales person' : 'Login created',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: created == null ? _form() : _credentials(created),
        ),
      ),
      actions: created == null
          ? [
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
                    : const Text('Create login'),
              ),
            ]
          : [
              TextButton.icon(
                onPressed: _copyDetails,
                icon: const Icon(Icons.copy_rounded, size: 17),
                label: const Text('Copy login details'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
    );
  }

  Widget _form() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Name'),
        TextField(
          controller: _name,
          enabled: !_saving,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. Ravi Kumar',
            prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
          ),
        ),
        const SizedBox(height: 14),
        const FieldLabel('Email (their login)'),
        TextField(
          controller: _email,
          enabled: !_saving,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(
            hintText: 'name@example.com',
            prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
          ),
        ),
        const SizedBox(height: 14),
        const FieldLabel('Password'),
        TextField(
          controller: _password,
          enabled: !_saving,
          obscureText: !_showPassword,
          autocorrect: false,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
                IconButton(
                  tooltip: 'Generate a new password',
                  icon: const Icon(Icons.autorenew_rounded, size: 20),
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          _password.text = generatePassword();
                          _showPassword = true;
                        }),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'At least 6 characters. You will be shown it once after creating, to pass on. '
          'They can change it any time with "Forgot password?" on the sign-in page.',
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
    );
  }

  Widget _credentials(({String name, String email, String password}) c) {
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${c.name} can now sign in. Send them these details:',
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primaryLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row('Sign in at', salesLoginUrl),
              row('Email', c.email),
              row('Password', c.password),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'This password is not shown again after you close this.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Assign QR numbers
// ---------------------------------------------------------------------------

class AssignQrsDialog extends StatefulWidget {
  final SalesUser rep;
  const AssignQrsDialog({super.key, required this.rep});

  @override
  State<AssignQrsDialog> createState() => _AssignQrsDialogState();
}

class _AssignQrsDialogState extends State<AssignQrsDialog> {
  final _input = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  AssignPlan _plan() => context.read<SalesAdminProvider>().planAssignment(
    input: _input.text,
    qrCodes: context.read<QrProvider>().qrCodes,
    rep: widget.rep,
  );

  Future<void> _apply(AssignPlan plan) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final count = await context.read<SalesAdminProvider>().applyAssignment(
        plan,
        widget.rep,
      );
      if (mounted) Navigator.pop(context, count);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not assign. Check your connection and try again.';
      });
    }
  }

  static String _list(List<String> items, {int max = 12}) {
    if (items.length <= max) return items.join(', ');
    return '${items.take(max).join(', ')} and ${items.length - max} more';
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds on every keystroke, and when the provider changes.
    context.watch<SalesAdminProvider>();
    final plan = _plan();
    final hasInput = _input.text.trim().isNotEmpty;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Assign QR codes to ${widget.rep.name}',
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FieldLabel('QR numbers'),
              TextField(
                controller: _input,
                enabled: !_saving,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'e.g. 121-140, 145, 150',
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Type single numbers, ranges, or both, separated by commas.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              _availablePanel(),
              if (hasInput) ...[
                const SizedBox(height: 14),
                _line(
                  plan.canApply
                      ? 'Will assign ${plan.toAssign.length} QR code${plan.toAssign.length == 1 ? '' : 's'}: '
                            '${_list([for (final q in plan.toAssign) q.qrCode])}'
                      : 'Nothing to assign yet.',
                  plan.canApply ? StatusTone.good : StatusTone.neutral,
                ),
                if (plan.moving.isNotEmpty)
                  _line(
                    'Moving from another sales person: '
                    '${_list([for (final m in plan.moving) '${m.code} (${m.fromName})'], max: 6)}',
                    StatusTone.warning,
                  ),
                if (plan.alreadyWithRep.isNotEmpty)
                  _line(
                    'Already with ${widget.rep.name}: ${_list(plan.alreadyWithRep)}',
                    StatusTone.neutral,
                  ),
                if (plan.notFound.isNotEmpty)
                  _line(
                    'No such QR number: ${_list(plan.notFound)}',
                    StatusTone.danger,
                  ),
                if (plan.blocked.isNotEmpty)
                  _line(
                    'Can\'t assign: ${_list([for (final b in plan.blocked) '${b.code} (${b.reason})'], max: 6)}',
                    StatusTone.danger,
                  ),
                for (final e in plan.parseErrors) _line(e, StatusTone.danger),
              ],
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
          onPressed: (_saving || !plan.canApply) ? null : () => _apply(plan),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  plan.canApply ? 'Assign ${plan.toAssign.length}' : 'Assign',
                ),
        ),
      ],
    );
  }

  static const int _maxChips = 30;

  void _setInput(String text) {
    setState(() {
      _input.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
  }

  void _addToInput(String text) {
    final current = _input.text.trim().replaceAll(RegExp(r'[,;\s]+$'), '');
    _setInput(current.isEmpty ? text : '$current, $text');
  }

  /// The QR numbers nobody holds yet, as one-tap chips, so the admin doesn't
  /// have to remember which numbers are free.
  Widget _availablePanel() {
    final sales = context.read<SalesAdminProvider>();
    final ranges = toQrRanges(
      sales.availableDemoQrNumbers(
        qrCodes: context.read<QrProvider>().qrCodes,
        shops: context.read<ShopProvider>().shops,
      ),
    );
    final total = ranges.fold<int>(0, (sum, r) => sum + r.count);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryLight),
      ),
      child: total == 0
          ? const Text(
              'No free demo QR codes left. Generate more, or type a number above.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Available to assign: $total',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Demo QR codes nobody holds yet. Tap one to add it above.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final n in const [10, 20, 50])
                      if (total > n)
                        OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => _setInput(
                                  qrRangesInputText(takeFirstQrNumbers(ranges, n)),
                                ),
                          child: Text('First $n'),
                        ),
                    OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => _setInput(qrRangesInputText(ranges)),
                      child: Text('All $total'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final r in ranges.take(_maxChips))
                      ActionChip(
                        label: Text(
                          r.count > 1 ? '${r.label}  (${r.count})' : r.label,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        onPressed: _saving ? null : () => _addToInput(r.inputText),
                      ),
                  ],
                ),
                if (ranges.length > _maxChips) ...[
                  const SizedBox(height: 8),
                  Text(
                    '+ ${ranges.length - _maxChips} more groups. Use the buttons above or type the numbers.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _line(String text, StatusTone tone) {
    final color = switch (tone) {
      StatusTone.good => AppColors.primaryDark,
      StatusTone.warning => const Color(0xFF9A6B00),
      StatusTone.danger => AppColors.danger,
      StatusTone.neutral => AppColors.textSecondary,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: color,
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
