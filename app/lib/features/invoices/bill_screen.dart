import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/big_button.dart';
import '../../core/widgets/load_error.dart';
import '../../core/widgets/money_text.dart';
import '../../l10n/app_localizations.dart';
import '../jobs/jobs_repository.dart';
import 'invoice_labels.dart';
import 'invoice_models.dart';
import 'invoices_repository.dart';

enum _Received { none, full, other }

/// Step two of finishing a job: discount, what was paid now, and issue.
class BillScreen extends ConsumerStatefulWidget {
  const BillScreen({super.key, required this.spaceId, required this.jobId});
  final String spaceId;
  final String jobId;

  @override
  ConsumerState<BillScreen> createState() => _BillScreenState();
}

class _BillScreenState extends ConsumerState<BillScreen> {
  final _discount = TextEditingController();
  final _received = TextEditingController();
  final _notes = TextEditingController();
  _Received _mode = _Received.none;
  PaymentMethod _method = PaymentMethod.cash;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _discount.addListener(() => setState(() {}));
    _received.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _discount.dispose();
    _received.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final key = (widget.spaceId, widget.jobId);
    final jobLoad = ref.watch(jobProvider(key));
    final itemsLoad = ref.watch(jobItemsProvider(key));
    final profileLoad = ref.watch(businessProfileProvider(widget.spaceId));
    final job = jobLoad.value;
    final items = itemsLoad.value;
    final profile = profileLoad.value;
    // The profile carries the tax rate, so no bill is shown without it.
    final missing = jobLoad.hasValue && !jobLoad.isLoading && job == null;
    if (jobLoad.failed || itemsLoad.failed || profileLoad.failed || missing) {
      return LoadErrorScaffold(
        onRetry: () {
          ref.invalidate(jobProvider(key));
          ref.invalidate(jobItemsProvider(key));
          ref.invalidate(businessProfileProvider(widget.spaceId));
        },
      );
    }
    if (job == null || items == null || !profileLoad.hasValue) {
      return const LoadingScaffold();
    }
    final subtotal = BillMath.subtotal(items);
    final discount = math.max(0, Money.parse(_discount.text) ?? 0);
    final discountBad = discount > subtotal;
    final tax = BillMath.tax(subtotal, discountBad ? 0 : discount, profile);
    final total = subtotal - (discountBad ? 0 : discount) + tax;
    final received = switch (_mode) {
      _Received.none => 0,
      _Received.full => total,
      _Received.other => math.max(0, Money.parse(_received.text) ?? 0),
    };
    final receivedBad = received > total;
    final balance = receivedBad ? total : total - received;
    final canIssue = items.isNotEmpty && !discountBad && !receivedBad && !_busy;

    Widget row(String label, int paisa, {bool bold = false, Color? color}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: (bold ? text.titleMedium : text.bodyLarge)?.copyWith(
                    fontWeight: bold ? FontWeight.w800 : null,
                    color: color,
                  ),
                ),
              ),
              Text(
                'Rs ${Money.format(paisa)}',
                style: (bold ? text.titleLarge : text.bodyLarge)?.copyWith(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l.billFor(job.customerName))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Tokens.s4,
          Tokens.s2,
          Tokens.s4,
          Tokens.s7 * 3,
        ),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Tokens.s3),
              child: Column(
                children: [
                  for (final i in items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${i.description}  × ${formatQty(i.qty)}',
                              style: text.bodyMedium,
                            ),
                          ),
                          Text(
                            Money.format(i.amountPaisa),
                            style: text.bodyMedium?.copyWith(
                              fontFamily: 'Roboto',
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  row(l.subtotal, subtotal),
                ],
              ),
            ),
          ),
          const SizedBox(height: Tokens.s4),
          TextField(
            controller: _discount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l.discount,
              prefixText: 'Rs ',
              errorText: discountBad ? l.discountTooBig : null,
            ),
          ),
          if (profile?.taxEnabled ?? false)
            row(l.taxWithRate((profile!.taxRateBp / 100).toString()), tax),
          const SizedBox(height: Tokens.s2),
          row(l.total, total, bold: true),
          const SizedBox(height: Tokens.s5),
          Text(
            l.howMuchPaidNow,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: Tokens.s2),
          Wrap(
            spacing: Tokens.s2,
            children: [
              ChoiceChip(
                label: Text(l.nothingYet),
                selected: _mode == _Received.none,
                onSelected: (_) => setState(() => _mode = _Received.none),
              ),
              ChoiceChip(
                label: Text(l.fullAmount),
                selected: _mode == _Received.full,
                onSelected: (_) => setState(() => _mode = _Received.full),
              ),
              ChoiceChip(
                label: Text(l.otherAmount),
                selected: _mode == _Received.other,
                onSelected: (_) => setState(() => _mode = _Received.other),
              ),
            ],
          ),
          if (_mode == _Received.other) ...[
            const SizedBox(height: Tokens.s2),
            TextField(
              controller: _received,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l.received,
                prefixText: 'Rs ',
                errorText: receivedBad ? l.receivedTooBig : null,
              ),
            ),
          ],
          if (received > 0) ...[
            const SizedBox(height: Tokens.s3),
            Text(l.paidBy, style: text.labelLarge),
            const SizedBox(height: Tokens.s1),
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
          ],
          const SizedBox(height: Tokens.s4),
          TextField(
            controller: _notes,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: l.noteOptional),
          ),
          const SizedBox(height: Tokens.s5),
          Container(
            padding: const EdgeInsets.all(Tokens.s4),
            decoration: BoxDecoration(
              color: (balance > 0 ? Tokens.saffron : Tokens.get).withValues(
                alpha: 0.12,
              ),
              borderRadius: BorderRadius.circular(Tokens.radiusLarge),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    balance > 0 ? l.balanceDue : l.fullyPaid,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                MoneyText(
                  paisa: balance,
                  sign: balance > 0 ? true : null,
                  size: 24,
                ),
              ],
            ),
          ),
          if (received > 0 && balance == 0)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.s2),
              child: Text(
                l.fullyPaid,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.s4),
          child: BigButton(
            label: l.issueInvoice,
            icon: Icons.receipt_long,
            busy: _busy,
            onPressed: canIssue
                ? () => _issue(job.customerName, total, balance, received)
                : null,
          ),
        ),
      ),
    );
  }

  Future<void> _issue(
    String customer,
    int total,
    int balance,
    int received,
  ) async {
    final l = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.issueInvoice),
        content: Text(
          balance == 0
              ? l.issueInvoiceConfirmPaid(Money.format(total), customer)
              : l.issueInvoiceConfirm(
                  Money.format(total),
                  customer,
                  Money.format(balance),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.yes),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final id = await ref
          .read(invoicesRepositoryProvider)
          .issueInvoice(
            BillRequest(
              jobId: widget.jobId,
              discountPaisa: Money.parse(_discount.text) ?? 0,
              receivedPaisa: received,
              method: _method,
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            ),
          );
      if (!mounted) return;
      refreshAfterBilling(ref, widget.spaceId, jobId: widget.jobId);
      context.pushReplacement('/space/${widget.spaceId}/invoice/$id');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(l, e))));
    }
  }
}
