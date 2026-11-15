import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_parliament/models/debate.dart';
import 'package:open_parliament/models/member.dart';
import 'package:open_parliament/models/speech.dart';
import 'package:open_parliament/services/api_services.dart';
import 'package:open_parliament/services/database_service.dart';
import 'package:open_parliament/services/parliamentary_data_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Hansard fake: serves a fixed set of root debates for any date, each with
/// one speech per entry in [speechesPerDebate]. Counts network calls.
class _FakeHansardApi extends HansardApiService {
  List<Debate> debates;
  Map<String, List<String>> speechesPerDebate;
  int sittingFetches = 0;
  bool fail = false;

  _FakeHansardApi({required this.debates, required this.speechesPerDebate});

  @override
  Future<List<Debate>> fetchSittingDebates(String date, {String? house}) async {
    sittingFetches++;
    if (fail) throw const SocketException('offline');
    return debates;
  }

  @override
  Future<Map<String, dynamic>?> fetchDebateJson(String debateId) async => {
    'id': debateId,
  };

  @override
  List<Speech> parseDebateSpeeches(
    Map<String, dynamic> body,
    String debateId,
    String debateTitle, {
    int startOrderIndex = 0,
  }) {
    final texts = speechesPerDebate[debateId] ?? const [];
    return [
      for (var i = 0; i < texts.length; i++)
        Speech(
          id: '$debateId-$i',
          debateId: debateId,
          debateTitle: debateTitle,
          rootDebateId: debateId,
          memberName: 'Member',
          attributedTo: 'Member',
          speechText: texts[i],
          orderIndex: startOrderIndex + i,
        ),
    ];
  }
}

class _FakeMembersApi extends MembersApiService {
  List<Member> members;
  int fetches = 0;

  _FakeMembersApi(this.members);

  @override
  Future<List<Member>> fetchAllMembers() async {
    fetches++;
    return members;
  }
}

