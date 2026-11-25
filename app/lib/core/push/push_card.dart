import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../theme/tokens.dart';
import 'push_service.dart';

/// Shown when alerts do not reach this phone, with the button that fixes it.
class PushCard extends ConsumerWidget {
  const PushCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(pushStatusProvider);
    if (status != PushStatus.off && status != PushStatus.failed) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final off = status == PushStatus.off;
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: Tokens.s4,
        vertical: Tokens.s2,
      ),
      padding: const EdgeInsets.all(Tokens.s3),
      decoration: BoxDecoration(
        color: Tokens.saffron.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(Tokens.radius),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.notifications_off_outlined,
            color: Tokens.saffronDeep,
          ),
          const SizedBox(width: Tokens.s2),
          Expanded(child: Text(off ? l.pushOff : l.pushFailed)),
          TextButton(
            onPressed: () => ref.read(pushServiceProvider).turnOn(),
            child: Text(off ? l.turnOn : l.tryAgainShort),
          ),
        ],
      ),
    );
  }
}
