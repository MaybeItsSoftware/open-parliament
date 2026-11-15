import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Manages the local SQLite databases used for the local-first data strategy.
///
/// Two database families are maintained:
///  - `members.db`  — cached MP profiles, refreshed every 30 days.
///  - `sitting_YYYY-MM-DD.db` — one database per sitting day; created on first
///    fetch and only rewritten while the day may still be publishing (see
///    `ParliamentaryDataService.getSpeeches`).
class DatabaseService {
  static const String _membersDbName = 'members.db';

  /// How many sitting days to keep on disk. Each day is its own database
  /// (often a few MB for a busy day); without a cap the cache grows forever.
  static const int defaultSittingKeepCount = 60;

  /// Sitting days within this many days of today are never evicted: they
  /// are the ones the landing screen and stepper open, and may be in use.
  static const int recentSittingProtectionDays = 14;

  final Future<Directory> Function() _directory;

  /// [directory] overrides where databases live (tests use a temp dir).
  DatabaseService({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  /// Returns the absolute path to the members database file.
  Future<String> membersDbPath() async {
    final dir = await _directory();
    return p.join(dir.path, _membersDbName);
  }

  /// Returns the absolute path to the sitting database for [date] (YYYY-MM-DD).
  Future<String> sittingDbPath(String date) async {
    final dir = await _directory();
    return p.join(dir.path, 'sitting_$date.db');
  }

  // ─── Members DB ───────────────────────────────────────────────────────────

  /// Opens (and creates if necessary) the members database.
  Future<Database> openMembersDb() async {
    final path = await membersDbPath();
    return openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE members (
            id               INTEGER PRIMARY KEY,
            name             TEXT    NOT NULL,
            party            TEXT,
            party_abbreviation TEXT,
            thumbnail_url    TEXT,
            constituency     TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE meta (
            key   TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE speaker_aliases (
            alias_key  TEXT PRIMARY KEY,
            member_id  INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_speaker_aliases_member ON speaker_aliases(member_id)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS speaker_aliases (
              alias_key  TEXT PRIMARY KEY,
              member_id  INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_speaker_aliases_member
            ON speaker_aliases(member_id)
          ''');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE members ADD COLUMN constituency TEXT');
        }
        if (oldVersion < 5) {
          // Existing member rows predate the constituency column (it was added
          // empty). Drop the freshness marker so the next read re-fetches
          // members with their constituency populated, enabling the control map.
          await db.delete(
            'meta',
            where: 'key = ?',
            whereArgs: ['last_fetched'],
          );
        }
      },
    );
  }

  /// Deletes all `sitting_*.db` files from the application support directory.
  ///
  /// Returns the number of files deleted.
  Future<int> wipeDebateCache() async {
    final dir = await _directory();
    int count = 0;
    await for (final entity in dir.list()) {
      if (entity is File &&
          p.basename(entity.path).startsWith('sitting_') &&
          p.basename(entity.path).endsWith('.db')) {
        await deleteDatabase(entity.path);
        count++;
      }
    }
    return count;
  }

  /// Clears cached MP profiles and drops the freshness marker so the next read
  /// re-fetches them. Speaker aliases are left intact (member ids are stable).
  /// Returns the number of member rows removed.
  Future<int> wipeMembersCache() async {
    final db = await openMembersDb();
    final count = await db.delete('members');
    await db.delete('meta', where: 'key = ?', whereArgs: ['last_fetched']);
    return count;
  }

  /// Lists cached sitting dates (YYYY-MM-DD) for every local sitting database.
  Future<List<String>> cachedSittingDates() async {
    final dir = await _directory();
    final dates = <String>[];
    final pattern = RegExp(r'^sitting_(\d{4}-\d{2}-\d{2})\.db$');
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final match = pattern.firstMatch(name);
      if (match != null) {
        dates.add(match.group(1)!);
      }
    }
    dates.sort((a, b) => b.compareTo(a));
    return dates;
  }

  /// Marks [date]'s sitting database as just used, so [evictSittings] keeps
  /// it. Reads don't change a file's modified time on their own. Best-effort.
  Future<void> touchSitting(String date) async {
    try {
      await File(await sittingDbPath(date)).setLastModified(DateTime.now());
    } catch (_) {
      // A missing file or a read-only filesystem just means no LRU bump.
    }
  }

  /// Deletes the least recently used sitting databases beyond [keep],
  /// never touching days within [recentSittingProtectionDays] of [now]
  /// or any date in [protect]. Returns the number of days deleted.
  Future<int> evictSittings({
    int keep = defaultSittingKeepCount,
    Set<String> protect = const {},
    DateTime? now,
  }) async {
    final today = now ?? DateTime.now();
    final cutoff = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: recentSittingProtectionDays));
    final dir = await _directory();
    final pattern = RegExp(r'^sitting_(\d{4}-\d{2}-\d{2})\.db$');
    final entries = <({String path, String date, DateTime used})>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final match = pattern.firstMatch(p.basename(entity.path));
      if (match == null) continue;
      entries.add((
        path: entity.path,
        date: match.group(1)!,
        used: entity.lastModifiedSync(),
      ));
    }
    if (entries.length <= keep) return 0;

    entries.sort((a, b) => b.used.compareTo(a.used));
    var deleted = 0;
    for (final entry in entries.skip(keep)) {
      if (protect.contains(entry.date)) continue;
      final day = DateTime.tryParse(entry.date);
      if (day == null || !day.isBefore(cutoff)) continue;
      await deleteDatabase(entry.path);
      deleted++;
    }
    return deleted;
  }

  // ─── Sitting DB ───────────────────────────────────────────────────────────

  /// Returns `true` when a sitting database for [date] already exists locally.
  Future<bool> sittingDbExists(String date) async {
    final path = await sittingDbPath(date);
    return databaseExists(path);
  }

  /// Opens (and creates if necessary) the sitting database for [date].
  Future<Database> openSittingDb(String date) async {
    final path = await sittingDbPath(date);
    return openDatabase(
      path,
      version: 6,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE debates (
            id        TEXT PRIMARY KEY,
            title     TEXT,
            house     TEXT,
            section   TEXT,
            order_idx INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE speeches (
            id           TEXT    PRIMARY KEY,
            debate_id    TEXT    NOT NULL,
            debate_title TEXT,
            root_debate_id TEXT,
            item_type    TEXT,
            hrs_tag      TEXT,
            member_id    INTEGER,
            member_name  TEXT,
            attributed_to TEXT,
            speech_text  TEXT,
            timecode     TEXT,
            order_idx    INTEGER,
            FOREIGN KEY (debate_id) REFERENCES debates(id)
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_speeches_debate ON speeches(debate_id)',
        );
        await db.execute(
          'CREATE INDEX idx_speeches_member ON speeches(member_id)',
        );
        await db.execute(_sittingMetaDdl);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE speeches ADD COLUMN item_type TEXT');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE speeches ADD COLUMN hrs_tag TEXT');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE debates ADD COLUMN section TEXT');
        }
        if (oldVersion < 5) {
          // Existing rows keep a NULL root_debate_id; the data service
          // detects that and re-fetches the day to backfill it.
          await db.execute(
            'ALTER TABLE speeches ADD COLUMN root_debate_id TEXT',
          );
        }
        if (oldVersion < 6) {
          // Records when the day was fetched, so a sitting cached while
          // Hansard was still publishing it can be refreshed later.
          await db.execute(_sittingMetaDdl);
        }
      },
    );
  }

  static const String _sittingMetaDdl = '''
    CREATE TABLE IF NOT EXISTS meta (
      key   TEXT PRIMARY KEY,
      value TEXT
    )
  ''';
}
