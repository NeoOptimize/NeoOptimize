import { useEffect, useMemo, useState } from 'react';
import { ThemeProvider } from './hooks/useThemeContext';
import { TerminalHeader } from './components/TerminalHeader';
import { FileTreeNav } from './components/FileTreeNav';
import { MainContent } from './components/MainContent';
import { SectionId, UIMode, visibleNavItems } from './types/ui';

function readStoredMode(): UIMode {
  try {
    const raw = localStorage.getItem('neo-ui-mode');
    return raw === 'advanced' ? 'advanced' : 'simple';
  } catch {
    return 'simple';
  }
}

export function App() {
  const [uiMode, setUiMode] = useState<UIMode>(readStoredMode);
  const [activeSection, setActiveSection] = useState<SectionId>('dashboard');

  const allowedSections = useMemo(
    () => new Set(visibleNavItems(uiMode).map((item) => item.id)),
    [uiMode]
  );

  useEffect(() => {
    try {
      localStorage.setItem('neo-ui-mode', uiMode);
    } catch (err) {
      void err;
    }
    if (!allowedSections.has(activeSection)) {
      setActiveSection('dashboard');
    }
  }, [uiMode, allowedSections, activeSection]);

  return (
    <ThemeProvider>
      <div
        className="min-h-screen w-full relative"
        style={{
          backgroundColor: 'var(--bg-primary)'
        }}
      >
        <div className="scanlines" aria-hidden="true" />
        <div className="relative z-10 flex flex-col min-h-screen">
          <TerminalHeader />
          <div className="flex flex-1 pt-14">
            <FileTreeNav
              activeSection={activeSection}
              onSectionChange={setActiveSection}
              uiMode={uiMode}
              onModeChange={setUiMode}
            />
            <MainContent
              activeSection={activeSection}
              uiMode={uiMode}
              onModeChange={setUiMode}
            />
          </div>
        </div>
      </div>
    </ThemeProvider>
  );
}
