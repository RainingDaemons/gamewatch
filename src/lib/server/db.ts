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
		target TEXT NOT NULL,
		extra_pages INTEGER NOT NULL DEFAULT 0
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

const columns = db.prepare(`PRAGMA table_info(services)`).all() as { name: string }[];
if (!columns.some((c) => c.name === 'extra_pages')) {
	db.exec(`ALTER TABLE services ADD COLUMN extra_pages INTEGER NOT NULL DEFAULT 0`);
}

const CONFIG_PATH = process.env.STATUS_CONFIG_PATH ?? resolve(process.cwd(), 'config.toml');
const config = parse(readFileSync(CONFIG_PATH, 'utf-8')) as {
	services: {
		name: string;
		display_name: string;
		health_url: string;
		extra_pages?: boolean | string;
	}[];
};

const TRUTHY = new Set(['yes', 'true', '1', 'on']);

function hasExtraPages(value: boolean | string | undefined): boolean {
	if (typeof value === 'boolean') return value;
	if (typeof value === 'string') return TRUTHY.has(value.trim().toLowerCase());
	return false;
}

const upsert = db.prepare(`
	INSERT INTO services (id, name, target, extra_pages) VALUES (?, ?, ?, ?)
	ON CONFLICT(id) DO UPDATE SET
		name = excluded.name,
		target = excluded.target,
		extra_pages = excluded.extra_pages
`);

for (const service of config.services) {
	upsert.run(service.name, service.display_name, service.health_url, hasExtraPages(service.extra_pages) ? 1 : 0);
}

export default db;
