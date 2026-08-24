import { json } from '@sveltejs/kit';
import db from '$lib/server/db';

interface ServiceRow {
	id: string;
	name: string;
}

interface UptimeRow {
	total: number;
	up: number;
}

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

export function GET() {
	const services = db.prepare('SELECT id, name FROM services').all() as ServiceRow[];
	const now = Date.now();

	const result = services.map((svc) => {
		const current = db
			.prepare(
				`SELECT healthy, checked_at, latency_ms FROM checks
				 WHERE service_id = ? ORDER BY checked_at DESC LIMIT 1`
			)
			.get(svc.id);

		const history = db
			.prepare(
				`SELECT healthy, checked_at FROM checks
				 WHERE service_id = ? AND checked_at >= ?
				 ORDER BY checked_at DESC LIMIT 60`
			)
			.all(svc.id, now - HOUR_MS);

		const uptime = db
			.prepare(
				`SELECT COUNT(*) AS total, COALESCE(SUM(healthy), 0) AS up
				 FROM checks WHERE service_id = ? AND checked_at >= ?`
			)
			.get(svc.id, now - DAY_MS) as UptimeRow;

		const uptimePercent =
			uptime.total > 0 ? Math.round((uptime.up / uptime.total) * 100) : null;

		return { ...svc, current, history: history.reverse(), uptime: uptimePercent };
	});

	return json(result);
}
