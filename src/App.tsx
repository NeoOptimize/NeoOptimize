import React, { useState } from 'react';
import { ThemeProvider } from './hooks/useThemeContext';
import { TerminalHeader } from './components/TerminalHeader';
import { FileTreeNav } from './components/FileTreeNav';
import { MainContent } from './components/MainContent';
export function App() {
  const [activeSection, setActiveSection] = useState(1);
  return (
    <ThemeProvider>
      <div
        className="min-h-screen w-full relative"
        style={{
          backgroundColor: 'var(--bg-primary)'
        }}>

        {/* CRT Scanline Overlay */}
        <div className="scanlines" aria-hidden="true" />

        {/* App Shell */}
        <div className="relative z-10 flex flex-col min-h-screen">
          <TerminalHeader />
          <div className="flex flex-1 pt-14">
            <FileTreeNav
              activeSection={activeSection}
              onSectionChange={setActiveSection} />

            <MainContent activeSection={activeSection} />
          </div>
        </div>
      </div>
    </ThemeProvider>);

}