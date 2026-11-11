import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../theme/tokens.dart';

/// A newer Android build published on the website.
class AppUpdate {
  const AppUpdate({required this.build, required this.apkUrl, this.notes});
  final int build;
  final String apkUrl;
  final String? notes;
}

/// Where the app learns about new versions. The website holds
/// `version.json` like {"build": 3, "apk": "https://.../duebook.apk",
/// "notes": "..."} next to the APK. No Play Store needed.
abstract class UpdateSource {
  Future<int> currentBuild();
  Future<AppUpdate?> latest();
}

class WebsiteUpdateSource implements UpdateSource {
  static const url = 'https://duebook.sparkingasia.com/version.json';

  @override
  Future<int> currentBuild() async =>
      int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;

  @override
  Future<AppUpdate?> latest() async {
    final r = await http
        .get(Uri.parse(url), headers: {'Cache-Control': 'no-cache'})
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final build = (j['build'] as num?)?.toInt();
    final apk = j['apk'] as String?;
    if (build == null || apk == null || !apk.startsWith('https://')) {
      return null;
    }
    return AppUpdate(build: build, apkUrl: apk, notes: j['notes'] as String?);
  }
}

final updateSourceProvider = Provider<UpdateSource>(
  (_) => WebsiteUpdateSource(),
);

/// The update to offer, or null. Only Android installs APKs from the
/// website; anywhere else, and on any failure, it stays quiet.
final availableUpdateProvider = FutureProvider<AppUpdate?>((ref) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    final source = ref.watch(updateSourceProvider);
    final latest = await source.latest();
    if (latest == null) return null;
    return latest.build > await source.currentBuild() ? latest : null;
  } catch (_) {
    return null;
  }
});

/// "A new version is ready" with an Update button. Shows nothing when
/// there is no newer build.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(availableUpdateProvider).value;
    if (update == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Card(
      color: Tokens.primary.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radius),
        side: const BorderSide(color: Tokens.primary, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Tokens.s3),
        child: Row(
          children: [
            const Icon(Icons.system_update, color: Tokens.primary),
            const SizedBox(width: Tokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.updateReady,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (update.notes != null && update.notes!.isNotEmpty)
                    Text(update.notes!, style: text.bodyMedium),
                ],
              ),
            ),
            FilledButton(
              // The theme makes buttons full width; this one sits in a row.
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => launchUrl(
                Uri.parse(update.apkUrl),
                mode: LaunchMode.externalApplication,
              ),
              child: Text(l.updateNow),
            ),
          ],
        ),
      ),
    );
  }
}
