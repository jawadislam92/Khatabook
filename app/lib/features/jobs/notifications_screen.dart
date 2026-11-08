import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import 'jobs_repository.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final list = ref.watch(notificationsProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    return Scaffold(
      appBar: AppBar(title: Text(l.notifications)),
      body: Column(
        children: [
          if (!AppConfig.pushEnabled)
            Container(
              margin: const EdgeInsets.all(Tokens.s4),
              padding: const EdgeInsets.all(Tokens.s3),
              decoration: BoxDecoration(
                color: Tokens.saffron.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(Tokens.radius),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Tokens.saffronDeep),
                  const SizedBox(width: Tokens.s2),
                  Expanded(child: Text(l.pushNotReady, style: text.bodyMedium)),
                ],
              ),
            ),
          Expanded(
            child: list.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(l.errorGeneric)),
              data: (items) => items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(Tokens.s5),
                        child: Text(
                          l.noNotifications,
                          textAlign: TextAlign.center,
                          style: text.bodyLarge,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        Tokens.s4,
                        0,
                        Tokens.s4,
                        Tokens.s6,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final n = items[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor:
                                (n.unread ? Tokens.primary : scheme.outline)
                                    .withValues(alpha: 0.15),
                            child: Icon(
                              n.kind.startsWith('job')
                                  ? Icons.assignment_outlined
                                  : Icons.notifications_outlined,
                              color: n.unread
                                  ? Tokens.primary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          title: Text(
                            n.title,
                            style: TextStyle(
                              fontWeight: n.unread
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${n.body}\n${DateFormat.MMMd(locale).add_jm().format(n.createdAt.toLocal())}',
                          ),
                          isThreeLine: true,
                          onTap: () async {
                            if (n.unread) {
                              await ref
                                  .read(jobsRepositoryProvider)
                                  .markRead(n.id);
                            }
                            if (n.deepLink != null && context.mounted) {
                              context.push(n.deepLink!);
                            }
                          },
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
