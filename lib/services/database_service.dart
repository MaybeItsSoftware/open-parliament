import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Manages the local SQLite databases used for the local-first data strategy.
///
/// Two database families are maintained:
///  - `members.db`  — cached MP profiles, refreshed every 30 days.
///  - `sitting_YYYY-MM-DD.db` — one database per sitting day; created on first
///    fetch and never modified after that (append-only cache).
class DatabaseService {
  static const String _membersDbName = 'members.db';

  /// Returns the absolute path to the members database file.
  Future<String> membersDbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, _membersDbName);
  }

  /// Returns the absolute path to the sitting database for [date] (YYYY-MM-DD).
  Future<String> sittingDbPath(String date) async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'sitting_$date.db');
  }

  // ─── Members DB ───────────────────────────────────────────────────────────

  /// Opens (and creates if necessary) the members database.
  Future<Database> openMembersDb() async {
    final path = await membersDbPath();
    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE members (
            id               INTEGER PRIMARY KEY,
            name             TEXT    NOT NULL,
            party            TEXT,
            party_abbreviation TEXT,
            thumbnail_url    TEXT
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
      },
    );
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
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE debates (
            id        TEXT PRIMARY KEY,
            title     TEXT,
            house     TEXT,
            order_idx INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE speeches (
            id           TEXT    PRIMARY KEY,
            debate_id    TEXT    NOT NULL,
            debate_title TEXT,
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
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE speeches ADD COLUMN item_type TEXT');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE speeches ADD COLUMN hrs_tag TEXT');
        }
      },
    );
  }
}
