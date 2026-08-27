<script lang="ts">
	import { onMount } from 'svelte';

	interface HistoryPoint {
		healthy: number;
		checked_at: number;
	}

	interface Current {
		healthy: number;
		checked_at: number;
		latency_ms: number | null;
	}

	interface Service {
		id: string;
		name: string;
		extra_pages: boolean;
		current: Current | null;
		history: HistoryPoint[];
		uptime: number | null;
	}

	let services: Service[] = $state([]);
	let now: number = $state(Date.now());
	let loading: boolean = $state(true);

	async function load() {
		try {
			const res = await fetch('/api/status');
			if (res.ok) {
				services = await res.json();
				now = Date.now();
			}
		} catch {
			// keep last known data on transient errors
		} finally {
			loading = false;
		}
	}

	onMount(() => {
		load();
		const interval = setInterval(load, 30_000);
		return () => clearInterval(interval);
	});

	const overallUp = $derived(
		services.length > 0 && services.every((s) => s.current?.healthy === 1)
	);

	function timeAgo(ts: number | undefined) {
		if (!ts) return '—';
		const s = Math.max(0, Math.floor((now - ts) / 1000));
		if (s < 60) return `${s}s ago`;
		const m = Math.floor(s / 60);
		if (m < 60) return `${m}m ago`;
		const h = Math.floor(m / 60);
		if (h < 24) return `${h}h ago`;
		return `${Math.floor(h / 24)}d ago`;
	}
</script>

<svelte:head>
	<title>Gamewatch</title>
	<meta name="description" content="Live status for Necesse Server" />
</svelte:head>

<div class="min-h-screen bg-neutral-950 text-neutral-100 flex flex-col">
	<header class="w-full mb-10 border-b border-gray-600">
		<div class="mx-auto max-w-3xl px-6 py-4">
			<div class="flex items-center justify-between">
				<div>
					<h1 class="text-2xl font-semibold tracking-tight">Gamewatch</h1>
				</div>
				<div class="flex items-center gap-2 text-sm">
					<span
						class={`inline-block h-3 w-3 rounded-full ${overallUp ? 'bg-emerald-500' : 'bg-red-500'}`}
					></span>
					<span class="font-medium">
						{overallUp ? 'All Systems Operational' : 'Service Disruption'}
					</span>
				</div>
			</div>
		</div>
	</header>

	<main class="flex-1 mx-auto max-w-3xl w-full px-6 pb-10">
		{#if loading}
			<p class="text-sm text-neutral-500">Loading...</p>
		{:else}
			<div class="space-y-4">
				{#each services as svc}
					{@const up = svc.current?.healthy === 1}
					{@const uptime = svc.uptime}
					<div class="rounded-xl border border-neutral-800 bg-neutral-900 p-5">
						<div class="flex items-center justify-between">
							<div>
								{#if svc.extra_pages}
									<a href="/info/{svc.id}" class="text-lg font-medium text-blue-400 hover:text-blue-300 hover:underline">
										{svc.name}
									</a>
								{:else}
									<h2 class="text-lg font-medium">{svc.name}</h2>
								{/if}
								<p class="text-xs text-neutral-500">
									{timeAgo(svc.current?.checked_at)}
									{#if svc.current?.latency_ms != null} · {svc.current.latency_ms}ms{/if}
								</p>
							</div>
							<div class="flex items-center gap-3">
								{#if uptime !== null}
									<span class="text-xs text-neutral-500">{uptime}% uptime (last 24h)</span>
								{/if}
								<span
									class={`rounded-full px-3 py-1 text-xs font-semibold ${
										up
											? 'bg-emerald-500/10 text-emerald-400'
											: 'bg-red-500/10 text-red-400'
									}`}
								>
									{up ? 'Operational' : 'Down'}
								</span>
							</div>
						</div>
						<div class="mt-4 flex items-end gap-[2px]">
							{#each svc.history as check}
								<div
									title={`${check.healthy ? 'Up' : 'Down'} · ${new Date(check.checked_at).toLocaleString()}`}
									class={`h-8 flex-1 rounded-sm ${check.healthy ? 'bg-emerald-500' : 'bg-red-500'}`}
								></div>
							{/each}
						</div>
					</div>
				{/each}
			</div>
		{/if}
	</main>

	<footer class="mt-10 border-t border-gray-600">
		<div class="mx-auto max-w-3xl px-6 py-6">
			<div class="flex items-center justify-between">
				<span class="text-sm text-neutral-400">Checks run every 1 minute from server to network</span>
				<span class="flex gap-1 items-center text-blue-400 hover:text-blue-300 hover:underline">
					<a href="https://rainingdaemons.com/" target="_blank" class="text-sm">RainingDaemons</a>
					<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24">
						<path d="M0 0h24v24H0z" fill="none" />
						<path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18 6L6 18M8 6h10v10" />
					</svg>
				</span>
			</div>
		</div>
	</footer>
</div>
