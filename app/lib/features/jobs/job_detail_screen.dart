import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/big_button.dart';
import '../../core/widgets/load_error.dart';
import '../../core/utils/dates.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_repository.dart';
import '../groups/groups_repository.dart';
import '../groups/role_labels.dart';
import '../invoices/invoice_labels.dart';
import '../invoices/invoice_models.dart';
import '../invoices/invoices_repository.dart';
import '../spaces/spaces_repository.dart';
import 'job_labels.dart';
import 'jobs_models.dart';
import 'jobs_repository.dart';

class JobDetailScreen extends ConsumerWidget {
  const JobDetailScreen({
    super.key,
    required this.spaceId,
    required this.jobId,
  });
  final String spaceId;
  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (spaceId, jobId);
    final job = ref.watch(jobProvider(key));
    void retry() => ref.invalidate(jobProvider(key));
    return job.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingScaffold(),
      error: (e, _) => LoadErrorScaffold(onRetry: retry),
      data: (job) => job == null
          ? LoadErrorScaffold(onRetry: retry)
          : _content(context, ref, job),
    );
  }

  /// Runs a write and tells the user when it fails, so a tap never does
  /// nothing without a word.
  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e) {
      if (!context.mounted) return;
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(l, e))));
    }
  }

  Widget _content(BuildContext context, WidgetRef ref, Job job) {
    final l = AppLocalizations.of(context);
    final events = ref.watch(jobEventsProvider((spaceId, jobId)));
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
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final color = statusColor(job.status);
    final mine = job.isAssignedTo(me);
    final iConfirmed =
        job.assignees.where((a) => a.userId == me).firstOrNull?.confirmed ??
        false;
    final repo = ref.read(jobsRepositoryProvider);

    Widget? primary;
    if (job.status.isOpen && job.status != JobStatus.finished) {
      if (mine &&
          !iConfirmed &&
          (job.status == JobStatus.scheduled ||
              job.status == JobStatus.confirmed)) {
        primary = BigButton(
          label: l.confirmJob,
          icon: Icons.check_circle_outline,
          onPressed: () => _run(context, () => repo.confirm(jobId)),
        );
      } else if ((mine || manager) &&
          (job.status == JobStatus.scheduled ||
              job.status == JobStatus.confirmed)) {
        primary = BigButton(
          label: l.onMyWay,
          icon: Icons.directions_car_outlined,
          onPressed: () =>
              _run(context, () => repo.setStatus(jobId, JobStatus.onTheWay)),
        );
      } else if ((mine || manager) && job.status == JobStatus.onTheWay) {
        primary = BigButton(
          label: l.startWork,
          icon: Icons.handyman_outlined,
          onPressed: () =>
              _run(context, () => repo.setStatus(jobId, JobStatus.working)),
        );
      } else if ((mine || manager) && job.status == JobStatus.working) {
        primary = BigButton(
          label: l.finishJob,
          icon: Icons.task_alt,
          onPressed: () => context.push('/space/$spaceId/job/$jobId/finish'),
        );
      }
    } else if ((mine || manager) && job.status == JobStatus.finished) {
      primary = BigButton(
        label: l.makeBill,
        icon: Icons.receipt_long_outlined,
        onPressed: () => context.push('/space/$spaceId/job/$jobId/finish'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(job.customerName),
        actions: [
          if (manager && job.status.isOpen)
            PopupMenuButton<String>(
              onSelected: (v) => _run(
                context,
                () => switch (v) {
                  'time' => _reschedule(context, ref, job),
                  'who' => _assign(context, ref, job),
                  _ => _cancel(context, ref, job),
                },
              ),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'time',
                  child: ListTile(
                    leading: const Icon(Icons.schedule),
                    title: Text(l.reschedule),
                  ),
                ),
                PopupMenuItem(
                  value: 'who',
                  child: ListTile(
                    leading: const Icon(Icons.group_outlined),
                    title: Text(l.assignPeople),
                  ),
                ),
                PopupMenuItem(
                  value: 'cancel',
                  child: ListTile(
                    leading: Icon(Icons.cancel_outlined, color: scheme.error),
                    title: Text(
                      l.cancelJob,
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Tokens.s4),
        children: [
          Container(
            padding: const EdgeInsets.all(Tokens.s4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(Tokens.radiusLarge),
              border: Border.all(
                color: color.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(jobTypeIcon(job.type), color: color),
                    const SizedBox(width: Tokens.s2),
                    Expanded(
                      child: Text(
                        jobTypeLabel(l, job.type),
                        style: text.labelLarge?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      statusLabel(l, job.status),
                      style: text.labelLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Tokens.s2),
                Text(
                  job.title,
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: Tokens.s2),
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 20),
                    const SizedBox(width: Tokens.s2),
                    Expanded(
                      child: Text(
                        '${DateFormat.yMMMEd(locale).format(job.scheduledAt)}  ${clockTime(context, job.scheduledAt)}',
                        style: text.titleMedium?.copyWith(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (job.address != null) ...[
                  const SizedBox(height: Tokens.s1),
                  Row(
                    children: [
                      const Icon(Icons.place_outlined, size: 20),
                      const SizedBox(width: Tokens.s2),
                      Expanded(
                        child: Text(job.address!, style: text.bodyLarge),
                      ),
                    ],
                  ),
                ],
                if (job.estimatePaisa != null) ...[
                  const SizedBox(height: Tokens.s1),
                  Row(
                    children: [
                      const Icon(Icons.payments_outlined, size: 20),
                      const SizedBox(width: Tokens.s2),
                      Text(
                        'Rs ${Money.format(job.estimatePaisa!)}',
                        style: text.bodyLarge?.copyWith(fontFamily: 'Roboto'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Tokens.s3),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: job.customerPhone == null
                      ? null
                      : () => launchUrl(
                          Uri(
                            scheme: 'tel',
                            path: job.customerPhone!.replaceAll(
                              RegExp(r'[^\d+]'),
                              '',
                            ),
                          ),
                        ),
                  icon: const Icon(Icons.call_outlined),
                  label: Text(l.callCustomer),
                ),
              ),
              const SizedBox(width: Tokens.s2),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: job.address == null
                      ? null
                      : () => launchUrl(
                          Uri.parse(
                            'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(job.address!)}',
                          ),
                          mode: LaunchMode.externalApplication,
                        ),
                  icon: const Icon(Icons.map_outlined),
                  label: Text(l.openMap),
                ),
              ),
            ],
          ),
          if (primary != null) ...[const SizedBox(height: Tokens.s3), primary],
          if (job.status == JobStatus.invoiced || job.status == JobStatus.paid)
            _InvoiceCard(spaceId: spaceId, jobId: jobId),
          _ItemsUsed(spaceId: spaceId, jobId: jobId),
          const SizedBox(height: Tokens.s5),
          Text(
            l.whoGoes,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: Tokens.s2),
          if (job.assignees.isEmpty)
            Text(
              l.nobodyAssigned,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          Wrap(
            spacing: Tokens.s2,
            runSpacing: Tokens.s2,
            children: [
              for (final a in job.assignees)
                Chip(
                  avatar: Icon(
                    a.confirmed ? Icons.check_circle : Icons.hourglass_top,
                    size: 18,
                    color: a.confirmed ? Tokens.get : Tokens.saffronDeep,
                  ),
                  label: Text(a.name),
                ),
            ],
          ),
          if (job.notes != null) ...[
            const SizedBox(height: Tokens.s5),
            Text(
              l.notesOptional.split(' ').first,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: Tokens.s1),
            Text(job.notes!, style: text.bodyLarge),
          ],
          const SizedBox(height: Tokens.s5),
          Text(
            l.history,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: Tokens.s2),
          if (events.failed)
            LoadError(
              onRetry: () =>
                  ref.invalidate(jobEventsProvider((spaceId, jobId))),
            ),
          for (final e in (events.value ?? const <JobEvent>[]).reversed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(switch (e.type) {
                'created' => Icons.add_task,
                'assigned' => Icons.group_outlined,
                'confirmed' => Icons.check_circle_outline,
                'rescheduled' => Icons.schedule,
                _ => Icons.flag_outlined,
              }, color: scheme.onSurfaceVariant),
              title: Text(switch (e.type) {
                'created' => l.eventCreated(e.actorName ?? ''),
                'assigned' => l.eventAssigned(e.actorName ?? ''),
                'confirmed' => l.eventConfirmed(e.actorName ?? ''),
                'rescheduled' => l.eventRescheduled(e.actorName ?? ''),
                _ => l.eventStatus(
                  e.actorName ?? '',
                  e.toStatus == null ? '' : statusLabel(l, e.toStatus!),
                ),
              }),
              subtitle: Text(
                DateFormat.MMMd(locale).add_jm().format(e.at.toLocal()),
              ),
            ),
          const SizedBox(height: Tokens.s6),
        ],
      ),
    );
  }

  Future<void> _reschedule(BuildContext context, WidgetRef ref, Job job) async {
    final d = await showDatePicker(
      context: context,
      initialDate: job.scheduledAt,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null || !context.mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(job.scheduledAt),
    );
    if (t == null) return;
    await ref
        .read(jobsRepositoryProvider)
        .reschedule(jobId, DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _assign(BuildContext context, WidgetRef ref, Job job) async {
    final l = AppLocalizations.of(context);
    final members = ref.read(membersProvider(spaceId)).value ?? const [];
    final chosen = job.assignees.map((a) => a.userId).toSet();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(l.assignPeople),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in members)
                CheckboxListTile(
                  value: chosen.contains(m.userId),
                  title: Text(m.name),
                  onChanged: (v) => setState(
                    () => v! ? chosen.add(m.userId) : chosen.remove(m.userId),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.save),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await ref
          .read(jobsRepositoryProvider)
          .setAssignees(jobId, chosen.toList());
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, Job job) async {
    final l = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l.cancelJobConfirm),
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
    if (yes == true) {
      await ref
          .read(jobsRepositoryProvider)
          .setStatus(jobId, JobStatus.cancelled);
      if (context.mounted) context.pop();
    }
  }
}

/// Link to the live bill once the job is invoiced or paid.
class _InvoiceCard extends ConsumerWidget {
  const _InvoiceCard({required this.spaceId, required this.jobId});
  final String spaceId;
  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final key = (spaceId, jobId);
    final found = ref.watch(invoiceForJobProvider(key));
    if (found.failed) {
      return LoadError(
        onRetry: () => ref.invalidate(invoiceForJobProvider(key)),
      );
    }
    final inv = found.value;
    if (inv == null) return const SizedBox.shrink();
    final color = invoiceStatusColor(inv.status);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: Tokens.s3),
      child: Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Tokens.radius),
        child: ListTile(
          onTap: () => context.push('/space/$spaceId/invoice/${inv.id}'),
          leading: Icon(Icons.receipt_long, color: color),
          title: Text(
            '${inv.number}  ·  Rs ${Money.format(inv.totalPaisa)}',
            style: text.titleMedium?.copyWith(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            inv.isOpen
                ? '${l.balanceDue} Rs ${Money.format(inv.balancePaisa)}'
                : invoiceStatusLabel(l, inv),
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}

/// Materials recorded against the job so far.
class _ItemsUsed extends ConsumerWidget {
  const _ItemsUsed({required this.spaceId, required this.jobId});
  final String spaceId;
  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final key = (spaceId, jobId);
    final loaded = ref.watch(jobItemsProvider(key));
    if (loaded.failed) {
      return LoadError(onRetry: () => ref.invalidate(jobItemsProvider(key)));
    }
    final items = loaded.value ?? const <JobItem>[];
    if (items.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Tokens.s5),
        Text(
          l.itemsUsed,
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: Tokens.s2),
        for (final i in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${i.description}  × ${formatQty(i.qty)}',
                    style: text.bodyLarge,
                  ),
                ),
                Text(
                  'Rs ${Money.format(i.amountPaisa)}',
                  style: text.bodyLarge?.copyWith(fontFamily: 'Roboto'),
                ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: Text(
                l.total,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              'Rs ${Money.format(BillMath.subtotal(items))}',
              style: text.titleMedium?.copyWith(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
