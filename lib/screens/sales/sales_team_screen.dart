import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/assignment_model.dart';
import '../../models/invoice_model.dart';
import '../../models/sales_user_model.dart';
import '../../providers/sales_admin_provider.dart';
import '../../providers/shop_provider.dart';
import '../../services/csv_download.dart';
import '../../services/invoice_pdf.dart';
import '../../services/sales_repository.dart';
import '../../utils/app_colors.dart';
import '../../utils/date_format.dart';
import '../../utils/invoice_report.dart';
import '../../utils/money_format.dart';
import '../../utils/sales_report.dart';
import '../../widgets/section_card.dart';
import 'invoice_dialog.dart';
import 'sales_dialogs.dart';
import 'sales_widgets.dart';

enum _Section { team, assigned, invoices, report }

/// The admin's sales area: create logins, hand out QR codes, unlock an edit,
/// and see who sold what.
class SalesTeamScreen extends StatefulWidget {
  const SalesTeamScreen({super.key});

  @override
  State<SalesTeamScreen> createState() => _SalesTeamScreenState();
}

class _SalesTeamScreenState extends State<SalesTeamScreen> {
  _Section _section = _Section.team;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 600;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isCompact ? 16 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sales Team',
            style: TextStyle(
              fontSize: isCompact ? 21 : 26,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Create sales logins, give them QR codes, and see who sold what.',
            style: TextStyle(fontSize: 14.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          const _PriceBar(),
          const SizedBox(height: 16),
          SegmentedButton<_Section>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: _Section.team,
                label: Text('Team'),
                icon: Icon(Icons.groups_rounded, size: 18),
              ),
              ButtonSegment(
                value: _Section.assigned,
                label: Text('Assigned QRs'),
                icon: Icon(Icons.qr_code_2_rounded, size: 18),
              ),
              ButtonSegment(
                value: _Section.invoices,
                label: Text('Invoices'),
                icon: Icon(Icons.receipt_long_rounded, size: 18),
              ),
              ButtonSegment(
                value: _Section.report,
                label: Text('Report'),
                icon: Icon(Icons.bar_chart_rounded, size: 18),
              ),
            ],
            selected: {_section},
            onSelectionChanged: (s) => setState(() => _section = s.first),
          ),
          const SizedBox(height: 20),
          switch (_section) {
            _Section.team => const _TeamSection(),
            _Section.assigned => const _AssignedSection(),
            _Section.invoices => const _InvoicesSection(),
            _Section.report => const _ReportSection(),
          },
        ],
      ),
    );
  }
}

String _msg(Object e) => e is SalesException
    ? e.message
    : 'Something went wrong. Check your connection and try again.';

void _snack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text),
      backgroundColor: error ? AppColors.danger : AppColors.primary,
    ),
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: danger
              ? ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                )
              : null,
          child: Text(action),
        ),
      ],
    ),
  );
  return result == true;
}

// ---------------------------------------------------------------------------
// Team
// ---------------------------------------------------------------------------

class _TeamSection extends StatelessWidget {
  const _TeamSection();

  Future<void> _add(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const AddSalesPersonDialog(),
  );

  Future<void> _assign(BuildContext context, SalesUser rep) async {
    final count = await showDialog<int>(
      context: context,
      builder: (_) => AssignQrsDialog(rep: rep),
    );
    if (count != null && count > 0 && context.mounted) {
      _snack(
        context,
        'Assigned $count QR code${count == 1 ? '' : 's'} to ${rep.name}.',
      );
    }
  }

  Future<void> _toggleActive(BuildContext context, SalesUser rep) async {
    final turningOff = rep.active;
    if (turningOff) {
      final ok = await _confirm(
        context,
        title: 'Turn off ${rep.name}?',
        body: 'They will not be able to sign in or see their QR codes. Their assigned QR codes and sales are kept, and you can turn them back on later.',
        action: 'Turn off',
        danger: true,
      );
      if (!ok || !context.mounted) return;
    }
    try {
      await context.read<SalesAdminProvider>().setActive(rep, !rep.active);
      if (context.mounted) {
        _snack(
          context,
          turningOff ? '${rep.name} turned off.' : '${rep.name} turned on.',
        );
      }
    } catch (e) {
      if (context.mounted) _snack(context, _msg(e), error: true);
    }
  }

