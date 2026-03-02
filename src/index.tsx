import "./index.css";
import React from "react";
import { createRoot } from 'react-dom/client';
import { App } from "./App";
import { SystemStatsProvider } from './hooks/SystemStatsContext';
import { apiUrl } from './lib/api';

function sendClientEvent(kind: string, message: string, extra: Record<string, unknown> = {}) {
	try {
		const payload = { kind, message: String(message || ''), extra };
		fetch(apiUrl('/api/diagnostics/client-event'), {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify(payload)
		}).catch((err: unknown) => {
			void err;
		});
	} catch (err) {
		void err;
	}
}

window.addEventListener('error', (event) => {
	sendClientEvent('window-error', String(event.message || 'unknown'), {
		file: event.filename || '',
		line: event.lineno || 0,
		column: event.colno || 0
	});
});
window.addEventListener('unhandledrejection', (event) => {
	const reason = (event as PromiseRejectionEvent).reason;
	sendClientEvent('unhandled-rejection', String(reason?.message || reason || 'unknown'));
});

const container = document.getElementById('root');
if (container) {
	const root = createRoot(container);
	root.render(
		<React.StrictMode>
			<SystemStatsProvider>
				<App />
			</SystemStatsProvider>
		</React.StrictMode>
	);
}
