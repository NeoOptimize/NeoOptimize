import React, { useCallback, useContext, useEffect, useState } from 'react';
import { Routes, Route, Navigate, NavLink, useLocation, useNavigate } from 'react-router-dom';
import { Toaster, toast } from 'react-hot-toast';
import {
  Monitor, Activity, Terminal, Shield, Users, Settings,
  BarChart2, LogOut, Cpu, Brain, AlertTriangle
} from 'lucide-react';
import { api } from './lib/api';

// Pages
import Dashboard       from './pages/Dashboard';
import Agents          from './pages/Agents';
import Commands        from './pages/Commands';
import AuditLog        from './pages/AuditLog';
import UsersPage       from './pages/UsersPage';
import SettingsPage    from './pages/SettingsPage';
import Optimizer       from './pages/Optimizer';
import SecurityAlerts  from './pages/SecurityAlerts';
import AIAnalysis      from './pages/AIAnalysis';
import Login           from './pages/Login';

export const AuthCtx = React.createContext({
  status: 'ready',
  user: null,
  error: null,
  bootstrap: () => {},
  clearSession: () => {},
  setSessionFromLogin: () => {},
});

function useAuthSession() {
  const initialToken = typeof window !== 'undefined' ? localStorage.getItem('neo_token') : null;
  const [session, setSession] = useState({
    status: initialToken ? 'checking' : 'ready',
    user: null,
    error: null,
  });

  const bootstrap = useCallback(async () => {
    const token = localStorage.getItem('neo_token');
    if (!token) {
      setSession({ status: 'ready', user: null, error: null });
      return;
    }

    setSession(prev => ({ ...prev, status: 'checking', error: null }));
    try {
      const me = await api.getMe({ redirectOnUnauthorized: false });
      setSession({ status: 'ready', user: me, error: null });
    } catch (err) {
      const message = err?.message || 'Session validation failed';
      const authExpired = /unauthori|session expired|invalid token|malformed token|token expired/i.test(message);

      if (authExpired) {
        localStorage.removeItem('neo_token');
        setSession({
          status: 'ready',
          user: null,
          error: 'Your previous session expired. Please sign in again.',
        });
      } else {
        setSession({
          status: 'offline',
          user: null,
          error: 'NeoOptimize service unavailable. Please retry once the service is reachable.',
        });
      }
    }
  }, []);

  useEffect(() => {
    bootstrap();
  }, [bootstrap]);

  const clearSession = useCallback(() => {
    localStorage.removeItem('neo_token');
    setSession({ status: 'ready', user: null, error: null });
  }, []);

  const setSessionFromLogin = useCallback((user) => {
    setSession({ status: 'ready', user, error: null });
  }, []);

  return {
    ...session,
    bootstrap,
    clearSession,
    setSessionFromLogin,
  };
}

