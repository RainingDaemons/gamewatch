<script lang="ts">
	import { page } from '$app/state';
	import { onMount } from 'svelte';
	import type { Component } from 'svelte';
	import ExtraLayout from '../../../../extra_pages/+layout.svelte';

	const pageLoaders = import.meta.glob('/extra_pages/*/+page.svelte');

	const service = $derived(page.params.service);

	let displayName = $state<string | null>(null);
	let PageComp = $state<Component | null>(null);
	let notFound = $state(false);
	let loading = $state(true);

	onMount(async () => {
		try {
			const res = await fetch('/api/status');
			const services = res.ok
				? ((await res.json()) as { id: string; name: string; extra_pages: boolean }[])
				: [];
			const svc = services.find((s) => s.id === service);

			if (!svc?.extra_pages) {
				notFound = true;
				return;
			}

			displayName = svc.name;

			const loader = pageLoaders[`/extra_pages/${service}/+page.svelte`];
			if (loader) {
				const mod = (await loader()) as { default: Component };
				PageComp = mod.default;
			} else {
				notFound = true;
			}
		} catch {
			notFound = true;
		} finally {
			loading = false;
		}
	});
</script>

<svelte:head>
	<title>{displayName ? `${displayName} Info` : 'Info'}</title>
</svelte:head>

{#if loading}
	<div class="min-h-screen bg-neutral-950 text-neutral-100 flex items-center justify-center">
		<p class="text-sm text-neutral-500">Loading...</p>
	</div>
{:else}
	<ExtraLayout displayName={displayName ?? service ?? ''}>
		{#if notFound || !PageComp}
			<div class="rounded-xl border border-neutral-800 bg-neutral-900 p-5">
				<p class="text-sm text-neutral-400">No info page available for this service.</p>
			</div>
		{:else}
			<PageComp />
		{/if}
	</ExtraLayout>
{/if}
