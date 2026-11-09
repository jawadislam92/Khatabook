import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/money.dart';
import '../../l10n/app_localizations.dart';
import '../jobs/job_labels.dart';
import 'invoice_labels.dart';
import 'invoice_models.dart';
import 'invoices_repository.dart';

/// Bills tab on the business home: this month at a glance, unpaid first.
class InvoicesTab extends ConsumerStatefulWidget {
  const InvoicesTab({super.key, required this.spaceId, required this.manager});
  final String spaceId;
  final bool manager;

  @override
  ConsumerState<InvoicesTab> createState() => _InvoicesTabState();
}

class _InvoicesTabState extends ConsumerState<InvoicesTab> {
  bool _unpaidOnly = true;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final invoices = ref.watch(invoicesProvider(widget.spaceId));
    final stats =
        ref.watch(invoiceStatsProvider(widget.spaceId)).value ??
        InvoiceStats.zero;
    final profile = ref.watch(businessProfileProvider(widget.spaceId));
    final nudge =
        widget.manager &&
        profile.hasValue &&
        !(profile.value?.isComplete ?? false);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.tabInvoices),
        actions: [
          IconButton(
            tooltip: l.itemsUsedThisMonth,
            icon: const Icon(Icons.bar_chart_outlined),
            onPressed: () =>
                context.push('/business/${widget.spaceId}/items-report'),
          ),
          if (widget.manager)
            IconButton(
              tooltip: l.businessDetails,
              icon: const Icon(Icons.storefront_outlined),
              onPressed: () =>
                  context.push('/business/${widget.spaceId}/profile'),
            ),
        ],
      ),
      body: invoices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.errorGeneric)),
        data: (all) {
          final list = _unpaidOnly ? all.where((i) => i.isOpen).toList() : all;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Tokens.s4,
              0,
              Tokens.s4,
              Tokens.s7 * 2,
            ),
            children: [
              _StatsCard(stats: stats),
              if (nudge)
                Padding(
                  padding: const EdgeInsets.only(top: Tokens.s3),
                  child: Material(
                    color: Tokens.saffron.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(Tokens.radius),
                    child: ListTile(
                      leading: const Icon(
                        Icons.storefront_outlined,
                        color: Tokens.saffronDeep,
                      ),
                      title: Text(l.businessNudge),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          context.push('/business/${widget.spaceId}/profile'),
                    ),
                  ),
                ),
              const SizedBox(height: Tokens.s4),
              Row(
                children: [
                  ChoiceChip(
                    label: Text(l.filterUnpaid),
                    selected: _unpaidOnly,
                    onSelected: (_) => setState(() => _unpaidOnly = true),
                  ),
                  const SizedBox(width: Tokens.s2),
                  ChoiceChip(
                    label: Text(l.filterAll),
                    selected: !_unpaidOnly,
                    onSelected: (_) => setState(() => _unpaidOnly = false),
                  ),
                ],
              ),
              const SizedBox(height: Tokens.s2),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(Tokens.s4),
                  child: Text(
                    all.isEmpty ? l.noInvoices : l.unpaidBills(0),
                    textAlign: TextAlign.center,
                    style: text.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final inv in list)
                Card(
                  margin: const EdgeInsets.only(bottom: Tokens.s2),
                  child: ListTile(
                    onTap: () => context.push(
                      '/space/${widget.spaceId}/invoice/${inv.id}',
                    ),
                    leading: CircleAvatar(
                      backgroundColor: invoiceStatusColor(inv.status)
                          .withValues(alpha: 0.15),
                      child: Icon(
                        inv.isPaid
                            ? Icons.check_circle_outline
                            : inv.isVoid
                            ? Icons.block
                            : Icons.receipt_long_outlined,
                        color: invoiceStatusColor(inv.status),
                      ),
                    ),
                    title: Text(
                      inv.customerName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${inv.number}  ·  ${DateFormat.MMMd(locale).format(inv.issuedAt)}',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Rs ${Money.format(inv.totalPaisa)}',
                          style: text.titleMedium?.copyWith(
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          inv.isOpen
                              ? '${l.balanceDue} Rs ${Money.format(inv.balancePaisa)}'
                              : invoiceStatusLabel(l, inv.status),
                          style: text.bodySmall?.copyWith(
                            color: invoiceStatusColor(inv.status),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});
  final InvoiceStats stats;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    Widget stat(String label, String value, {Color? color}) => Expanded(
      child: Column(
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
              color: color ?? Colors.white,
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(Tokens.s4),
      decoration: BoxDecoration(
        gradient: Tokens.violetGradient,
        borderRadius: BorderRadius.circular(Tokens.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: Tokens.violet.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.thisMonth,
            style: text.labelLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: Tokens.s2),
          Row(
            children: [
              stat(l.invoiced, 'Rs ${Money.format(stats.monthInvoicedPaisa)}'),
              stat(l.received, 'Rs ${Money.format(stats.monthReceivedPaisa)}'),
              stat(l.jobsDone, '${stats.monthJobsDone}'),
            ],
          ),
          const SizedBox(height: Tokens.s3),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.25)),
          const SizedBox(height: Tokens.s3),
          Row(
            children: [
              Expanded(
                child: Text(
                  l.unpaidBills(stats.unpaidCount),
                  style: text.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                'Rs ${Money.format(stats.unpaidPaisa)}',
                style: text.headlineSmall?.copyWith(
                  color: const Color(0xFFFFE08A),
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Materials billed this month, most money first.
class ItemsReportScreen extends ConsumerWidget {
  const ItemsReportScreen({super.key, required this.spaceId});
  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final usage = ref.watch(itemsUsedProvider(spaceId));
    return Scaffold(
      appBar: AppBar(title: Text(l.itemsUsedThisMonth)),
      body: usage.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.errorGeneric)),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Tokens.s5),
                child: Text(
                  l.noItemsUsed,
                  textAlign: TextAlign.center,
                  style: text.bodyLarge,
                ),
              ),
            );
          }
          final total = list.fold(0, (s, u) => s + u.amountPaisa);
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Tokens.s4,
              Tokens.s2,
              Tokens.s4,
              Tokens.s7,
            ),
            children: [
              for (final u in list)
                Card(
                  margin: const EdgeInsets.only(bottom: Tokens.s2),
                  child: ListTile(
                    title: Text(
                      u.description,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${formatQty(u.qty)}${u.unit == null ? '' : ' ${unitLabel(l, u.unit!)}'}',
                      style: const TextStyle(fontFamily: 'Roboto'),
                    ),
                    trailing: Text(
                      'Rs ${Money.format(u.amountPaisa)}',
                      style: text.titleMedium?.copyWith(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.total,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    'Rs ${Money.format(total)}',
                    style: text.titleLarge?.copyWith(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
