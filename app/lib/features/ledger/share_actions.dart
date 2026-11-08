import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
import '../../l10n/app_localizations.dart';
import 'ledger_models.dart';
import 'ledger_repository.dart';
import 'statement.dart';

/// Opens WhatsApp (or SMS) with a ready reminder message for the party.
Future<void> sendReminderMessage(
  BuildContext context,
  PartyBalance pb, {
  bool sms = false,
}) async {
  final l = AppLocalizations.of(context);
  final phone = pb.party.phone;
  if (phone == null || phone.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.noPhone(pb.party.name))));
    return;
  }
  final amount = Money.format(pb.balancePaisa.abs());
  final msg = pb.willGet
      ? l.reminderMessageGet(pb.party.name, amount)
      : l.reminderMessageGive(pb.party.name, amount);
  final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
  final intl = digits.startsWith('0')
      ? '92${digits.substring(1)}'
      : digits.replaceFirst('+', '');
  final uri = sms
      ? Uri(scheme: 'sms', path: digits, queryParameters: {'body': msg})
      : Uri.parse('https://wa.me/$intl?text=${Uri.encodeComponent(msg)}');
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.couldNotOpenApp)));
  }
}

/// Builds the PDF statement for a party and opens the share sheet.
Future<void> shareStatement(
  BuildContext context,
  WidgetRef ref,
  PartyBalance pb,
  String spaceName,
) async {
  final l = AppLocalizations.of(context);
  final rtl = Directionality.of(context) == TextDirection.rtl;
  final entries = await ref
      .read(ledgerRepositoryProvider)
      .entriesForParty(pb.party.id);
  if (!context.mounted) return;
  final bytes = await Statement.pdf(
    party: pb.party,
    entries: entries,
    spaceName: spaceName,
    rtl: rtl,
    labels: StatementLabels(
      title: l.statementTitle,
      date: l.date,
      note: l.noteOptional.split(' ').first,
      gave: l.gave,
      got: l.got,
      balance: l.runningBalance,
      totalGave: l.totalGave,
      totalGot: l.totalGot,
      closing: l.closingBalance,
      cancelled: l.cancelled,
      generated: l.generatedOn(isoDate(DateTime.now())),
      willGet: l.youWillGet,
      willGive: l.youWillGive,
    ),
  );
  await Printing.sharePdf(
    bytes: bytes,
    filename:
        'statement-${pb.party.name.replaceAll(RegExp(r'[^\w]+'), '_')}.pdf',
  );
}

/// CSV of the whole space, shared as a file.
Future<void> shareCsv(
  BuildContext context,
  WidgetRef ref,
  String spaceId,
  String spaceName,
) async {
  final repo = ref.read(ledgerRepositoryProvider);
  final entries = await repo.entriesForSpace(spaceId);
  final parties = {
    for (final pb in await repo.partiesWithBalances(spaceId))
      pb.party.id: pb.party,
  };
  final bytes = Statement.csv(entries: entries, parties: parties);
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          bytes,
          name: 'duebook-$spaceName-${isoDate(DateTime.now())}.csv',
          mimeType: 'text/csv',
        ),
      ],
    ),
  );
}
