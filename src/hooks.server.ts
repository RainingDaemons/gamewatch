import cron from 'node-cron';
import db from '$lib/server/db';

type Service = { id: string; target: string };

async function checkService(id: string, url: string) {
	const start = Date.now();
	let healthy = false;
	try {
		const res = await fetch(url, { signal: AbortSignal.timeout(5000) });
		healthy = res.ok;
	} catch {
		healthy = false;
	}
	const latency = Date.now() - start;
	db.prepare(
		`INSERT INTO checks (service_id, checked_at, healthy, latency_ms) VALUES (?, ?, ?, ?)`
	).run(id, Date.now(), healthy ? 1 : 0, latency);
}

async function runChecks() {
	const services = db.prepare('SELECT id, target FROM services').all() as Service[];
	await Promise.allSettled(services.map((s) => checkService(s.id, s.target)));
}

// Run once at boot, then every minute
runChecks();

cron.schedule('* * * * *', () => {
	runChecks();
});
