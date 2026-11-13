import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../router/app_router.dart';
import '../theme/tokens.dart';
import 'offline_sync.dart';

/// A thin strip at the bottom of every screen while the phone is offline,
/// while changes wait to be sent, or when one was refused. Tapping it lists
/// the changes. Hidden when all is well.
class OfflineStrip extends ConsumerWidget {
  const OfflineStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(offlineSyncProvider);
    // Shown above the screens, where the app's words may not be loaded yet.
    final l = Localizations.of<AppLocalizations>(context, AppLocalizations);
    if (l == null) return const SizedBox.shrink();
    final waiting = sync.waitingCount;
    final failed = sync.failedCount;
    if (!sync.isOffline && waiting == 0 && failed == 0) {
      return const SizedBox.shrink();
    }
    final (color, icon, text) = failed > 0
        ? (Tokens.give, Icons.error_outline, l.sendFailed(failed))
        : sync.isOffline
        ? (
            Tokens.muted,
            Icons.cloud_off,
            waiting == 0
                ? l.offlineStrip
                : '${l.offlineStrip}  ${l.waitingToSend(waiting)}',
          )
        : (Tokens.sky, Icons.cloud_upload_outlined, l.waitingToSend(waiting));
    return Material(
      color: color,
      child: InkWell(
        onTap: waiting + failed == 0
            ? null
            : () {
                // The strip sits outside the screens, so open the list on
                // the router's own navigator.
                final nav = ref
                    .read(routerProvider)
                    .routerDelegate
                    .navigatorKey
                    .currentContext;
                if (nav == null) return;
                showModalBottomSheet<void>(
                  context: nav,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => const _PendingSheet(),
                );
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.s4,
            vertical: Tokens.s2,
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: Tokens.s2),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (waiting + failed > 0)
                const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

String changeLabel(AppLocalizations l, String kind) => switch (kind) {
  'ledger.addParty' => l.changeNewPerson,
  'ledger.updateParty' => l.changeEditPerson,
  'ledger.addEntry' => l.changeNewEntry,
  'ledger.setReminder' => l.changeReminder,
  'ledger.reminderDone' => l.changeReminderDone,
  'jobs.create' => l.changeNewJob,
  'jobs.followUp' => l.bookVisit,
  'jobs.setItems' => l.changeItems,
  _ => l.changeJobStep,
};

class _PendingSheet extends ConsumerWidget {
  const _PendingSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final sync = ref.watch(offlineSyncProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final items = sync.pending;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
            child: Text(
              l.pendingTitle,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(Tokens.s4),
              children: [
                for (final c in items)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        c.failed ? Icons.error_outline : Icons.schedule,
                        color: c.failed ? scheme.error : null,
                      ),
                      title: Text(changeLabel(l, c.kind)),
                      subtitle: Text(
                        c.failed
                            ? c.error!
                            : '${l.pendingWaiting}  ·  ${DateFormat.MMMd(locale).add_jm().format(c.createdAt)}',
                      ),
                      trailing: c.failed
                          ? Wrap(
                              children: [
                                IconButton(
                                  tooltip: l.retry,
                                  icon: const Icon(Icons.refresh),
                                  onPressed: () => sync.retry(c.id),
                                ),
                                IconButton(
                                  tooltip: l.remove,
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: scheme.error,
                                  ),
                                  onPressed: () => sync.discard(c.id),
                                ),
                              ],
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Tokens.s4),
            child: FilledButton.icon(
              onPressed: sync.flush,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: Text(l.sendNow),
            ),
          ),
        ],
      ),
    );
  }
}
