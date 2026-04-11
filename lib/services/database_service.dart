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
      version: 1,
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
      version: 1,
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
    );
  }
}