function BootScreen({ title = 'NEOOPTIMIZE', subtitle = 'Initializing Secure Channel...', detail, error, actionLabel = 'Retry', onAction }) {
  return (
    <div className="login-page">
      <div className="login-bg" />
      <div className="login-card" style={{ maxWidth: 560 }}>
        <div className="login-brand" style={{ marginBottom: '1.2rem' }}>
          <div className="login-logo" aria-hidden="true">
            <img src="/logo.png" alt="" />
          </div>
          <h1>
            Neo<span className="text-gradient">Optimize</span>
          </h1>
          <p>{title}</p>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <div className="spinner" style={{ width: 18, height: 18 }} />
            <div>
              <div style={{ fontWeight: 700 }}>{subtitle}</div>
              {detail && (
                <div style={{ color: 'var(--text-muted)', fontSize: '0.82rem', marginTop: 4 }}>
                  {detail}
                </div>
              )}
            </div>
          </div>

          {error && (
            <div className="alert alert-danger" style={{ margin: 0 }}>
              {error}
            </div>
          )}

          {onAction && (
            <button className="btn btn-secondary" type="button" onClick={onAction} style={{ alignSelf: 'flex-start' }}>
              {actionLabel}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

function Protected({ children }) {
  const { status, user, error, bootstrap } = useContext(AuthCtx);
  const location = useLocation();

  if (status === 'checking') {
    return (
      <BootScreen
        subtitle="Verifying secure session..."
        detail="Checking saved credentials against the secure service."
      />
    );
  }

  if (status === 'offline') {
    return (
      <BootScreen
        subtitle="Service unavailable"
        detail={error || 'The secure service could not be reached.'}
        error="Login will resume automatically once the service is reachable."
        actionLabel="Retry session"
        onAction={bootstrap}
      />
    );
  }

  if (!user) return <Navigate to="/login" replace state={{ from: location }} />;
  return children;
}

function PublicOnly({ children }) {
  const { status, user, error, bootstrap } = useContext(AuthCtx);

  if (status === 'checking') {
    return (
      <BootScreen
        subtitle="Verifying secure session..."
        detail="Checking saved credentials against the secure service."
      />
    );
  }

  if (status === 'offline') {
    return (
      <BootScreen
        subtitle="Service unavailable"
        detail={error || 'The secure service could not be reached.'}
        error="Login will resume automatically once the service is reachable."
        actionLabel="Retry session"
        onAction={bootstrap}
      />
    );
  }

  if (user) return <Navigate to="/" replace />;
  return children;
}

function Sidebar({ onlineCount, pendingCount, alertCount }) {
  const navigate = useNavigate();
  const { user, clearSession } = useContext(AuthCtx);

  function handleLogout() {
    clearSession();
    navigate('/login');
    toast.success('Logged out');
  }

  const navItems = [
    { to: '/',          icon: BarChart2,      label: 'Overview',       section: 'MONITOR'  },
    { to: '/agents',    icon: Monitor,        label: 'Systems',        badge: onlineCount  },
    { to: '/alerts',    icon: AlertTriangle,  label: 'Security Alerts',badge: alertCount, badgeDanger: alertCount > 0, section: 'SECURITY' },
    { to: '/ai',        icon: Brain,          label: 'AI Analysis'                         },
    { to: '/optimizer', icon: Cpu,            label: 'Optimizer',      section: 'OPTIMIZE' },
    { to: '/commands',  icon: Terminal,       label: 'Task Queue',     badge: pendingCount, badgeDanger: pendingCount > 0 },
    { to: '/audit',     icon: Shield,         label: 'Audit Log',      section: 'MANAGE'   },
    { to: '/users',     icon: Users,          label: 'Users',          adminOnly: true     },
    { to: '/settings',  icon: Settings,       label: 'Settings'                            },
  ];

  return (
    <nav className="sidebar">
      <div className="sidebar-logo">
        <div className="sidebar-logo-icon">
          <div className="logo-inner">
            <img src="/logo.png" alt="" />
          </div>
          <div className="logo-glow" />
        </div>
        <div className="sidebar-logo-text">
          <div className="sidebar-logo-title">NEO<span style={{ color: 'var(--primary)' }}>OPTIMIZE</span></div>
          <div className="sidebar-logo-sub">SYSTEM OPTIMIZER PRO</div>
        </div>
      </div>

      <div className="sidebar-nav">
        {navItems.map((item) => {
          if (item.adminOnly && user?.role !== 'admin') return null;
          return (
            <React.Fragment key={item.to}>
              {item.section && <div className="nav-section">{item.section}</div>}
              <NavLink
                to={item.to}
                end={item.to === '/'}
                className={({ isActive }) => `nav-item${isActive ? ' active' : ''}`}
              >
                <item.icon size={17} />
                {item.label}
                {item.badge > 0 && (
                  <span className={`nav-badge${item.badgeDanger ? ' danger' : ''}`}>{item.badge}</span>
                )}
              </NavLink>
            </React.Fragment>
          );
        })}
      </div>

      <div className="sidebar-footer">
        <div className="user-card">
          <div className="user-avatar">{user?.email?.[0]?.toUpperCase() || 'U'}</div>
          <div className="user-info">
            <div className="user-email">{user?.email}</div>
            <div className="user-role">{user?.role}</div>
          </div>
          <button className="btn btn-ghost btn-icon" onClick={handleLogout} title="Logout">
            <LogOut size={15} />
          </button>
        </div>
      </div>
    </nav>
  );
}

export function TopBar({ title, subtitle, actions }) {
  return (
    <div className="topbar">
      <div style={{ flex: 1 }}>
        <div className="topbar-title">{title}</div>
        {subtitle && <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginTop: 2 }}>{subtitle}</div>}
      </div>
      {actions}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <div className="status-dot" title="Service Online" />
        <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>Live</span>
      </div>
    </div>
  );
}

function AppShell() {
  const [onlineCount, setOnlineCount]   = useState(0);
  const [pendingCount, setPendingCount]  = useState(0);
  const [alertCount, setAlertCount]     = useState(0);

  useEffect(() => {
    async function fetchCounts() {
      try {
        const res = await api.getStats();
        const on  = res.agents?.find(a => a.status === 'online')?.count || 0;
        setOnlineCount(parseInt(on));
        const pending = res.commands?.find(c => c.status === 'pending')?.count || 0;
        setPendingCount(parseInt(pending));
      } catch {}
      // Live alert count
      try {
        const alerts = await api.getAlerts({ resolved: false, limit: 1 });
        setAlertCount(alerts.total || alerts.alerts?.length || 0);
      } catch {}
    }
    fetchCounts();
    const t = setInterval(fetchCounts, 30000);
    return () => clearInterval(t);
  }, []);

  return (
    <div className="app-shell">
      <Sidebar onlineCount={onlineCount} pendingCount={pendingCount} alertCount={alertCount} />
      <main className="main-content">
        <Routes>
          <Route path="/"         element={<Dashboard />} />
          <Route path="/agents"   element={<Agents />} />
          <Route path="/alerts"   element={<SecurityAlerts />} />
          <Route path="/ai"       element={<AIAnalysis />} />
          <Route path="/optimizer" element={<Optimizer />} />
          <Route path="/commands" element={<Commands />} />
          <Route path="/audit"    element={<AuditLog />} />
          <Route path="/users"    element={<UsersPage />} />
          <Route path="/settings" element={<SettingsPage />} />
          <Route path="/about"    element={<Navigate to="/" replace />} />
        </Routes>
      </main>
    </div>
  );
}

export default function App() {
  const session = useAuthSession();

  return (
    <AuthCtx.Provider value={session}>
      <Toaster
        position="top-right"
        toastOptions={{
          style: {
            background: 'var(--bg-surface)',
            color: 'var(--text-primary)',
            border: '1px solid var(--border-active)',
            borderRadius: '10px',
            fontSize: '0.85rem',
          },
          success: { iconTheme: { primary: '#00e57a', secondary: '#000' } },
          error:   { iconTheme: { primary: '#ff3d71', secondary: '#000' } },
        }}
      />
      <Routes>
        <Route path="/login" element={<PublicOnly><Login /></PublicOnly>} />
        <Route path="/*" element={
          <Protected><AppShell /></Protected>
        } />
      </Routes>
    </AuthCtx.Provider>
  );
}