  Future<void> _resetPassword(BuildContext context, SalesUser rep) async {
    final ok = await _confirm(
      context,
      title: 'Send password reset?',
      body: 'We will email a password reset link to ${rep.email}.',
      action: 'Send',
    );
    if (!ok || !context.mounted) return;
    try {
      await context.read<SalesAdminProvider>().sendPasswordReset(rep);
      if (context.mounted) _snack(context, 'Reset email sent to ${rep.email}.');
    } catch (e) {
      if (context.mounted) _snack(context, _msg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sales = context.watch<SalesAdminProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A Wrap, so on a narrow phone the count and the buttons stack
        // instead of running off the edge.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 4,
          children: [
            Text(
              '${sales.users.length} sales ${sales.users.length == 1 ? 'person' : 'people'}',
              style: const TextStyle(
                fontSize: 14.5,
                color: AppColors.textSecondary,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: sales.loading ? null : sales.load,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 4),
                ElevatedButton.icon(
                  onPressed: () => _add(context),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('Add sales person'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (sales.loading && sales.users.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          )
        else if (sales.loadError != null && sales.users.isEmpty)
          ErrorNote(message: sales.loadError!, onRetry: sales.load)
        else if (sales.users.isEmpty)
          const EmptyNote(
            icon: Icons.groups_outlined,
            message: 'No sales people yet.\nTap "Add sales person" to create their login.',
          )
        else
          for (final rep in sales.users)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _RepCard(
                rep: rep,
                assigned: sales.assignedCountFor(rep.uid),
                sold: sales.soldCountFor(rep.uid),
                pending: sales.pendingCountFor(rep.uid),
                onAssign: () => _assign(context, rep),
                onToggleActive: () => _toggleActive(context, rep),
                onResetPassword: () => _resetPassword(context, rep),
              ),
            ),
      ],
    );
  }
}

class _RepCard extends StatelessWidget {
  final SalesUser rep;
  final int assigned;
  final int sold;
  final int pending;
  final VoidCallback onAssign;
  final VoidCallback onToggleActive;
  final VoidCallback onResetPassword;

  const _RepCard({
    required this.rep,
    required this.assigned,
    required this.sold,
    required this.pending,
    required this.onAssign,
    required this.onToggleActive,
    required this.onResetPassword,
  });

  @override
  Widget build(BuildContext context) {
    final initial = rep.name.trim().isEmpty
        ? '?'
        : rep.name.trim()[0].toUpperCase();
    return SectionCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primaryLight,
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rep.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      rep.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              rep.active
                  ? const StatusChip('Active', tone: StatusTone.good)
                  : const StatusChip('Turned off', tone: StatusTone.danger),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              _Count('Assigned', assigned),
              _Count('Sold', sold),
              _Count('To do', pending),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: rep.active ? onAssign : null,
                icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                label: const Text('Assign QRs'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onResetPassword,
                icon: const Icon(Icons.lock_reset_rounded, size: 18),
                label: const Text('Reset password'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onToggleActive,
                icon: Icon(
                  rep.active
                      ? Icons.block_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 18,
                ),
                label: Text(rep.active ? 'Turn off' : 'Turn on'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  foregroundColor: rep.active
                      ? AppColors.danger
                      : AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  final String label;
  final int value;
  const _Count(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Assigned QRs
// ---------------------------------------------------------------------------

enum _StatusFilter { all, notSetUp, edited, unlocked }

/// What state an assignment is in, in the admin's words.
({String label, StatusTone tone}) assignmentStatus(Assignment a) {
  if (a.isSold && a.locked) {
    return (label: 'Edited - locked', tone: StatusTone.good);
  }
  if (a.isSold) {
    return (label: 'Unlocked for another edit', tone: StatusTone.warning);
  }
  if (a.locked) return (label: 'Locked', tone: StatusTone.danger);
  return (label: 'Not set up yet', tone: StatusTone.neutral);
}

class _AssignedSection extends StatefulWidget {
  const _AssignedSection();

  @override
  State<_AssignedSection> createState() => _AssignedSectionState();
}

class _AssignedSectionState extends State<_AssignedSection> {
  static const int _maxShown = 200;

  final _search = TextEditingController();
  String _query = '';
  String? _repUid;
  _StatusFilter _status = _StatusFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matchesStatus(Assignment a) => switch (_status) {
    _StatusFilter.all => true,
    _StatusFilter.notSetUp => !a.isSold,
    _StatusFilter.edited => a.isSold && a.locked,
    _StatusFilter.unlocked => a.isSold && !a.locked,
  };

  Future<void> _unlock(Assignment a) async {
    final ok = await _confirm(
      context,
      title: 'Allow another edit?',
      body:
          '${a.assignedToName} will be able to change ${a.qrCode} one more time. It locks again as soon as they save.',
      action: 'Allow edit',
    );
    if (!ok || !mounted) return;
    try {
      await context.read<SalesAdminProvider>().unlock(a);
      if (mounted) {
        _snack(context, '${a.qrCode} is unlocked for ${a.assignedToName}.');
      }
    } catch (e) {
      if (mounted) _snack(context, _msg(e), error: true);
    }
  }

  /// Makes the invoice for a sold QR (asking for the details the first time)
  /// and downloads it. A QR that already has one just downloads it again.
  Future<void> _invoice(Assignment a, String? shopName) async {
    var invoice = context.read<SalesAdminProvider>().invoiceFor(a.shopId);
    if (invoice == null) {
      final sales = context.read<SalesAdminProvider>();
      invoice = await showDialog<Invoice>(
        context: context,
        builder: (_) => CreateInvoiceDialog(
          assignment: a,
          shopName: shopName,
          initialPrice: sales.defaultPrice,
          onCreate: ({
            required clientName,
            required clientPhone,
            required clientAddress,
            required price,
          }) => sales.createInvoice(
            a,
            clientName: clientName,
            clientPhone: clientPhone,
            clientAddress: clientAddress,
            price: price,
          ),
        ),
      );
      if (invoice == null || !mounted) return;
    }
    try {
      await invoiceDownloader(invoice);
      if (mounted) _snack(context, 'Invoice ${invoice.numberText} downloaded.');
    } catch (_) {
      if (mounted) {
        _snack(
          context,
          'Invoice ${invoice.numberText} was saved, but the PDF could not be made. Tap it again to retry.',
          error: true,
        );
      }
    }
  }

  Future<void> _takeBack(Assignment a) async {
    final ok = await _confirm(
      context,
      title: 'Take back ${a.qrCode}?',
      body:
          '${a.qrCode} will no longer be assigned to ${a.assignedToName}. You can assign it again later.',
      action: 'Take back',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await context.read<SalesAdminProvider>().unassign(a);
      if (mounted) _snack(context, '${a.qrCode} taken back.');
    } catch (e) {
      if (mounted) _snack(context, _msg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sales = context.watch<SalesAdminProvider>();
    final shopNames = {
      for (final s in context.watch<ShopProvider>().shops) s.shopId: s.shopName,
    };

    final q = _query.trim().toLowerCase();
    final asCode = RegExp(r'^\d+$').hasMatch(q) ? 'qr$q' : q;
    final rows =
        sales.assignments.where((a) {
          if (_repUid != null && a.assignedTo != _repUid) return false;
          if (!_matchesStatus(a)) return false;
          if (q.isEmpty) return true;
          return a.qrCode.toLowerCase().contains(q) ||
              (shopNames[a.shopId] ?? '').toLowerCase().contains(q) ||
              a.assignedToName.toLowerCase().contains(q);
        }).toList()..sort((a, b) {
          final aExact = a.qrCode.toLowerCase() == asCode ? 0 : 1;
          final bExact = b.qrCode.toLowerCase() == asCode ? 0 : 1;
          if (aExact != bExact) return aExact.compareTo(bExact);
          return _number(a.qrCode).compareTo(_number(b.qrCode));
        });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search QR number, shop or person',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String?>(
                initialValue: _repUid,
                isExpanded: true,
                decoration: const InputDecoration(),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All sales people'),
                  ),
                  for (final u in sales.users)
                    DropdownMenuItem<String?>(
                      value: u.uid,
                      child: Text(u.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _repUid = v),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<_StatusFilter>(
                initialValue: _status,
                isExpanded: true,
                decoration: const InputDecoration(),
                items: const [
                  DropdownMenuItem(
                    value: _StatusFilter.all,
                    child: Text('Any status'),
                  ),
                  DropdownMenuItem(
                    value: _StatusFilter.notSetUp,
                    child: Text('Not set up yet'),
                  ),
                  DropdownMenuItem(
                    value: _StatusFilter.edited,
                    child: Text('Edited - locked'),
                  ),
                  DropdownMenuItem(
                    value: _StatusFilter.unlocked,
                    child: Text('Unlocked for edit'),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => _status = v ?? _StatusFilter.all),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '${rows.length} of ${sales.assignments.length} assigned QR codes',
          style: const TextStyle(
            fontSize: 13.5,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        if (sales.loading && sales.assignments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          )
        else if (sales.loadError != null && sales.assignments.isEmpty)
          ErrorNote(message: sales.loadError!, onRetry: sales.load)
        else if (sales.assignments.isEmpty)
          const EmptyNote(
            icon: Icons.qr_code_2_rounded,
            message: 'No QR codes are assigned yet.\nOpen the Team tab and tap "Assign QRs" on a sales person.',
          )
        else if (rows.isEmpty)
          const EmptyNote(
            icon: Icons.search_off_rounded,
            message: 'No assigned QR codes match.',
          )
        else ...[
          for (final a in rows.take(_maxShown))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AssignmentRow(
                assignment: a,
                shopName: shopNames[a.shopId],
                invoice: sales.invoiceFor(a.shopId),
                onInvoice: () => _invoice(a, shopNames[a.shopId]),
                onUnlock: () => _unlock(a),
                onTakeBack: () => _takeBack(a),
              ),
            ),
          if (rows.length > _maxShown)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Showing the first $_maxShown. Search or filter to narrow it down.',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ],
    );
  }

  static int _number(String code) =>
      int.tryParse(code.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1 << 30;
}

class _AssignmentRow extends StatelessWidget {
  final Assignment assignment;
  final String? shopName;
  final Invoice? invoice;
  final VoidCallback onInvoice;
  final VoidCallback onUnlock;
  final VoidCallback onTakeBack;

  const _AssignmentRow({
    required this.assignment,
    required this.shopName,
    required this.invoice,
    required this.onInvoice,
    required this.onUnlock,
    required this.onTakeBack,
  });

  @override
  Widget build(BuildContext context) {
    final a = assignment;
    final status = assignmentStatus(a);
    final details = [
      a.assignedToName,
      if (a.assignedAt != null) 'Assigned ${formatShortDate(a.assignedAt!)}',
      if (a.soldAt != null) 'Saved ${formatShortDate(a.soldAt!)}',
    ].join('  -  ');

    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              QrCodeChip(a.qrCode),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  shopName ?? 'Unknown shop',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(status.label, tone: status.tone),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            details,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
          if (invoice != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Invoiced ${invoice!.numberText}  -  Rs. ${formatRupees(invoice!.amount)}  -  ${invoice!.clientName}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
          ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (a.isSold)
                  ElevatedButton.icon(
                    onPressed: onInvoice,
                    icon: Icon(
                      invoice == null
                          ? Icons.receipt_long_rounded
                          : Icons.download_rounded,
                      size: 16,
                    ),
                    label: Text(
                      invoice == null
                          ? 'Create invoice'
                          : 'Invoice ${invoice!.numberText}',
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (a.locked)
                  OutlinedButton.icon(
                    onPressed: onUnlock,
                    icon: const Icon(Icons.lock_open_rounded, size: 16),
                    label: const Text('Allow edit again'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                if (!a.isSold)
                  OutlinedButton.icon(
                    onPressed: onTakeBack,
                    icon: const Icon(Icons.undo_rounded, size: 16),
                    label: const Text('Take back'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                      foregroundColor: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Invoices
// ---------------------------------------------------------------------------

enum _MadeBy { anyone, admin, rep }

class _InvoicesSection extends StatefulWidget {
  const _InvoicesSection();

  @override
  State<_InvoicesSection> createState() => _InvoicesSectionState();
}

class _InvoicesSectionState extends State<_InvoicesSection> {
  static const int _maxShown = 200;

  final _search = TextEditingController();
  String _query = '';
  String? _repUid;
  _MadeBy _madeBy = _MadeBy.anyone;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Invoice> _filtered(List<Invoice> all) {
    final q = _query.trim().toLowerCase();
    return all.where((i) {
      if (_repUid != null && i.soldByUid != _repUid) return false;
      if (_madeBy == _MadeBy.admin && i.createdByRep) return false;
      if (_madeBy == _MadeBy.rep && !i.createdByRep) return false;
      if (q.isEmpty) return true;
      return i.numberText.toLowerCase().contains(q) ||
          i.qrCode.toLowerCase().contains(q) ||
          i.clientName.toLowerCase().contains(q) ||
          i.soldByName.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _download(Invoice invoice) async {
    try {
      await invoiceDownloader(invoice);
      if (mounted) _snack(context, 'Invoice ${invoice.numberText} downloaded.');
    } catch (_) {
      if (mounted) {
        _snack(
          context,
          'The PDF for ${invoice.numberText} could not be made. Try again.',
          error: true,
        );
      }
    }
  }

  void _downloadCsv(List<Invoice> shown) {
    downloadCsv(content: InvoiceReport.csv(shown), fileName: 'invoices.csv');
  }

  @override
  Widget build(BuildContext context) {
    final sales = context.watch<SalesAdminProvider>();
    final all = sales.invoices;
    final shown = _filtered(all);
    final perRep = InvoiceReport.perRep(all);
    final soldNotInvoiced = sales.assignments
        .where((a) => a.isSold && sales.invoiceFor(a.shopId) == null)
        .length;

    Widget stat(String label, String value) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            stat('Invoices', '${all.length}'),
            const SizedBox(width: 10),
            stat(
              'Total billed',
              'Rs. ${formatRupees(InvoiceReport.totalAmount(all))}',
            ),
            const SizedBox(width: 10),
            stat('Sold, not invoiced', '$soldNotInvoiced'),
          ],
        ),
        if (perRep.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'By sales person',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                for (final t in perRep)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            t.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${t.count} invoice${t.count == 1 ? '' : 's'}'
                            '${t.byRep > 0 ? ' (${t.byRep} made by them)' : ''}'
                            '  -  Rs. ${formatRupees(t.amount)}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search invoice, QR, client or person',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String?>(
                initialValue: _repUid,
                isExpanded: true,
                decoration: const InputDecoration(),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All sales people'),
                  ),
                  for (final u in sales.users)
                    DropdownMenuItem<String?>(
                      value: u.uid,
                      child: Text(u.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _repUid = v),
              ),
            ),
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<_MadeBy>(
                initialValue: _madeBy,
                isExpanded: true,
                decoration: const InputDecoration(),
                items: const [
                  DropdownMenuItem(
                    value: _MadeBy.anyone,
                    child: Text('Made by anyone'),
                  ),
                  DropdownMenuItem(
                    value: _MadeBy.admin,
                    child: Text('Made by admin'),
                  ),
                  DropdownMenuItem(
                    value: _MadeBy.rep,
                    child: Text('Made by sales person'),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => _madeBy = v ?? _MadeBy.anyone),
              ),
            ),
            OutlinedButton.icon(
              onPressed: shown.isEmpty ? null : () => _downloadCsv(shown),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download invoices (CSV)'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '${shown.length} of ${all.length} invoices',
          style: const TextStyle(
            fontSize: 13.5,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        if (sales.loading && all.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          )
        else if (all.isEmpty)
          const EmptyNote(
            icon: Icons.receipt_long_rounded,
            message:
                'No invoices yet.\nThey appear here when you or a sales person makes one.',
          )
        else if (shown.isEmpty)
          const EmptyNote(
            icon: Icons.search_off_rounded,
            message: 'No invoices match.',
          )
        else ...[
          for (final i in shown.take(_maxShown))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _InvoiceRow(invoice: i, onDownload: () => _download(i)),
            ),
          if (shown.length > _maxShown)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Showing the latest 200. Search or filter to narrow it down. The CSV has all of the matching invoices.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
        ],
      ],
    );
  }
}

/// The fixed invoice price, with the button to change it. It sits above the
/// tabs so the admin can set it from anywhere in the Sales Team area.
class _PriceBar extends StatelessWidget {
  const _PriceBar();

  Future<void> _edit(BuildContext context) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _PriceDialog(initial: context.read<SalesAdminProvider>().defaultPrice),
    );
    if (saved == true && context.mounted) {
      _snack(context, 'Invoice price saved.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = context.watch<SalesAdminProvider>().defaultPrice;
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.sell_outlined, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  price == null
                      ? 'Invoice price not set'
                      : 'Invoice price: Rs. ${formatRupees(price)} per QR',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  price == null
                      ? 'Sales people cannot make invoices until you set it.'
                      : 'Sales people invoice at this price and cannot change it.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => _edit(context),
            child: Text(price == null ? 'Set price' : 'Change'),
          ),
        ],
      ),
    );
  }
}

class _PriceDialog extends StatefulWidget {
  final int? initial;
  const _PriceDialog({required this.initial});

  @override
  State<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends State<_PriceDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial == null ? '' : '${widget.initial}',
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<SalesAdminProvider>().setPrice(_controller.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _msg(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Invoice price per QR',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sales people make their invoices at this price and cannot change it. Invoices that already exist keep their own price.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            const FieldLabel('Price (Rs.)'),
            TextField(
              controller: _controller,
              autofocus: true,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'e.g. 1500',
                prefixIcon: Icon(Icons.currency_rupee_rounded, size: 20),
              ),
              onSubmitted: (_) => _saving ? null : _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
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
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save price'),
        ),
      ],
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  final Invoice invoice;
  final VoidCallback onDownload;
  const _InvoiceRow({required this.invoice, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final i = invoice;
    final details = [
      'Sold by ${i.soldByName.isEmpty ? 'unknown' : i.soldByName}',
      'Made by ${i.createdByLabel}',
      if (i.issuedAt != null) formatShortDate(i.issuedAt!),
    ].join('  -  ');

    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusChip(i.numberText, tone: StatusTone.good),
              const SizedBox(width: 8),
              QrCodeChip(i.qrCode),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  i.clientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Rs. ${formatRupees(i.amount)}',
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            details,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onDownload,
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: Text('Download ${i.numberText}'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------

class _ReportSection extends StatefulWidget {
  const _ReportSection();

  @override
  State<_ReportSection> createState() => _ReportSectionState();
}

class _ReportSectionState extends State<_ReportSection> {
  DateTime? _from;
  DateTime? _to;
  String _preset = 'month';

  @override
  void initState() {
    super.initState();
    _applyPreset('month');
  }

  void _applyPreset(String preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _preset = preset;
    switch (preset) {
      case 'today':
        _from = today;
        _to = today;
      case 'week':
        _from = today.subtract(const Duration(days: 6));
        _to = today;
      case 'month':
        _from = DateTime(now.year, now.month, 1);
        _to = today;
      case 'all':
        _from = null;
        _to = null;
    }
  }

  Future<void> _pick({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = (isFrom ? _from : _to) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      _preset = 'custom';
      if (isFrom) {
        _from = picked;
        if (_to != null && _to!.isBefore(picked)) _to = picked;
      } else {
        _to = picked;
        if (_from != null && _from!.isAfter(picked)) _from = picked;
      }
    });
  }

  void _download(SalesReport report, {required bool sold}) {
    final stamp = report.from == null && report.to == null
        ? 'all-time'
        : '${report.from == null ? 'start' : SalesReport.formatDate(report.from!)}_to_${report.to == null ? 'today' : SalesReport.formatDate(report.to!)}';
    downloadCsv(
      content: sold ? report.soldCsv() : report.summaryCsv(),
      fileName: sold
          ? 'sales_sold_list_$stamp.csv'
          : 'sales_summary_$stamp.csv',
    );
  }

  @override
  Widget build(BuildContext context) {
    final sales = context.watch<SalesAdminProvider>();
    final shopNames = {
      for (final s in context.watch<ShopProvider>().shops) s.shopId: s.shopName,
    };
    final report = SalesReport.build(
      assignments: sales.assignments,
      users: sales.users,
      shopNames: shopNames,
      from: _from,
      to: _to,
    );

    Widget chip(String id, String label) => ChoiceChip(
      label: Text(label),
      selected: _preset == id,
      onSelected: (_) => setState(() => _applyPreset(id)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FieldLabel('Date range'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  chip('today', 'Today'),
                  chip('week', 'Last 7 days'),
                  chip('month', 'This month'),
                  chip('all', 'All time'),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _pick(isFrom: true),
                    icon: const Icon(Icons.calendar_today_rounded, size: 16),
                    label: Text(
                      'From: ${_from == null ? 'start' : formatShortDate(_from!)}',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pick(isFrom: false),
                    icon: const Icon(Icons.event_rounded, size: 16),
                    label: Text(
                      'To: ${_to == null ? 'today' : formatShortDate(_to!)}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                '${report.totalSold} sold  -  ${report.rangeLabel}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: report.summaries.isEmpty
                  ? null
                  : () => _download(report, sold: false),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download summary (CSV)'),
            ),
            OutlinedButton.icon(
              onPressed: report.soldRows.isEmpty
                  ? null
                  : () => _download(report, sold: true),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download sold list (CSV)'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (sales.loading && sales.users.isEmpty && sales.assignments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          )
        else if (report.summaries.isEmpty)
          const EmptyNote(
            icon: Icons.bar_chart_rounded,
            message:
                'Add a sales person and assign them QR codes to see a report.',
          )
        else ...[
          SectionCard(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingTextStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  fontSize: 13,
                ),
                columns: const [
                  DataColumn(label: Text('Sales person')),
                  DataColumn(label: Text('Assigned'), numeric: true),
                  DataColumn(label: Text('Sold'), numeric: true),
                  DataColumn(label: Text('To do now'), numeric: true),
                ],
                rows: [
                  for (final s in report.summaries)
                    DataRow(
                      cells: [
                        DataCell(Text(s.name)),
                        DataCell(Text('${s.assignedInRange}')),
                        DataCell(
                          Text(
                            '${s.soldInRange}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        DataCell(Text('${s.pendingNow}')),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Assigned and Sold count only the dates above. "Sold" is the day the sales person first saved the QR. "To do now" is everything still waiting, whatever the dates.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Sold in this range (${report.soldRows.length})',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          if (report.soldRows.isEmpty)
            const EmptyNote(
              icon: Icons.inbox_outlined,
              message: 'Nothing sold in this date range.',
            )
          else
            SectionCard(
              padding: EdgeInsets.zero,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingTextStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                  columns: const [
                    DataColumn(label: Text('Sold on')),
                    DataColumn(label: Text('QR')),
                    DataColumn(label: Text('Shop')),
                    DataColumn(label: Text('Sales person')),
                  ],
                  rows: [
                    for (final r in report.soldRows.take(300))
                      DataRow(
                        cells: [
                          DataCell(Text(formatShortDate(r.soldAt))),
                          DataCell(
                            Text(
                              r.qrCode,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 260),
                              child: Text(
                                r.shopName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(Text(r.repName)),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          if (report.soldRows.length > 300)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Showing the latest 300. The CSV download has them all.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
        ],
      ],
    );
  }
}
