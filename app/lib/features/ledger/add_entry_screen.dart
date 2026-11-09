import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
import '../../core/utils/number_words.dart';
import '../../core/widgets/load_error.dart';
import '../../core/widgets/number_pad.dart';
import '../../l10n/app_localizations.dart';
import 'ledger_models.dart';
import 'ledger_repository.dart';
import 'party_form.dart';

/// Two steps: who, then how much. Ends with a plain sentence to confirm.
class AddEntryScreen extends ConsumerStatefulWidget {
  const AddEntryScreen({
    super.key,
    required this.spaceId,
    required this.direction,
    this.partyId,
  });
  final String spaceId;
  final EntryDirection direction;
  final String? partyId;

  @override
  ConsumerState<AddEntryScreen> createState() => _AddEntryScreenState();
}

class _AddEntryScreenState extends ConsumerState<AddEntryScreen> {
  String? _partyId;
  String _digits = '';
  DateTime _date = DateTime.now();
  final _note = TextEditingController();
  final _search = TextEditingController();
  String _query = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _partyId = widget.partyId;
  }

  @override
  void dispose() {
    _note.dispose();
    _search.dispose();
    super.dispose();
  }

  int get _paisa => (int.tryParse(_digits) ?? 0) * 100;

  Color _color(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return widget.direction == EntryDirection.gave
        ? (dark ? Tokens.getDark : Tokens.get)
        : (dark ? Tokens.giveDark : Tokens.give);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final gave = widget.direction == EntryDirection.gave;
    final title = gave ? l.iGaveMoney : l.iGotMoney;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: _color(context),
        foregroundColor: Colors.white,
        leading: _partyId != null && widget.partyId == null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _partyId = null),
              )
            : null,
      ),
      body: _partyId == null ? _pickParty(context) : _amount(context),
    );
  }

  Widget _pickParty(BuildContext context) {
    final l = AppLocalizations.of(context);
    final parties = ref.watch(partyBalancesProvider(widget.spaceId));
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Tokens.s4,
            Tokens.s4,
            Tokens.s4,
            Tokens.s2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.whoIsThis,
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: Tokens.s3),
              TextField(
                controller: _search,
                autofocus: (parties.value?.length ?? 0) > 6,
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: l.searchPeople,
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: parties.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => LoadError(
              onRetry: () =>
                  ref.invalidate(partyBalancesProvider(widget.spaceId)),
            ),
            data: (list) {
              final filtered =
                  (_query.isEmpty
                          ? list
                          : list.where(
                              (p) =>
                                  p.party.name.toLowerCase().contains(_query),
                            ))
                      .toList()
                    ..sort(
                      (a, b) => (b.lastEntryDate ?? DateTime(2000)).compareTo(
                        a.lastEntryDate ?? DateTime(2000),
                      ),
                    );
              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  Tokens.s4,
                  0,
                  Tokens.s4,
                  Tokens.s6,
                ),
                children: [
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Tokens.saffron,
                        child: const Icon(
                          Icons.person_add_alt_1,
                          color: Colors.black,
                        ),
                      ),
                      title: Text(
                        _query.isEmpty
                            ? l.newPerson
                            : '${l.newPerson}: ${_search.text.trim()}',
                      ),
                      onTap: () async {
                        final p = await showPartyForm(
                          context,
                          ref,
                          spaceId: widget.spaceId,
                          initialName: _search.text.trim(),
                        );
                        if (p != null) setState(() => _partyId = p.id);
                      },
                    ),
                  ),
                  const SizedBox(height: Tokens.s2),
                  for (final pb in filtered)
                    Card(
                      margin: const EdgeInsets.only(bottom: Tokens.s2),
                      child: ListTile(
                        leading: CircleAvatar(child: Text(pb.party.initials)),
                        title: Text(pb.party.name),
                        subtitle: pb.settled
                            ? null
                            : Text(
                                pb.willGet
                                    ? l.youWillGetFrom(
                                        Money.format(pb.balancePaisa),
                                        pb.party.name,
                                      )
                                    : l.youWillGiveTo(
                                        Money.format(-pb.balancePaisa),
                                        pb.party.name,
                                      ),
                              ),
                        onTap: () => setState(() => _partyId = pb.party.id),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _amount(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final simple = ref.watch(appSettingsProvider).simpleMode;
    final lang = Localizations.localeOf(context).languageCode;
    final pb = ref.watch(partyProvider((widget.spaceId, _partyId!)));
    final name = pb?.party.name ?? '';
    final color = _color(context);
    final gave = widget.direction == EntryDirection.gave;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Tokens.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.15),
                      child: Text(
                        pb?.party.initials ?? '?',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: Tokens.s3),
                    Expanded(
                      child: Text(
                        gave ? l.youGaveTo(name) : l.youGotFrom(name),
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Tokens.s5),
                Text(
                  l.howMuch,
                  style: text.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Tokens.s1),
                Text(
                  _digits.isEmpty
                      ? 'Rs 0'
                      : 'Rs ${Money.groupDigits(int.parse(_digits))}',
                  style: TextStyle(
                    fontSize: simple ? 44 : 40,
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontFamily: 'Roboto',
                  ),
                ),
                SizedBox(
                  height: 28,
                  child: _digits.isEmpty
                      ? null
                      : Text(
                          NumberWords.rupees(int.parse(_digits), lang),
                          style: text.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                ),
                const SizedBox(height: Tokens.s3),
                Wrap(
                  spacing: Tokens.s2,
                  runSpacing: Tokens.s2,
                  children: [
                    for (final q in const [500, 1000, 2000, 5000, 10000])
                      ActionChip(
                        label: Text(Money.groupDigits(q)),
                        onPressed: () => setState(() => _digits = '$q'),
                      ),
                  ],
                ),
                const SizedBox(height: Tokens.s4),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(friendlyDate(context, _date)),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(2015),
                            lastDate: DateTime.now().add(
                              const Duration(days: 1),
                            ),
                          );
                          if (d != null) setState(() => _date = d);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Tokens.s3),
                TextField(
                  controller: _note,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: l.noteOptional,
                    hintText: l.noteHint,
                  ),
                  maxLength: 200,
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(
            Tokens.s4,
            Tokens.s2,
            Tokens.s4,
            Tokens.s4,
          ),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outline)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                NumberPad(
                  onDigit: (d) {
                    if (_digits.length >= 9) return;
                    if (_digits.isEmpty && d == '0') return;
                    setState(() => _digits += d);
                  },
                  onBackspace: () => setState(
                    () => _digits = _digits.isEmpty
                        ? ''
                        : _digits.substring(0, _digits.length - 1),
                  ),
                ),
                const SizedBox(height: Tokens.s3),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: color),
                  onPressed: _paisa > 0 && !_saving
                      ? () => _confirm(name)
                      : null,
                  child: Text(l.save),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirm(String name) async {
    final l = AppLocalizations.of(context);
    final amount = Money.format(_paisa);
    final date = friendlyDate(context, _date);
    final gave = widget.direction == EntryDirection.gave;
    final now = DateTime.now();
    final isToday =
        _date.year == now.year &&
        _date.month == now.month &&
        _date.day == now.day;
    final sentence = isToday
        ? (gave
              ? l.confirmGaveToday(amount, name)
              : l.confirmGotToday(amount, name))
        : (gave
              ? l.confirmGave(amount, name, date)
              : l.confirmGot(amount, name, date));
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(sentence, style: Theme.of(ctx).textTheme.titleMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.no),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.yes),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(ledgerRepositoryProvider)
          .addEntry(
            NewEntry(
              spaceId: widget.spaceId,
              partyId: _partyId!,
              direction: widget.direction,
              amountPaisa: _paisa,
              entryDate: _date,
              note: _note.text,
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.saved)));
      if (widget.partyId == null) {
        context.pushReplacement('/space/${widget.spaceId}/party/$_partyId');
      } else {
        context.pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.errorGeneric)));
      }
    }
  }
}
