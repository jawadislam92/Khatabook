// Ledger models. Money is always integer paisa.
import 'package:characters/characters.dart';

enum EntryDirection { gave, got }

enum EntrySource { manual, invoice, payment, reversal }

class Party {
  const Party({
    required this.id,
    required this.spaceId,
    required this.name,
    this.phone,
    this.isCustomer = false,
    this.address,
    this.notes,
  });

  final String id;
  final String spaceId;
  final String name;
  final String? phone;
  final bool isCustomer;
  final String? address;
  final String? notes;

  Party copyWith({
    String? name,
    String? phone,
    String? address,
    String? notes,
  }) => Party(
    id: id,
    spaceId: spaceId,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    isCustomer: isCustomer,
    address: address ?? this.address,
    notes: notes ?? this.notes,
  );

  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

/// A party together with its running balance.
class PartyBalance {
  const PartyBalance({
    required this.party,
    required this.balancePaisa,
    required this.entryCount,
    this.lastEntryDate,
  });

  final Party party;

  /// Positive: they owe us ("you will get"). Negative: we owe them.
  final int balancePaisa;
  final int entryCount;
  final DateTime? lastEntryDate;

  bool get willGet => balancePaisa > 0;
  bool get willGive => balancePaisa < 0;
  bool get settled => balancePaisa == 0;
}

class SpaceTotals {
  const SpaceTotals({required this.willGetPaisa, required this.willGivePaisa});
  final int willGetPaisa;
  final int willGivePaisa;
  int get netPaisa => willGetPaisa - willGivePaisa;
  static const zero = SpaceTotals(willGetPaisa: 0, willGivePaisa: 0);
}

class Entry {
  const Entry({
    required this.id,
    required this.spaceId,
    required this.bookId,
    required this.partyId,
    required this.direction,
    required this.amountPaisa,
    required this.entryDate,
    required this.createdBy,
    required this.createdAt,
    this.createdByName,
    this.note,
    this.source = EntrySource.manual,
    this.reversalOf,
    this.voidedAt,
    this.updatedAt,
  });

  final String id;
  final String spaceId;
  final String bookId;
  final String partyId;
  final EntryDirection direction;
  final int amountPaisa;
  final DateTime entryDate;
  final String? note;
  final EntrySource source;
  final String? reversalOf;
  final DateTime? voidedAt;
  final String createdBy;
  final String? createdByName;
  final DateTime createdAt;
  final DateTime? updatedAt;

  bool get isVoided => voidedAt != null;
  bool get isReversal => source == EntrySource.reversal;
  bool get wasEdited =>
      updatedAt != null && updatedAt!.difference(createdAt).inSeconds > 2;

  /// Signed effect on the party balance.
  int get signedPaisa =>
      direction == EntryDirection.gave ? amountPaisa : -amountPaisa;
}

class Reminder {
  const Reminder({
    required this.id,
    required this.spaceId,
    required this.partyId,
    required this.dueDate,
    this.note,
    this.doneAt,
  });
  final String id;
  final String spaceId;
  final String partyId;
  final DateTime dueDate;
  final String? note;
  final DateTime? doneAt;
  bool get isDone => doneAt != null;
}

class NewEntry {
  const NewEntry({
    required this.spaceId,
    required this.partyId,
    required this.direction,
    required this.amountPaisa,
    required this.entryDate,
    this.note,
  });
  final String spaceId;
  final String partyId;
  final EntryDirection direction;
  final int amountPaisa;
  final DateTime entryDate;
  final String? note;
}

class EntryEdit {
  const EntryEdit({
    this.amountPaisa,
    this.direction,
    this.entryDate,
    this.note,
  });
  final int? amountPaisa;
  final EntryDirection? direction;
  final DateTime? entryDate;
  final String? note;
}
