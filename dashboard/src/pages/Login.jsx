import React, { useContext, useEffect, useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { toast } from 'react-hot-toast';
import { api } from '../lib/api';
import { Shield, Eye, EyeOff, LogIn, RefreshCw } from 'lucide-react';
import { AuthCtx } from '../App';

export default function Login() {
  const [email, setEmail]       = useState('');
  const [password, setPassword] = useState('');
  const [showPw, setShowPw]     = useState(false);
  const [loading, setLoading]   = useState(false);
  const [health, setHealth]     = useState({ status: 'checking', message: 'Checking service...' });
  const { error: sessionError, setSessionFromLogin } = useContext(AuthCtx);
  const navigate = useNavigate();
  const location = useLocation();
  const from = location.state?.from?.pathname || '/';

  useEffect(() => {
    let alive = true;

    async function checkHealth() {
      try {
        const r = await api.getHealth();
        if (!alive) return;
        setHealth({
          status: r.status === 'ok' ? 'online' : 'degraded',
          message: r.status === 'ok' ? 'Secure service online' : 'Service degraded',
          detail: `Postgres ${r.postgres ? 'up' : 'down'} · Redis ${r.redis ? 'up' : 'down'}`,
        });
      } catch (e) {
        if (!alive) return;
        setHealth({
          status: 'offline',
          message: e.message || 'Service unavailable',
          detail: 'Login will work once the secure service is reachable.',
        });
      }
    }

    checkHealth();
    const timer = setInterval(checkHealth, 15000);
    return () => {
      alive = false;
      clearInterval(timer);
    };
  }, []);

  function formatLoginError(message) {
    const lower = String(message || '').toLowerCase();
    if (lower.includes('too many failed attempts')) return message;
    if (lower.includes('invalid credentials')) return 'Email or password is incorrect';
    if (lower.includes('session expired')) return 'Session expired. Please sign in again.';
    if (lower.includes('unable to reach') || lower.includes('failed to fetch') || lower.includes('network')) {
      return 'Unable to reach NeoOptimize service';
    }
    return message || 'Unable to sign in';
  }

  async function handleSubmit(e) {
    e.preventDefault();
    if (!email || !password) return toast.error('Please fill all fields');
    setLoading(true);
    try {
      const res = await api.login(email, password);
      setSessionFromLogin({
        email: res.email,
        role: res.role,
        tenantName: res.tenantName,
      });
      toast.success(`Welcome back, ${res.email}`);
      navigate(from, { replace: true });
    } catch (e) {
      toast.error(formatLoginError(e.message));
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="login-page">
      <div className="login-bg" />
      <div className="login-card">
        <div className="login-brand">
          <div className="login-logo" aria-hidden="true">
            <img src="/logo.png" alt="" />
          </div>
          <h1>
            Neo<span className="text-gradient">Optimize</span>
          </h1>
          <p>System Optimization Console — Secure Access</p>
        </div>

        <form onSubmit={handleSubmit} className="login-form">
          {sessionError && (
            <div className="alert alert-warning" style={{ marginBottom: 12 }}>
              {sessionError}
            </div>
          )}

          <div className="form-group">
            <label htmlFor="login-email">Email Address</label>
            <input
              id="login-email"
              type="email"
              value={email}
              onChange={e => setEmail(e.target.value)}
              placeholder="admin@neooptimize.local"
              autoComplete="email"
              required
            />
          </div>

          <div className="form-group">
            <label htmlFor="login-password">Password</label>
            <div className="password-field">
              <input
                id="login-password"
                type={showPw ? 'text' : 'password'}
                value={password}
                onChange={e => setPassword(e.target.value)}
                placeholder="Your password"
                autoComplete="current-password"
                required
              />
              <button
                type="button"
                className="password-toggle"
                aria-label={showPw ? 'Hide password' : 'Show password'}
                onClick={() => setShowPw(v => !v)}
              >
                {showPw ? <EyeOff size={16} /> : <Eye size={16} />}
              </button>
            </div>
          </div>

          <button
            id="login-submit"
            type="submit"
            className="btn btn-primary login-submit"
            disabled={loading}
          >
            {loading
              ? <><div className="spinner" style={{ width: 16, height: 16 }} /> Signing in...</>
              : <><LogIn size={16} /> Sign In</>
            }
          </button>
        </form>

        <div className="security-note" style={{ display: 'flex', flexDirection: 'column', gap: 8, alignItems: 'flex-start' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <Shield size={14} color={health.status === 'offline' ? 'var(--danger)' : health.status === 'degraded' ? 'var(--warning)' : 'var(--success)'} />
            <span>
              {health.message}
              {health.detail ? ` · ${health.detail}` : ''}
            </span>
          </div>
          <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>
            Recovery stays on the secure bootstrap path if the local admin password is lost.
          </div>
          <button
            type="button"
            className="btn btn-ghost btn-sm"
            onClick={async () => {
              setHealth({ status: 'checking', message: 'Checking service...' });
              try {
                const r = await api.getHealth();
                setHealth({
                  status: r.status === 'ok' ? 'online' : 'degraded',
                  message: r.status === 'ok' ? 'Secure service online' : 'Service degraded',
                  detail: `Postgres ${r.postgres ? 'up' : 'down'} · Redis ${r.redis ? 'up' : 'down'}`,
                });
              } catch (e) {
                setHealth({
                  status: 'offline',
                  message: e.message || 'Service unavailable',
                  detail: 'Login will work once the secure service is reachable.',
                });
              }
            }}
            style={{ paddingInline: 0, display: 'inline-flex', alignItems: 'center', gap: 6 }}
          >
            <RefreshCw size={13} />
            Refresh status
          </button>
        </div>
      </div>
    </div>
  );
}
