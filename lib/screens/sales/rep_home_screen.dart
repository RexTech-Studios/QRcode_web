import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/invoice_model.dart';
import '../../providers/rep_provider.dart';
import '../../services/auth_service.dart';
import '../../services/invoice_pdf.dart';
import '../../services/sales_repository.dart';
import '../../utils/app_colors.dart';
import '../../utils/date_format.dart';
import '../../utils/money_format.dart';
import '../../widgets/section_card.dart';
import 'invoice_dialog.dart';
import 'sales_widgets.dart';

/// What a sales person sees after signing in: only the QR codes the admin
/// assigned to them. Each can be set up for a real client once; after that it
/// is locked until the admin unlocks it.
class RepHomeScreen extends StatefulWidget {
  const RepHomeScreen({super.key});

  @override
  State<RepHomeScreen> createState() => _RepHomeScreenState();
}

class _RepHomeScreenState extends State<RepHomeScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RepItem> _filter(List<RepItem> items) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return items;
    final asCode = RegExp(r'^\d+$').hasMatch(q) ? 'qr$q' : q;
    final matches = items
        .where(
          (i) =>
              i.assignment.qrCode.toLowerCase().contains(q) ||
              i.shopName.toLowerCase().contains(q),
        )
        .toList();
    // An exact QR number goes first, so typing "296" finds QR296 even though
    // "2960" also contains it.
    matches.sort((a, b) {
      final aExact = a.assignment.qrCode.toLowerCase() == asCode ? 0 : 1;
      final bExact = b.assignment.qrCode.toLowerCase() == asCode ? 0 : 1;
      return aExact.compareTo(bExact);
    });
    return matches;
  }

  Future<void> _refresh() async {
    final provider = context.read<RepProvider>();
    final user = provider.user;
    if (user != null) await provider.load(user);
  }

  Future<void> _openSetup(RepItem item) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _SetupDialog(item: item),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved. This QR is now locked.'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  /// Makes the invoice for a QR that has been set up (asking for the client's
  /// details the first time) and downloads it. A QR that already has one just
  /// downloads it again.
  Future<void> _invoice(RepItem item) async {
    final provider = context.read<RepProvider>();
    var invoice = provider.invoiceFor(item.assignment.shopId);
    if (invoice == null) {
      if (provider.price == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The invoice price has not been set yet. Ask the admin to set it.',
            ),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }
      invoice = await showDialog<Invoice>(
        context: context,
        builder: (_) => CreateInvoiceDialog(
          assignment: item.assignment,
          shopName: item.shop?.shopName,
          initialPrice: provider.price,
          priceLocked: true,
          onCreate: ({
            required clientName,
            required clientPhone,
            required clientAddress,
            required price,
          }) => provider.createInvoice(
            item,
            clientName: clientName,
            clientPhone: clientPhone,
            clientAddress: clientAddress,
          ),
        ),
      );
      if (invoice == null || !mounted) return;
    }
    try {
      await invoiceDownloader(invoice);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invoice ${invoice.numberText} downloaded.'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Invoice ${invoice.numberText} was saved, but the PDF could not be made. Tap it again to retry.',
            ),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RepProvider>();
    final items = _filter(provider.items);
    final isCompact = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            _Header(name: provider.user?.name ?? ''),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: _refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.all(isCompact ? 16 : 24),
                      children: [
                        Text(
                          'My QR codes',
                          style: TextStyle(
                            fontSize: isCompact ? 21 : 26,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Set up each QR for your client once. After you save, only the admin can unlock it.',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _Stats(
                          assigned: provider.items.length,
                          done: provider.doneCount,
                          pending: provider.pendingCount,
                        ),
                        if (provider.invoicedCount > 0) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Invoiced: ${provider.invoicedCount}  -  Rs. ${formatRupees(provider.invoicedTotal)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        TextField(
                          controller: _searchController,
                          onChanged: (v) => setState(() => _query = v),
                          decoration: InputDecoration(
                            hintText:
                                'Search by QR number (e.g. 121) or shop name',
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 20,
                            ),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _query = '');
                                    },
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (provider.loading && provider.items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 48),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                              ),
                            ),
                          )
                        else if (provider.loadError != null &&
                            provider.items.isEmpty)
                          ErrorNote(
                            message: provider.loadError!,
                            onRetry: _refresh,
                          )
                        else if (provider.items.isEmpty)
                          const EmptyNote(
                            icon: Icons.qr_code_2_rounded,
                            message: 'No QR codes have been assigned to you yet.\nAsk the admin to assign some.',
                          )
                        else if (items.isEmpty)
                          const EmptyNote(
                            icon: Icons.search_off_rounded,
                            message: 'None of your QR codes match that search.',
                          )
                        else
                          for (final item in items)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _ItemCard(
                                item: item,
                                invoice: provider.invoiceFor(
                                  item.assignment.shopId,
                                ),
                                onSetUp: () => _openSetup(item),
                                onInvoice: () => _invoice(item),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String name;
  const _Header({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.chat_bubble, color: Colors.white, size: 17),
          ),
          const SizedBox(width: 10),
          const Flexible(
            child: Text(
              'Full Star QR',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const Spacer(),
          if (name.isNotEmpty)
            Flexible(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: AuthService.signOut,
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Logout'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              textStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  final int assigned;
  final int done;
  final int pending;
  const _Stats({
    required this.assigned,
    required this.done,
    required this.pending,
  });

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, int value) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
    return Row(
      children: [
        cell('Assigned', assigned),
        const SizedBox(width: 10),
        cell('Done', done),
        const SizedBox(width: 10),
        cell('To do', pending),
      ],
    );
  }
}

class _ItemCard extends StatelessWidget {
  final RepItem item;
  final Invoice? invoice;
  final VoidCallback onSetUp;
  final VoidCallback onInvoice;
  const _ItemCard({
    required this.item,
    required this.invoice,
    required this.onSetUp,
    required this.onInvoice,
  });

  @override
  Widget build(BuildContext context) {
    final a = item.assignment;
    final locked = a.locked;
    final soldAt = a.soldAt;

    return SectionCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              QrCodeChip(a.qrCode),
              const SizedBox(width: 8),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: locked
                      ? const StatusChip('Saved - locked', tone: StatusTone.good)
                      : const StatusChip(
                          'Ready to set up',
                          tone: StatusTone.warning,
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item.shopName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          if (soldAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Saved on ${formatShortDate(soldAt)}',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textMuted,
              ),
            ),
          ],
          if (invoice != null) ...[
            const SizedBox(height: 4),
            Text(
              'Invoiced ${invoice!.numberText}  -  Rs. ${formatRupees(invoice!.amount)}  -  ${invoice!.clientName}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryDark,
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (a.isSold) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onInvoice,
                icon: Icon(
                  invoice == null
                      ? Icons.receipt_long_rounded
                      : Icons.download_rounded,
                  size: 17,
                ),
                label: Text(
                  invoice == null
                      ? 'Create invoice'
                      : 'Invoice ${invoice!.numberText}',
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (item.shop != null) ...[
            _SheetButton(item: item),
            const SizedBox(height: 10),
          ],
          if (locked)
            const Text(
              'To change this again, ask the admin to unlock it.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onSetUp,
                icon: const Icon(Icons.edit_rounded, size: 17),
                label: const Text('Set up for client'),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Open sheet" when the shop has its feedback Google Sheet, otherwise
/// "Generate sheet", which creates one and attaches it.
class _SheetButton extends StatefulWidget {
  final RepItem item;
  const _SheetButton({required this.item});

  @override
  State<_SheetButton> createState() => _SheetButtonState();
}

class _SheetButtonState extends State<_SheetButton> {
  bool _busy = false;

  String get _url => widget.item.shop?.googleSheetsUrl?.trim() ?? '';

  void _say(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppColors.danger : AppColors.primary,
      ),
    );
  }

  Future<void> _open() async {
    final uri = Uri.tryParse(_url);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) _say('Could not open the Google Sheet.', error: true);
    }
  }

  Future<void> _generate() async {
    setState(() => _busy = true);
    try {
      await context.read<RepProvider>().generateSheet(widget.item);
      if (mounted) _say('Google Sheet created for this shop.');
    } on SalesException catch (e) {
      if (mounted) _say(e.message, error: true);
    } catch (_) {
      if (mounted) {
        _say('Could not create the Google Sheet. Try again.', error: true);
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final hasSheet = _url.isNotEmpty;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _busy ? null : (hasSheet ? _open : _generate),
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                hasSheet
                    ? Icons.table_chart_outlined
                    : Icons.add_chart_outlined,
                size: 17,
              ),
        label: Text(
          _busy
              ? 'Generating...'
              : hasSheet
              ? 'Open sheet'
              : 'Generate sheet',
        ),
      ),
    );
  }
}

class _SetupDialog extends StatefulWidget {
  final RepItem item;
  const _SetupDialog({required this.item});

  @override
  State<_SetupDialog> createState() => _SetupDialogState();
}

class _SetupDialogState extends State<_SetupDialog> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item.shop?.shopName ?? '');
    _url = TextEditingController(text: widget.item.shop?.googleReviewUrl ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = RepProvider.validateSetup(_name.text, _url.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    // The one edit can't be taken back, so confirm before using it.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Save and lock?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'You are saving "${_name.text.trim()}" for ${widget.item.assignment.qrCode}.\n\n'
          'You can only do this once. To change it later, the admin has to unlock it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Go back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save and lock'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<RepProvider>().saveSetup(
        widget.item,
        shopName: _name.text,
        reviewUrl: _url.text,
      );
      if (mounted) Navigator.pop(context, true);
    } on SalesException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Could not save. Check your connection and try again.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          QrCodeChip(widget.item.assignment.qrCode),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Set up for client',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.amberAccentBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'You can save this only once. After that it is locked until the admin unlocks it.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF7A5200),
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const FieldLabel('Shop name'),
              TextField(
                controller: _name,
                enabled: !_saving,
                maxLength: 100,
                decoration: const InputDecoration(
                  hintText: "Your client's shop name",
                  counterText: '',
                  prefixIcon: Icon(Icons.storefront_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 14),
              const FieldLabel('Google Maps review link'),
              TextField(
                controller: _url,
                enabled: !_saving,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  hintText: 'https://g.page/r/.../review',
                  prefixIcon: Icon(Icons.link_rounded, size: 20),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Paste the "Write a review" link from your client\'s Google Maps business.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
