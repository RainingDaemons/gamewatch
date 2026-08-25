import Database from 'better-sqlite3';
import { parse } from 'smol-toml';
import { mkdirSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

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

const CONFIG_PATH = process.env.STATUS_CONFIG_PATH ?? resolve(process.cwd(), 'config.toml');
const config = parse(readFileSync(CONFIG_PATH, 'utf-8')) as {
	services: { NECESSE_HEALTH_URL: string; PLAYIT_HEALTH_URL: string };
};

const NECESSE_TARGET = config.services.NECESSE_HEALTH_URL;
const PLAYIT_TARGET = config.services.PLAYIT_HEALTH_URL;

const upsert = db.prepare(`
	INSERT INTO services (id, name, target) VALUES (?, ?, ?)
	ON CONFLICT(id) DO UPDATE SET name = excluded.name, target = excluded.target
`);

upsert.run('necesse', 'Necesse Service', NECESSE_TARGET);
upsert.run('playit', 'Playit.gg Tunnel', PLAYIT_TARGET);

export default db;
