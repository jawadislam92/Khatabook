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
    if (manager && job.status == JobStatus.onHold) {
      primary = BigButton(
        label: l.setNewDate,
        icon: Icons.event_repeat,
        onPressed: () => _run(context, () => _reschedule(context, ref, job)),
      );
    }

    // Nothing in the journey is required: later steps can be reached
    // straight away, and the job can always be stopped for today.
    final active = const {
      JobStatus.scheduled,
      JobStatus.confirmed,
      JobStatus.onTheWay,
      JobStatus.working,
    }.contains(job.status);
    final canAct = (mine || manager) && active;
    final skipToStart =
        canAct &&
        (job.status == JobStatus.scheduled ||
            job.status == JobStatus.confirmed);
    final skipToFinish = canAct && job.status != JobStatus.working;

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
          if (job.status == JobStatus.onHold)
            _HoldBanner(job: job, manager: manager),
          if (primary != null) ...[const SizedBox(height: Tokens.s3), primary],
          if (skipToStart || skipToFinish)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: Tokens.s2,
              children: [
                if (skipToStart)
                  TextButton.icon(
                    onPressed: () => _run(
                      context,
                      () => repo.setStatus(jobId, JobStatus.working),
                    ),
                    icon: const Icon(Icons.handyman_outlined),
                    label: Text(l.startWork),
                  ),
                if (skipToFinish)
                  TextButton.icon(
                    onPressed: () =>
                        context.push('/space/$spaceId/job/$jobId/finish'),
                    icon: const Icon(Icons.task_alt),
                    label: Text(l.finishJob),
                  ),
              ],
            ),
          if (canAct) ...[
            const SizedBox(height: Tokens.s2),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Tokens.rose,
                side: const BorderSide(color: Tokens.rose),
              ),
              onPressed: () => _cantFinish(context, ref, job),
              icon: const Icon(Icons.pause_circle_outline),
              label: Text(l.cantFinishToday),
            ),
          ],
          // More work after the job is done: a new visit with its own bill.
          if ((mine || manager) &&
              const {
                JobStatus.finished,
                JobStatus.invoiced,
                JobStatus.paid,
              }.contains(job.status))
            Padding(
              padding: const EdgeInsets.only(top: Tokens.s2),
              child: OutlinedButton.icon(
                onPressed: () => _bookVisit(context, job),
                icon: const Icon(Icons.event_repeat),
                label: Text(l.bookVisit),
              ),
            ),
          if (manager && job.status.isOpen && job.status != JobStatus.finished)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.s2),
              child: OutlinedButton.icon(
                onPressed: () =>
                    context.push('/space/$spaceId/job/$jobId/items'),
                icon: const Icon(Icons.inventory_2_outlined),
                label: Text(l.itemsToTake),
              ),
            ),
          if (job.status == JobStatus.invoiced || job.status == JobStatus.paid)
            _InvoiceCard(spaceId: spaceId, jobId: jobId),
          _ItemsUsed(
            spaceId: spaceId,
            jobId: jobId,
            planned:
                job.status.isOpen &&
                job.status != JobStatus.finished &&
                job.status != JobStatus.working,
          ),
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
                'on_hold' => Icons.pause_circle_outline,
                'follow_up' => Icons.event_repeat,
                _ => Icons.flag_outlined,
              }, color: scheme.onSurfaceVariant),
              title: Text(switch (e.type) {
                'created' => l.eventCreated(e.actorName ?? ''),
                'assigned' => l.eventAssigned(e.actorName ?? ''),
                'confirmed' => l.eventConfirmed(e.actorName ?? ''),
                'rescheduled' => l.eventRescheduled(e.actorName ?? ''),
                'on_hold' => l.eventOnHold(e.actorName ?? ''),
                'follow_up' => l.eventFollowUp(e.actorName ?? ''),
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

  Future<void> _bookVisit(BuildContext context, Job job) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BookVisitSheet(job: job),
    );
    if (id != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).visitBooked)),
      );
      // Open the new visit (screens shown outside the router, as in tests,
      // just stay where they are).
      if (GoRouter.maybeOf(context) != null) {
        context.push('/space/$spaceId/job/$id');
      }
    }
  }

  /// "Can't finish today": reason, note and date are all optional.
  Future<void> _cantFinish(BuildContext context, WidgetRef ref, Job job) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CantFinishSheet(jobId: jobId),
    );
    if (sent == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).holdSent)),
      );
    }
  }

  Future<void> _reschedule(BuildContext context, WidgetRef ref, Job job) async {
    final first = DateTime.now().subtract(const Duration(days: 1));
    var start = job.suggestedAt ?? job.scheduledAt;
    if (start.isBefore(first)) start = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null || !context.mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(start),
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
  const _ItemsUsed({
    required this.spaceId,
    required this.jobId,
    this.planned = false,
  });
  final String spaceId;
  final String jobId;

  /// Before the work: the owner's list of items to take.
  final bool planned;

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
          planned ? l.itemsToTake : l.itemsUsed,
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
                  i.unitPricePaisa == 0
                      ? l.priceNeeded
                      : 'Rs ${Money.format(i.amountPaisa)}',
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

/// Why the job stopped, what the installer wrote, and the date they
/// suggested. Installers see that the owner will set the new date.
class _HoldBanner extends StatelessWidget {
  const _HoldBanner({required this.job, required this.manager});
  final Job job;
  final bool manager;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final lines = [
      if (job.holdReason != null) holdReasonLabel(l, job.holdReason!),
      if (job.holdNote != null) job.holdNote!,
      if (job.suggestedAt != null)
        l.suggestedDate(
          '${DateFormat.MMMEd(locale).format(job.suggestedAt!)}  ${clockTime(context, job.suggestedAt!)}',
        ),
      if (!manager) l.waitingNewDate,
    ];
    return Container(
      margin: const EdgeInsets.only(top: Tokens.s3),
      padding: const EdgeInsets.all(Tokens.s3),
      decoration: BoxDecoration(
        color: Tokens.rose.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Tokens.radius),
        border: Border.all(color: Tokens.rose),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.pause_circle_outline, color: Tokens.rose),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.holdBanner,
                  style: text.titleMedium?.copyWith(
                    color: Tokens.rose,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                for (final line in lines) Text(line, style: text.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CantFinishSheet extends ConsumerStatefulWidget {
  const _CantFinishSheet({required this.jobId});
  final String jobId;

  @override
  ConsumerState<_CantFinishSheet> createState() => _CantFinishSheetState();
}

class _CantFinishSheetState extends ConsumerState<_CantFinishSheet> {
  final _note = TextEditingController();
  String? _reason;
  DateTime? _date;
  var _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 1)),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
    );
    if (!mounted) return;
    setState(
      () => _date = DateTime(
        d.year,
        d.month,
        d.day,
        t?.hour ?? 10,
        t?.minute ?? 0,
      ),
    );
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      final note = _note.text.trim();
      await ref
          .read(jobsRepositoryProvider)
          .reportProblem(
            widget.jobId,
            reason: _reason,
            note: note.isEmpty ? null : note,
            suggestedAt: _date,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).errorGeneric)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Tokens.s4,
        0,
        Tokens.s4,
        MediaQuery.viewInsetsOf(context).bottom + Tokens.s4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.cantFinishTitle,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(l.cantFinishHint, style: text.bodyMedium),
            const SizedBox(height: Tokens.s3),
            Wrap(
              spacing: Tokens.s2,
              runSpacing: Tokens.s2,
              children: [
                for (final r in holdReasons)
                  ChoiceChip(
                    label: Text(holdReasonLabel(l, r)),
                    selected: _reason == r,
                    onSelected: (on) => setState(() => _reason = on ? r : null),
                  ),
              ],
            ),
            const SizedBox(height: Tokens.s3),
            TextField(
              controller: _note,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l.holdNoteLabel),
            ),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event),
              label: Text(
                _date == null
                    ? l.suggestDate
                    : l.suggestedDate(
                        '${DateFormat.MMMEd(locale).format(_date!)}  ${clockTime(context, _date!)}',
                      ),
              ),
            ),
            const SizedBox(height: Tokens.s4),
            BigButton(
              label: l.holdSend,
              icon: Icons.send,
              busy: _busy,
              onPressed: _busy ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}

