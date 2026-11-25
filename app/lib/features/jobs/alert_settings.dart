import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/big_button.dart';
import '../../core/widgets/load_error.dart';
import '../../l10n/app_localizations.dart';
import '../invoices/invoice_labels.dart';
import 'job_alerts.dart';
import 'jobs_repository.dart';

String alertLevelLabel(AppLocalizations l, JobAlerts? a) => switch (a?.level) {
  null => l.alertsSameAsBusiness,
  AlertLevel.few => l.alertsFew,
  AlertLevel.normal => l.alertsNormal,
  AlertLevel.many => l.alertsMany,
  AlertLevel.custom => l.alertsCustom,
};

/// Few, Normal, Many, or choose each alert. With [allowBusiness] there is
/// also "Same as the business", which is null.
class AlertPicker extends StatelessWidget {
  const AlertPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowBusiness = false,
  });
  final JobAlerts? value;
  final ValueChanged<JobAlerts?> onChanged;
  final bool allowBusiness;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final v = value;

    Widget option(String title, String? sub, bool on, VoidCallback tap) =>
        ListTile(
          contentPadding: EdgeInsets.zero,
          selected: on,
          leading: Icon(
            on ? Icons.radio_button_checked : Icons.radio_button_off,
            color: on ? scheme.primary : scheme.onSurfaceVariant,
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: sub == null ? null : Text(sub),
          onTap: tap,
        );

    String span(int m) =>
        m % 60 == 0 ? l.hoursShort(m ~/ 60) : l.minutesShort(m);

    Widget chips(
      List<int> all,
      String Function(int) label,
      bool Function(int) on,
      void Function(int) tap,
    ) => Wrap(
      spacing: Tokens.s2,
      runSpacing: Tokens.s1,
      children: [
        for (final t in all)
          ChoiceChip(
            label: Text(label(t)),
            selected: on(t),
            onSelected: (_) => tap(t),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (allowBusiness)
          option(
            l.alertsSameAsBusiness,
            null,
            v == null,
            () => onChanged(null),
          ),
        option(
          l.alertsFew,
          l.alertsFewHint,
          v?.level == AlertLevel.few,
          () => onChanged(const JobAlerts.few()),
        ),
        option(
          l.alertsNormal,
          l.alertsNormalHint,
          v?.level == AlertLevel.normal,
          () => onChanged(const JobAlerts.normal()),
        ),
        option(
          l.alertsMany,
          l.alertsManyHint,
          v?.level == AlertLevel.many,
          () => onChanged(const JobAlerts.many()),
        ),
        option(
          l.alertsCustom,
          l.alertsCustomHint,
          v?.level == AlertLevel.custom,
          () => onChanged((v ?? const JobAlerts.normal()).custom()),
        ),
        if (v != null && v.level == AlertLevel.custom) ...[
          const SizedBox(height: Tokens.s2),
          Text(l.alertsRepeats, style: text.labelLarge),
          chips(
            const [0, 1, 2, 3, 4, 5],
            (n) => n == 0 ? l.alertsNever : l.alertsTimes(n),
            (n) => v.repeats == n,
            (n) => onChanged(v.custom(repeats: n)),
          ),
          if (v.repeats > 0) ...[
            const SizedBox(height: Tokens.s2),
            Text(l.alertsEvery, style: text.labelLarge),
            chips(
              const [10, 15, 30, 60],
              span,
              (n) => v.every == n,
              (n) => onChanged(v.custom(every: n)),
            ),
          ],
          const SizedBox(height: Tokens.s2),
          Text(l.alertsBefore, style: text.labelLarge),
          chips(
            const [120, 60, 30, 15],
            span,
            v.before.contains,
            (n) => onChanged(
              v.custom(
                before: v.before.contains(n)
                    ? v.before.where((b) => b != n).toList()
                    : ([...v.before, n]..sort((a, b) => b.compareTo(a))),
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.alertsEvening),
            value: v.evening,
            onChanged: (x) => onChanged(v.custom(evening: x)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.alertsUpdates),
            subtitle: Text(l.alertsUpdatesHint),
            value: v.updates,
            onChanged: (x) => onChanged(v.custom(updates: x)),
          ),
        ],
        if (v != null)
          Padding(
            padding: const EdgeInsets.only(top: Tokens.s2),
            child: Text(
              l.alertsCount(v.forInstaller, v.forManager),
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

/// Lets the owner or a manager choose for one job. Returns null when closed
/// without saving; the record holds the choice (null: same as business).
Future<({JobAlerts? alerts})?> pickJobAlerts(
  BuildContext context,
  JobAlerts? current,
) {
  var v = current;
  return showModalBottomSheet<({JobAlerts? alerts})>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      final l = AppLocalizations.of(ctx);
      return StatefulBuilder(
        builder: (ctx, setState) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Tokens.s4,
            0,
            Tokens.s4,
            Tokens.s4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.alertsThisJob, style: Theme.of(ctx).textTheme.titleLarge),
              Text(l.alertsAlways),
              AlertPicker(
                value: v,
                allowBusiness: true,
                onChanged: (x) => setState(() => v = x),
              ),
              const SizedBox(height: Tokens.s4),
              BigButton(
                label: l.save,
                icon: Icons.check,
                onPressed: () => Navigator.pop(ctx, (alerts: v)),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The business default. Owner only.
class AlertSettingsScreen extends ConsumerStatefulWidget {
  const AlertSettingsScreen({super.key, required this.spaceId});
  final String spaceId;
  @override
  ConsumerState<AlertSettingsScreen> createState() =>
      _AlertSettingsScreenState();
}

class _AlertSettingsScreenState extends ConsumerState<AlertSettingsScreen> {
  JobAlerts? _edited;
  bool _busy = false;

  Future<void> _save(JobAlerts a) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(jobsRepositoryProvider).setSpaceAlerts(widget.spaceId, a);
      ref.invalidate(spaceAlertsProvider(widget.spaceId));
      messenger.showSnackBar(SnackBar(content: Text(l.saved)));
      if (mounted) unawaited(Navigator.of(context).maybePop());
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(l, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final load = ref.watch(spaceAlertsProvider(widget.spaceId));
    return Scaffold(
      appBar: AppBar(title: Text(l.alertSettings)),
      body: load.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => LoadError(
          onRetry: () => ref.invalidate(spaceAlertsProvider(widget.spaceId)),
        ),
        data: (saved) {
          final v = _edited ?? saved;
          return ListView(
            padding: const EdgeInsets.all(Tokens.s4),
            children: [
              Text(l.alertSettingsHint),
              const SizedBox(height: Tokens.s1),
              Text(l.alertsAlways),
              const SizedBox(height: Tokens.s2),
              AlertPicker(
                value: v,
                onChanged: (x) => setState(() => _edited = x),
              ),
              const SizedBox(height: Tokens.s5),
              BigButton(
                label: l.save,
                icon: Icons.check,
                busy: _busy,
                onPressed: () => _save(v),
              ),
            ],
          );
        },
      ),
    );
  }
}
