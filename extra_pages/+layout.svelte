<script lang="ts">
	import type { Snippet } from 'svelte';
	let { displayName, children }: { displayName: string; children: Snippet } = $props();
</script>

<div class="min-h-screen bg-neutral-950 text-neutral-100 flex flex-col">
	<header class="w-full mb-10 border-b border-gray-600">
		<div class="mx-auto max-w-3xl px-6 py-4">
			<div class="flex items-center justify-between">
				<div>
					<h1 class="text-2xl font-semibold tracking-tight">{displayName} Info</h1>
				</div>
				<a
					href="/"
					class="flex items-center gap-1 text-sm text-blue-400 hover:text-blue-300 hover:underline"
				>
					<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24">
						<path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 18l-6-6 6-6" />
					</svg>
					<span>Back to Home</span>
				</a>
			</div>
		</div>
	</header>

	<main class="flex-1 mx-auto max-w-6xl w-full px-6 pb-6">
		{@render children()}
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
