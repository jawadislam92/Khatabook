import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../theme/tokens.dart';

extension AsyncFailed<T> on AsyncValue<T> {
  /// The request failed and there is no earlier result to keep showing.
  bool get failed => hasError && !hasValue;
}

/// The generic error message with a Retry button. Use it wherever a screen
/// or a section of a screen could not load its data.
class LoadError extends StatelessWidget {
  const LoadError({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Tokens.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.errorGeneric, textAlign: TextAlign.center),
            const SizedBox(height: Tokens.s3),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l.retry),
            ),
          ],
        ),
      ),
    );
  }
}

/// A whole screen that is still loading. Keeps the back button.
class LoadingScaffold extends StatelessWidget {
  const LoadingScaffold({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: const Center(child: CircularProgressIndicator()),
  );
}

/// A whole screen that failed to load. Keeps the back button.
class LoadErrorScaffold extends StatelessWidget {
  const LoadErrorScaffold({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: LoadError(onRetry: onRetry),
  );
}
