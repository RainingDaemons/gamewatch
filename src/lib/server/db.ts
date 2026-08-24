import Database from 'better-sqlite3';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const DB_PATH = process.env.STATUS_DB_PATH ?? '/opt/status-page/data/status.db';

mkdirSync(dirname(DB_PATH), { recursive: true });

const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');

db.exec(`
	CREATE TABLE IF NOT EXISTS services (
		id TEXT PRIMARY KEY,
		name TEXT NOT NULL,
		target TEXT NOT NULL
	);

	CREATE TABLE IF NOT EXISTS checks (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		service_id TEXT NOT NULL,
		checked_at INTEGER NOT NULL,
		healthy INTEGER NOT NULL,
		latency_ms INTEGER,
		FOREIGN KEY (service_id) REFERENCES services(id)
	);

	CREATE INDEX IF NOT EXISTS idx_checks_service_time
		ON checks (service_id, checked_at);
`);

const NECESSE_TARGET =
	process.env.NECESSE_HEALTH_URL ?? 'http://192.168.100.228:9101/health';
const PLAYIT_TARGET =
	process.env.PLAYIT_HEALTH_URL ?? 'http://192.168.100.229:9101/health';

const upsert = db.prepare(`
	INSERT INTO services (id, name, target) VALUES (?, ?, ?)
	ON CONFLICT(id) DO UPDATE SET name = excluded.name, target = excluded.target
`);

upsert.run('necesse', 'Necesse Service', NECESSE_TARGET);
upsert.run('playit', 'Playit.gg Tunnel', PLAYIT_TARGET);

export default db;
