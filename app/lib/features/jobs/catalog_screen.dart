import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/load_error.dart';
import '../../l10n/app_localizations.dart';
import '../groups/role_labels.dart';
import '../spaces/spaces_repository.dart';
import 'catalog_csv.dart';
import 'job_labels.dart';
import 'jobs_models.dart';
import 'jobs_repository.dart';

class CatalogScreen extends ConsumerWidget {
  const CatalogScreen({
    super.key,
    required this.spaceId,
    this.embedded = false,
  });
  final String spaceId;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final items = ref.watch(catalogProvider(spaceId));
    final space = ref
        .watch(mySpacesProvider)
        .value
        ?.where((s) => s.id == spaceId)
        .firstOrNull;
    final manager = roleAtLeast(
      space?.myRole ?? MemberRole.viewer,
      MemberRole.manager,
    );
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.catalog),
        automaticallyImplyLeading: !embedded,
        actions: [
          if (manager)
            PopupMenuButton<String>(
              onSelected: (v) => switch (v) {
                'export' => _export(context, ref, items.value ?? const []),
                'import' => _import(context, ref, items.value ?? const []),
                _ => _sample(),
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'import',
                  child: ListTile(
                    leading: const Icon(Icons.upload_file),
                    title: Text(l.catalogImport),
                  ),
                ),
                PopupMenuItem(
                  value: 'export',
                  child: ListTile(
                    leading: const Icon(Icons.download),
                    title: Text(l.catalogExport),
                  ),
                ),
                PopupMenuItem(
                  value: 'sample',
                  child: ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(l.catalogSample),
                  ),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: manager
          ? FloatingActionButton.extended(
              heroTag: 'new-item',
              onPressed: () => _edit(context, ref, null),
              icon: const Icon(Icons.add),
              label: Text(l.newItem),
            )
          : null,
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            LoadError(onRetry: () => ref.invalidate(catalogProvider(spaceId))),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Tokens.s5),
                child: Text(
                  l.noItems,
                  textAlign: TextAlign.center,
                  style: text.bodyLarge,
                ),
              ),
            );
          }
          final cats = <String, List<CatalogItem>>{};
          for (final i in list) {
            cats.putIfAbsent(i.category, () => []).add(i);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Tokens.s4,
              0,
              Tokens.s4,
              Tokens.s7 * 2,
            ),
            children: [
              for (final c in itemCategories.where(cats.containsKey)) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    0,
                    Tokens.s4,
                    0,
                    Tokens.s2,
                  ),
                  child: Text(
                    categoryLabel(l, c),
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                for (final i in cats[c]!)
                  Card(
                    margin: const EdgeInsets.only(bottom: Tokens.s2),
                    child: ListTile(
                      leading: Icon(
                        i.isFavourite ? Icons.star : Icons.star_border,
                        color: i.isFavourite ? Tokens.saffron : scheme.outline,
                      ),
                      title: Text(
                        i.name(lang),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: i.active ? null : scheme.onSurfaceVariant,
                          decoration: i.active
                              ? null
                              : TextDecoration.lineThrough,
                        ),
                      ),
                      subtitle: Text(
                        [
                          'Rs ${Money.format(i.salePricePaisa)} / ${unitLabel(l, i.unit)}',
                          if (i.costPricePaisa != null)
                            '${l.costPrice.split(' ').take(2).join(' ')} Rs ${Money.format(i.costPricePaisa!)}',
                        ].join('  ·  '),
                      ),
                      trailing: manager
                          ? const Icon(Icons.edit_outlined)
                          : null,
                      onTap: manager ? () => _edit(context, ref, i) : null,
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _shareFile(List<int> bytes, String name) =>
      SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(bytes),
              name: name,
              mimeType: 'text/csv',
            ),
          ],
        ),
      );

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    List<CatalogItem> items,
  ) {
    final seesCost = items.any((i) => i.costPricePaisa != null);
    return _shareFile(
      catalogCsv(items, includeCost: seesCost),
      'duebook-items.csv',
    );
  }

  Future<void> _sample() =>
      _shareFile(catalogSampleCsv(), 'duebook-items-sample.csv');

  /// Pick a CSV, show what would change, save on OK. Nothing is saved
  /// before the person agrees.
  Future<void> _import(
    BuildContext context,
    WidgetRef ref,
    List<CatalogItem> existing,
  ) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    final bytes = res?.files.firstOrNull?.bytes;
    if (bytes == null || !context.mounted) return;
    final plan = planCatalogImport(
      utf8.decode(bytes, allowMalformed: true),
      spaceId: spaceId,
      existing: existing,
    );
    if (!plan.headerFound) {
      messenger.showSnackBar(SnackBar(content: Text(l.importWrongFile)));
      return;
    }
    final changes = plan.toAdd.length + plan.toUpdate.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.importPreviewTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.importNew(plan.toAdd.length)),
              Text(l.importUpdated(plan.toUpdate.length)),
              if (plan.skipped.isNotEmpty) ...[
                const SizedBox(height: Tokens.s2),
                Text(l.importSkipped(plan.skipped.length)),
                for (final sk in plan.skipped.take(20))
                  Text(switch (sk.reason) {
                    CatalogSkip.noName => l.skipNoName(sk.line),
                    CatalogSkip.badPrice => l.skipBadPrice(sk.line),
                    CatalogSkip.repeated => l.skipRepeated(sk.line),
                  }, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: changes == 0 ? null : () => Navigator.pop(ctx, true),
            child: Text(l.catalogImport),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(jobsRepositoryProvider);
    var saved = 0;
    try {
      for (final i in plan.toAdd) {
        await repo.saveItem(i, isNew: true);
        saved++;
      }
      for (final i in plan.toUpdate) {
        await repo.saveItem(i, isNew: false);
        saved++;
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.errorGeneric)));
    }
    ref.invalidate(catalogProvider(spaceId));
    if (saved > 0) {
      messenger.showSnackBar(SnackBar(content: Text(l.importDone(saved))));
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    CatalogItem? existing,
  ) async {
    final l = AppLocalizations.of(context);
    final nameEn = TextEditingController(text: existing?.nameEn ?? '');
    final nameUr = TextEditingController(text: existing?.nameUr ?? '');
    final sale = TextEditingController(
      text: existing == null ? '' : '${existing.salePricePaisa ~/ 100}',
    );
    final cost = TextEditingController(
      text: existing?.costPricePaisa == null
          ? ''
          : '${existing!.costPricePaisa! ~/ 100}',
    );
    var unit = existing?.unit ?? 'pc';
    var category = existing?.category ?? 'camera';
    // New items show as a quick tile, so they are one tap away on Items used.
    var fav = existing?.isFavourite ?? true;
    var edit = existing?.allowPriceEdit ?? false;
    var active = existing?.active ?? true;
    final space = ref
        .read(mySpacesProvider)
        .value
        ?.where((s) => s.id == spaceId)
        .firstOrNull;
    final owner = space?.myRole == MemberRole.owner;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.fromLTRB(
            Tokens.s4,
            0,
            Tokens.s4,
            MediaQuery.viewInsetsOf(ctx).bottom + Tokens.s4,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  existing == null ? l.newItem : l.editItem,
                  style: Theme.of(ctx).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: Tokens.s3),
                TextField(
                  controller: nameEn,
                  decoration: InputDecoration(labelText: l.itemNameEn),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: Tokens.s2),
                TextField(
                  controller: nameUr,
                  decoration: InputDecoration(labelText: l.itemNameUr),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: Tokens.s2),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: sale,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: l.salePrice,
                          prefixText: 'Rs ',
                        ),
                      ),
                    ),
                    const SizedBox(width: Tokens.s2),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: unit,
                        decoration: InputDecoration(labelText: l.unit),
                        items: [
                          for (final u in itemUnits)
                            DropdownMenuItem(
                              value: u,
                              child: Text(unitLabel(l, u)),
                            ),
                        ],
                        onChanged: (v) => setState(() => unit = v ?? unit),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Tokens.s2),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: InputDecoration(labelText: l.category),
                  items: [
                    for (final c in itemCategories)
                      DropdownMenuItem(
                        value: c,
                        child: Text(categoryLabel(l, c)),
                      ),
                  ],
                  onChanged: (v) => setState(() => category = v ?? category),
                ),
                if (owner) ...[
                  const SizedBox(height: Tokens.s2),
                  TextField(
                    controller: cost,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l.costPrice,
                      prefixText: 'Rs ',
                    ),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.favouriteItem),
                  value: fav,
                  onChanged: (v) => setState(() => fav = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.allowPriceEdit),
                  value: edit,
                  onChanged: (v) => setState(() => edit = v),
                ),
                if (existing != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.itemActive),
                    value: active,
                    onChanged: (v) => setState(() => active = v),
                  ),
                const SizedBox(height: Tokens.s3),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    ctx,
                    nameEn.text.trim().isNotEmpty &&
                        Money.parse(sale.text) != null,
                  ),
                  child: Text(l.save),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved != true) return;
    final item = CatalogItem(
      id: existing?.id ?? '',
      spaceId: spaceId,
      nameEn: nameEn.text,
      nameUr: nameUr.text,
      unit: unit,
      category: category,
      salePricePaisa: Money.parse(sale.text) ?? 0,
      costPricePaisa: owner ? Money.parse(cost.text) : existing?.costPricePaisa,
      isFavourite: fav,
      allowPriceEdit: edit,
      active: active,
    );
    await ref
        .read(jobsRepositoryProvider)
        .saveItem(item, isNew: existing == null);
  }
}
