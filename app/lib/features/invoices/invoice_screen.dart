import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/big_button.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_repository.dart';
import '../groups/role_labels.dart';
import '../jobs/job_labels.dart';
import '../jobs/jobs_repository.dart';
import '../spaces/spaces_repository.dart';
import 'invoice_labels.dart';
import 'invoice_models.dart';
import 'invoice_pdf.dart';
import 'invoices_repository.dart';

class InvoiceScreen extends ConsumerWidget {
  const InvoiceScreen({
    super.key,
    required this.spaceId,
    required this.invoiceId,
  });
  final String spaceId;
  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final inv = ref.watch(invoiceProvider((spaceId, invoiceId))).value;
    final profile = ref.watch(businessProfileProvider(spaceId)).value;
    final me = ref.watch(currentUserProvider).value?.id ?? '';
    final space = ref
        .watch(mySpacesProvider)
        .value
        ?.where((s) => s.id == spaceId)
        .firstOrNull;
    final manager = roleAtLeast(
      space?.myRole ?? MemberRole.viewer,
      MemberRole.manager,
    );
    if (inv == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final job = inv.jobId == null
        ? null
        : ref.watch(jobProvider((spaceId, inv.jobId!))).value;
    final canBill = manager || (job?.isAssignedTo(me) ?? false);
    final color = invoiceStatusColor(inv.status);
    final livePayments = inv.payments.where((p) => !p.isVoided).toList();

    Widget totalRow(String label, int paisa, {bool bold = false, Color? c}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: (bold ? text.titleMedium : text.bodyLarge)?.copyWith(
                    fontWeight: bold ? FontWeight.w800 : null,
                    color: c,
                  ),
                ),
              ),
              Text(
                'Rs ${Money.format(paisa)}',
                style: (bold ? text.titleMedium : text.bodyLarge)?.copyWith(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w800,
                  color: c,
                ),
              ),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(inv.number),
        actions: [
          if (manager && !inv.isVoid)
            PopupMenuButton<String>(
              onSelected: (_) => _void(context, ref, inv),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'void',
                  child: ListTile(
                    leading: Icon(Icons.cancel_outlined, color: scheme.error),
                    title: Text(
                      l.voidInvoice,
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Tokens.s4,
          Tokens.s2,
          Tokens.s4,
          Tokens.s7 * 3,
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(Tokens.s4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, Color.lerp(color, Tokens.indigoDeep, 0.45)!],
              ),
              borderRadius: BorderRadius.circular(Tokens.radiusLarge),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        inv.customerName,
                        style: text.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        invoiceStatusLabel(l, inv.status),
                        style: text.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                if (inv.jobTitle != null)
                  Text(
                    inv.jobTitle!,
                    style: text.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                Text(
                  l.issuedOn(DateFormat.yMMMd(locale).format(inv.issuedAt)),
                  style: text.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: Tokens.s3),
                Text(
                  l.total,
                  style: text.labelLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                Text(
                  'Rs ${Money.format(inv.totalPaisa)}',
                  style: text.displaySmall?.copyWith(
                    color: Colors.white,
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: Tokens.s2),
                Row(
                  children: [
                    Expanded(
                      child: _HeroStat(
                        label: l.received,
                        value: 'Rs ${Money.format(inv.receivedPaisa)}',
                      ),
                    ),
                    Expanded(
                      child: _HeroStat(
                        label: l.balanceDue,
                        value: 'Rs ${Money.format(inv.balancePaisa)}',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (inv.isVoid)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.s3),
              child: Container(
                padding: const EdgeInsets.all(Tokens.s3),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(Tokens.radius),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.block),
                    const SizedBox(width: Tokens.s2),
                    Expanded(
                      child: Text(
                        '${l.invoiceStatusVoid}${inv.voidedAt == null ? '' : ' · ${DateFormat.yMMMd(locale).format(inv.voidedAt!.toLocal())}'}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: Tokens.s5),
          Text(
            l.itemsUsed,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: Tokens.s2),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Tokens.s3),
              child: Column(
                children: [
                  for (final line in inv.lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  line.description,
                                  style: text.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${formatQty(line.qty)}${line.unit == null ? '' : ' ${unitLabel(l, line.unit!)}'} × Rs ${Money.format(line.unitPricePaisa)}',
                                  style: text.bodySmall?.copyWith(
                                    fontFamily: 'Roboto',
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            'Rs ${Money.format(line.amountPaisa)}',
                            style: text.bodyLarge?.copyWith(
                              fontFamily: 'Roboto',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  totalRow(l.subtotal, inv.subtotalPaisa),
                  if (inv.discountPaisa > 0)
                    totalRow(l.discount, -inv.discountPaisa),
                  if (inv.taxPaisa > 0)
                    totalRow(
                      l.taxWithRate((inv.taxRateBp / 100).toString()),
                      inv.taxPaisa,
                    ),
                  totalRow(l.total, inv.totalPaisa, bold: true),
                  if (inv.receivedPaisa > 0)
                    totalRow(l.received, inv.receivedPaisa, c: Tokens.get),
                  if (!inv.isVoid)
                    totalRow(
                      l.balanceDue,
                      inv.balancePaisa,
                      bold: true,
                      c: inv.balancePaisa > 0 ? Tokens.saffronDeep : Tokens.get,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Tokens.s5),
          Text(
            l.payments,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: Tokens.s2),
          if (inv.payments.isEmpty)
            Text(
              l.noPaymentsYet,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          for (final p in inv.payments)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: (p.isVoided ? Tokens.muted : Tokens.get)
                    .withValues(alpha: 0.15),
                child: Icon(
                  methodIcon(p.method),
                  color: p.isVoided ? Tokens.muted : Tokens.get,
                ),
              ),
              title: Text(
                'Rs ${Money.format(p.amountPaisa)}',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w800,
                  decoration: p.isVoided ? TextDecoration.lineThrough : null,
                ),
              ),
              subtitle: Text(
                [
                  methodLabel(l, p.method),
                  DateFormat.yMMMd(locale).format(p.paidAt),
                  if (p.note?.isNotEmpty ?? false) p.note!,
                  if (p.isVoided) l.cancelled,
                ].join('  ·  '),
              ),
            ),
          if (inv.notes?.isNotEmpty ?? false) ...[
            const SizedBox(height: Tokens.s4),
            Text(inv.notes!, style: text.bodyMedium),
          ],
          if (inv.termsText?.isNotEmpty ?? false) ...[
            const SizedBox(height: Tokens.s3),
            Text(
              inv.termsText!,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (livePayments.isEmpty && inv.isOpen) const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.s4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _sharePdf(context, inv, profile),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(l.sharePdf),
                    ),
                  ),
                  const SizedBox(width: Tokens.s2),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _whatsapp(context, inv, profile),
                      icon: const Icon(Icons.chat_outlined),
                      label: Text(l.whatsapp),
                    ),
                  ),
                ],
              ),
              if (canBill && inv.isOpen) ...[
                const SizedBox(height: Tokens.s2),
                BigButton(
                  label: l.recordPayment,
                  icon: Icons.add_card_outlined,
                  onPressed: () => _recordPayment(context, ref, inv),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sharePdf(
    BuildContext context,
    Invoice inv,
    BusinessProfile? profile,
  ) async {
    final l = AppLocalizations.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final bytes = await InvoicePdf.build(
      invoice: inv,
      profile: profile,
      rtl: rtl,
      labels: InvoicePdfLabels(
        invoice: l.pdfInvoice,
        billTo: l.pdfBillTo,
        job: l.pdfJob,
        description: l.description,
        qty: l.qty,
        rate: l.rate,
        amount: l.amount,
        subtotal: l.subtotal,
        discount: l.discount,
        tax: l.tax,
        total: l.total,
        received: l.received,
        balanceDue: l.balanceDue,
        payTo: l.pdfPayTo,
        bank: l.bankName,
        accountTitle: l.accountTitle,
        accountNumber: l.accountNumber,
        easypaisa: l.methodEasypaisa,
        jazzcash: l.methodJazzcash,
        payments: l.payments,
        thanks: l.pdfThanks,
        madeWith: l.pdfMadeWith,
        paidStamp: l.pdfPaidStamp,
        cancelledStamp: l.invoiceStatusVoid,
        methodLabel: (m) => methodLabel(l, m),
      ),
    );
    await Printing.sharePdf(bytes: bytes, filename: '${inv.number}.pdf');
  }

  Future<void> _whatsapp(
    BuildContext context,
    Invoice inv,
    BusinessProfile? profile,
  ) async {
    final l = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final msg = l.invoiceMessage(
      profile?.name(lang) ?? 'Duebook',
      inv.number,
      inv.customerName,
      Money.format(inv.totalPaisa),
      Money.format(inv.receivedPaisa),
      Money.format(inv.balancePaisa),
    );
    final phone = inv.customerPhone;
    if (phone == null || phone.isEmpty) {
      await SharePlus.instance.share(ShareParams(text: msg));
      return;
    }
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final intl = digits.startsWith('0')
        ? '92${digits.substring(1)}'
        : digits.replaceFirst('+', '');
    final ok = await launchUrl(
      Uri.parse('https://wa.me/$intl?text=${Uri.encodeComponent(msg)}'),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.couldNotOpenApp)));
    }
  }

  Future<void> _recordPayment(
    BuildContext context,
    WidgetRef ref,
    Invoice inv,
  ) async {
    final l = AppLocalizations.of(context);
    final result = await showModalBottomSheet<(int, PaymentMethod, String?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PaymentSheet(balance: inv.balancePaisa),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref
          .read(invoicesRepositoryProvider)
          .recordPayment(inv.id, result.$1, result.$2, note: result.$3);
      if (!context.mounted) return;
      refreshAfterBilling(ref, spaceId, jobId: inv.jobId);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.paymentRecorded)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(l, e))));
    }
  }

  Future<void> _void(BuildContext context, WidgetRef ref, Invoice inv) async {
    final l = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.voidInvoice),
        content: Text(l.voidInvoiceConfirm(inv.number)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.no),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.yes),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    try {
      await ref.read(invoicesRepositoryProvider).voidInvoice(inv.id);
      if (!context.mounted) return;
      refreshAfterBilling(ref, spaceId, jobId: inv.jobId);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.invoiceVoided)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(l, e))));
    }
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: text.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
        Text(
          value,
          style: text.titleMedium?.copyWith(
            color: Colors.white,
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.balance});
  final int balance;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  late final _amount = TextEditingController(
    text: Money.format(widget.balance),
  );
  final _note = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final paisa = Money.parse(_amount.text) ?? 0;
    final bad = paisa <= 0 || paisa > widget.balance;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Tokens.s4,
        0,
        Tokens.s4,
        MediaQuery.viewInsetsOf(context).bottom + Tokens.s4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.recordPayment,
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: Tokens.s3),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
            decoration: InputDecoration(
              labelText: l.amount,
              prefixText: 'Rs ',
              errorText: _amount.text.isNotEmpty && bad
                  ? l.receivedTooBig
                  : null,
              suffixIcon: TextButton(
                onPressed: () => _amount.text = Money.format(widget.balance),
                child: Text(l.fullAmount),
              ),
            ),
          ),
          const SizedBox(height: Tokens.s3),
          Wrap(
            spacing: Tokens.s2,
            runSpacing: Tokens.s1,
            children: [
              for (final m in PaymentMethod.values)
                ChoiceChip(
                  avatar: Icon(methodIcon(m), size: 18),
                  label: Text(methodLabel(l, m)),
                  selected: _method == m,
                  onSelected: (_) => setState(() => _method = m),
                ),
            ],
          ),
          const SizedBox(height: Tokens.s3),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: l.noteOptional),
          ),
          const SizedBox(height: Tokens.s4),
          BigButton(
            label: l.save,
            icon: Icons.check,
            onPressed: bad
                ? null
                : () => Navigator.pop(context, (
                    paisa,
                    _method,
                    _note.text.trim().isEmpty ? null : _note.text.trim(),
                  )),
          ),
        ],
      ),
    );
  }
}
