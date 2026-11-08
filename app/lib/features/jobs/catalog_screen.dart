import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/money.dart';
import '../../l10n/app_localizations.dart';
import '../groups/role_labels.dart';
import '../spaces/spaces_repository.dart';
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
        error: (e, _) => Center(child: Text(l.errorGeneric)),
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
    var fav = existing?.isFavourite ?? false;
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
