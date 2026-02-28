import "./index.css";
import React from "react";
import { createRoot } from 'react-dom/client';
import { App } from "./App";
import { SystemStatsProvider } from './hooks/SystemStatsContext';

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