Member _member(int id, String name) =>
    Member(id: id, name: name, party: 'Labour', partyAbbreviation: 'Lab');

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  late DatabaseService db;
  late _FakeHansardApi hansard;
  late _FakeMembersApi membersApi;
  late ParliamentaryDataService service;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('op_data_test_');
    db = DatabaseService(directory: () async => dir);
    hansard = _FakeHansardApi(
      debates: const [
        Debate(id: 'A', title: 'First', house: 'Commons', orderIndex: 0),
        Debate(id: 'B', title: 'Second', house: 'Commons', orderIndex: 1),
      ],
      speechesPerDebate: {
        'A': ['a0', 'a1'],
        'B': ['b0'],
      },
    );
    membersApi = _FakeMembersApi([_member(1, 'Alice'), _member(2, 'Bob')]);
    service = ParliamentaryDataService(
      databaseService: db,
      hansardApiService: hansard,
      membersApiService: membersApi,
    );
  });

  tearDown(() async {
    // Close every database the test opened before removing the directory.
    for (final f in dir.listSync().whereType<File>()) {
      if (f.path.endsWith('.db')) await deleteDatabase(f.path);
    }
    await dir.delete(recursive: true);
  });

  group('getSpeeches', () {
    test(
      'fetches, persists in document order, then serves from cache',
      () async {
        // A settled day (well in the past) is never re-checked once cached.
        const date = '2024-03-05';
        final first = await service.getSpeeches(date);
        expect(first.map((s) => s.speechText), ['a0', 'a1', 'b0']);
        expect(first.map((s) => s.orderIndex), [0, 1, 2]);
        expect(hansard.sittingFetches, 1);

        final again = await service.getSpeeches(date);
        expect(again.map((s) => s.speechText), ['a0', 'a1', 'b0']);
        expect(hansard.sittingFetches, 1, reason: 'settled day served locally');

        final debates = await service.getDebatesForDate(date);
        expect(debates.map((d) => d.id), ['A', 'B']);
      },
    );

    test('concurrent calls for one date share a single fetch', () async {
      const date = '2024-03-06';
      await Future.wait([
        service.getSpeeches(date),
        service.getSpeeches(date),
        service.getSpeeches(date),
      ]);
      expect(hansard.sittingFetches, 1);
    });

    test('a day cached before it settled is re-checked, and falls back to the '
        'cached copy when offline', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final date = DatabaseSelectorDate.format(today);

      await service.getSpeeches(date);
      expect(hansard.sittingFetches, 1);

      // Backdate fetched_at past the 30-minute re-check window.
      final sitting = await db.openSittingDb(date);
      await sitting.update(
        'meta',
        {
          'value':
              '${now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch}',
        },
        where: 'key = ?',
        whereArgs: ['fetched_at'],
      );

      hansard.fail = true;
      final offline = await service.getSpeeches(date);
      expect(hansard.sittingFetches, 2, reason: 'stale day was re-checked');
      expect(offline.map((s) => s.speechText), ['a0', 'a1', 'b0']);
    });

    test('a refresh replaces rows that no longer exist upstream', () async {
      const date = '2024-03-07';
      await service.getSpeeches(date);

      hansard
        ..debates = const [
          Debate(id: 'A', title: 'First', house: 'Commons', orderIndex: 0),
        ]
        ..speechesPerDebate = {
          'A': ['a0-revised'],
        };
      await service.refreshSitting(date);

      final cached = await service.getCachedSpeeches(date);
      expect(cached!.map((s) => s.speechText), ['a0-revised']);
      final debates = await service.getDebatesForDate(date);
      expect(debates.map((d) => d.id), ['A']);
    });

    test('refreshSitting throws offline and leaves the cache intact', () async {
      const date = '2024-03-08';
      await service.getSpeeches(date);
      hansard.fail = true;
      await expectLater(service.refreshSitting(date), throwsA(anything));
      final cached = await service.getCachedSpeeches(date);
      expect(cached, hasLength(3));
    });

    test('getCachedSpeeches is null for a day never fetched', () async {
      expect(await service.getCachedSpeeches('2024-01-01'), isNull);
      expect(hansard.sittingFetches, 0);
    });
  });

  group('members', () {
    test('fetched once, persisted, and memoised in memory', () async {
      final first = await service.getMembers();
      expect(first.map((m) => m.name), containsAll(['Alice', 'Bob']));
      await service.getMembers();
      expect(membersApi.fetches, 1);

      // A fresh service over the same files reads SQLite, not the network.
      final second = ParliamentaryDataService(
        databaseService: db,
        hansardApiService: hansard,
        membersApiService: membersApi,
      );
      final fromDisk = await second.getMembers();
      expect(fromDisk.map((m) => m.name), ['Alice', 'Bob']);
      expect(membersApi.fetches, 1);
      expect((await second.getMemberById(2))?.name, 'Bob');
    });

    test('clearCachedMembers forces a re-fetch', () async {
      await service.getMembers();
      await service.clearCachedMembers();
      membersApi.members = [_member(3, 'Carol')];
      final members = await service.getMembers();
      expect(members.map((m) => m.name), ['Carol']);
      expect(membersApi.fetches, 2);
    });

    test('an empty API response keeps the existing roster', () async {
      await service.getMembers();
      await service.clearCachedMembers();
      await service.getMembers(); // re-populate
      final db2 = await db.openMembersDb();
      await db2.delete('meta'); // force stale
      membersApi.members = const [];
      final fresh = ParliamentaryDataService(
        databaseService: db,
        hansardApiService: hansard,
        membersApiService: membersApi,
      );
      expect(
        (await fresh.getMembers()).map((m) => m.name),
        containsAll(['Alice', 'Bob']),
      );
    });

    test('speaker aliases round-trip and are replaced on conflict', () async {
      await service.saveSpeakerAliasMemberIds({'the minister|2024': 1});
      await service.saveSpeakerAliasMemberIds({'the minister|2024': 2, ' ': 9});
      final ids = await service.getSpeakerAliasMemberIds([
        'the minister|2024',
        'unknown',
      ]);
      expect(ids, {'the minister|2024': 2});
    });
  });

  group('migrations', () {
    test(
      'a v4 sitting database upgrades and is flagged for backfill',
      () async {
        const date = '2023-11-20';
        final path = await db.sittingDbPath(date);
        final legacy = await openDatabase(
          path,
          version: 4,
          onCreate: (d, _) async {
            await d.execute(
              'CREATE TABLE debates (id TEXT PRIMARY KEY, '
              'title TEXT, house TEXT, section TEXT, order_idx INTEGER)',
            );
            await d.execute(
              'CREATE TABLE speeches (id TEXT PRIMARY KEY, '
              'debate_id TEXT NOT NULL, debate_title TEXT, item_type TEXT, '
              'hrs_tag TEXT, member_id INTEGER, member_name TEXT, '
              'attributed_to TEXT, speech_text TEXT, timecode TEXT, '
              'order_idx INTEGER)',
            );
            await d.insert('speeches', {
              'id': 'old',
              'debate_id': 'A',
              'member_name': 'M',
              'attributed_to': 'M',
              'speech_text': 'legacy',
              'order_idx': 0,
            });
          },
        );
        await legacy.close();

        // Legacy rows have no root_debate_id: not usable as a saved copy...
        expect(await service.getCachedSpeeches(date), isNull);
        // ...and getSpeeches re-fetches to backfill.
        final speeches = await service.getSpeeches(date);
        expect(hansard.sittingFetches, 1);
        expect(speeches.every((s) => s.rootDebateId != null), isTrue);
      },
    );

    test(
      'a v4 members database gains the constituency column and re-fetches',
      () async {
        final path = await db.membersDbPath();
        final legacy = await openDatabase(
          path,
          version: 4,
          onCreate: (d, _) async {
            await d.execute(
              'CREATE TABLE members (id INTEGER PRIMARY KEY, '
              'name TEXT NOT NULL, party TEXT, party_abbreviation TEXT, '
              'thumbnail_url TEXT, constituency TEXT)',
            );
            await d.execute(
              'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)',
            );
            await d.execute(
              'CREATE TABLE speaker_aliases (alias_key TEXT '
              'PRIMARY KEY, member_id INTEGER NOT NULL, updated_at INTEGER '
              'NOT NULL)',
            );
            await d.insert('meta', {
              'key': 'last_fetched',
              'value': '${DateTime.now().toUtc().millisecondsSinceEpoch}',
            });
          },
        );
        await legacy.close();

        await service.getMembers();
        expect(membersApi.fetches, 1, reason: 'v5 drops the freshness marker');
      },
    );
  });

  group('evictSittings', () {
    Future<void> seed(String date, DateTime used) async {
      final d = await db.openSittingDb(date);
      await d.close();
      await File(await db.sittingDbPath(date)).setLastModified(used);
    }

    test('deletes least recently used days beyond the cap', () async {
      final now = DateTime(2026, 6, 1);
      await seed('2025-01-01', now.subtract(const Duration(days: 1)));
      await seed('2025-01-02', now.subtract(const Duration(days: 30)));
      await seed('2025-01-03', now.subtract(const Duration(days: 10)));

      final deleted = await db.evictSittings(keep: 2, now: now);
      expect(deleted, 1);
      expect(await db.cachedSittingDates(), ['2025-01-03', '2025-01-01']);
    });

    test('never deletes recent or protected days', () async {
      final now = DateTime(2026, 6, 1);
      final old = now.subtract(const Duration(days: 365));
      await seed('2026-05-28', old); // within 14 days of now
      await seed('2025-02-01', old); // protected
      await seed('2025-02-02', old); // evictable
      await seed('2025-02-03', now);

      final deleted = await db.evictSittings(
        keep: 1,
        now: now,
        protect: {'2025-02-01'},
      );
      expect(deleted, 1);
      expect(await db.cachedSittingDates(), [
        '2026-05-28',
        '2025-02-03',
        '2025-02-01',
      ]);
    });

    test('reading a day bumps it to most recently used', () async {
      final now = DateTime.now();
      final old = now.subtract(const Duration(days: 400));
      await service.getSpeeches('2024-04-01');
      await service.getSpeeches('2024-04-02');
      for (final date in ['2024-04-01', '2024-04-02']) {
        await File(await db.sittingDbPath(date)).setLastModified(old);
      }
      await service.getSpeeches('2024-04-01'); // touch

      await db.evictSittings(keep: 1);
      expect(await db.cachedSittingDates(), ['2024-04-01']);
    });
  });
}

/// Mirrors the data layer's `YYYY-MM-DD` key format.
class DatabaseSelectorDate {
  static String format(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