/// New visit for the same customer, address and team. Only the date is
/// needed; the work description starts as the old one.
class _BookVisitSheet extends ConsumerStatefulWidget {
  const _BookVisitSheet({required this.job});
  final Job job;

  @override
  ConsumerState<_BookVisitSheet> createState() => _BookVisitSheetState();
}

class _BookVisitSheetState extends ConsumerState<_BookVisitSheet> {
  late final _title = TextEditingController(text: widget.job.title);
  final _notes = TextEditingController();
  late DateTime _at;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    final t = DateTime.now().add(const Duration(days: 1));
    _at = DateTime(t.year, t.month, t.day, 10);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    if (!mounted) return;
    setState(
      () => _at = DateTime(
        d.year,
        d.month,
        d.day,
        t?.hour ?? _at.hour,
        t?.minute ?? _at.minute,
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final id = await ref
          .read(jobsRepositoryProvider)
          .bookFollowUp(
            widget.job.id,
            _at,
            title: _title.text.trim(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (mounted) Navigator.pop(context, id);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).errorGeneric)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Tokens.s4,
        0,
        Tokens.s4,
        MediaQuery.viewInsetsOf(context).bottom + Tokens.s4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.bookVisit,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(l.bookVisitHint, style: text.bodyMedium),
            const SizedBox(height: Tokens.s3),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l.jobTitle),
            ),
            const SizedBox(height: Tokens.s3),
            TextField(
              controller: _notes,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l.notesOptional),
            ),
            const SizedBox(height: Tokens.s3),
            OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.event),
              label: Text(
                '${DateFormat.MMMEd(locale).format(_at)}  ${clockTime(context, _at)}',
              ),
            ),
            const SizedBox(height: Tokens.s4),
            BigButton(
              label: l.bookVisitSave,
              icon: Icons.event_available,
              busy: _busy,
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
