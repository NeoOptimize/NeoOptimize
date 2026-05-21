import React, { useState, useEffect } from 'react';
import { TopBar } from '../App';
import { api } from '../lib/api';
import { toast } from 'react-hot-toast';
import { Users, UserPlus, RefreshCw, Edit2, Trash2, Key, Shield, Eye } from 'lucide-react';

function UserModal({ user, onClose, onSave }) {
  const [role, setRole]         = useState(user?.role || 'operator');
  const [active, setActive]     = useState(user?.is_active ?? true);
  const [saving, setSaving]     = useState(false);
  const isNew = !user;

  const [form, setForm] = useState({ email: '', password: '', role: 'operator' });

  async function handleSave() {
    setSaving(true);
    try {
      if (isNew) {
        await api.createUser({ email: form.email, password: form.password, role: form.role });
        toast.success('User created');
      } else {
        await api.updateUser(user.id, { role, is_active: active });
        toast.success('User updated');
      }
      onSave();
      onClose();
    } catch (e) { toast.error(e.message); }
    finally { setSaving(false); }
  }

  return (
    <div className="modal-overlay" onClick={e => e.target === e.currentTarget && onClose()}>
      <div className="modal">
        <div className="modal-header">
          <div className="modal-title">{isNew ? 'Create User' : `Edit: ${user.email}`}</div>
          <button className="btn btn-ghost btn-icon" onClick={onClose}>✕</button>
        </div>
        <div className="modal-body" style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
          {isNew ? (
            <>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Email</label>
                <input type="email" value={form.email} onChange={e => setForm(f => ({ ...f, email: e.target.value }))} placeholder="user@example.com" />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Password (min 10 chars)</label>
                <input type="password" value={form.password} onChange={e => setForm(f => ({ ...f, password: e.target.value }))} placeholder="Strong password..." />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Role</label>
                <select value={form.role} onChange={e => setForm(f => ({ ...f, role: e.target.value }))}>
                  <option value="admin">Admin — Full access</option>
                  <option value="operator">Operator — Send commands, view agents</option>
                  <option value="viewer">Viewer — Read only</option>
                </select>
              </div>
            </>
          ) : (
            <>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Role</label>
                <select value={role} onChange={e => setRole(e.target.value)}>
                  <option value="admin">Admin</option>
                  <option value="operator">Operator</option>
                  <option value="viewer">Viewer</option>
                </select>
              </div>
              <label style={{ display: 'flex', alignItems: 'center', gap: 10, cursor: 'pointer' }}>
                <div
                  onClick={() => setActive(v => !v)}
                  style={{
                    width: 40, height: 22, borderRadius: 11,
                    background: active ? 'var(--success)' : 'var(--bg-elevated)',
                    border: '1px solid var(--border)', position: 'relative', cursor: 'pointer'
                  }}>
                  <div style={{
                    width: 16, height: 16, borderRadius: 8, background: 'white',
                    position: 'absolute', top: 2, left: active ? 20 : 2, transition: 'var(--transition)'
                  }} />
                </div>
                <span style={{ fontSize: '0.85rem' }}>Account Active</span>
              </label>
            </>
          )}
        </div>
        <div className="modal-footer">
          <button className="btn btn-secondary" onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" onClick={handleSave} disabled={saving}>
            {saving ? 'Saving...' : isNew ? 'Create User' : 'Save Changes'}
          </button>
        </div>
      </div>
    </div>
  );
}

export default function UsersPage() {
  const [users, setUsers]       = useState([]);
  const [loading, setLoading]   = useState(true);
  const [modal, setModal]       = useState(null); // null | 'new' | user

  async function load() {
    setLoading(true);
    try {
      const res = await api.getUsers();
      setUsers(res.users || []);
    } finally { setLoading(false); }
  }

  useEffect(() => { load(); }, []);

  async function handleDelete(user) {
    if (!confirm(`Delete user "${user.email}"?`)) return;
    try {
      await api.deleteUser(user.id);
      toast.success('User deleted');
      load();
    } catch (e) { toast.error(e.message); }
  }

  const ROLE_ICON = { admin: Shield, operator: Key, viewer: Eye };

  return (
    <>
      <TopBar
        title="User Management"
        subtitle="Manage admin access and permissions"
        actions={
          <button className="btn btn-primary btn-sm" onClick={() => setModal('new')}>
            <UserPlus size={13} /> Add User
          </button>
        }
      />
      <div className="page-content animate-fade-in">
        <div className="alert alert-warning" style={{ marginBottom: '1.5rem' }}>
          <Shield size={16} />
          <span>Only Admin accounts can manage users. Viewer accounts have read-only access. Operator accounts can issue commands.</span>
        </div>

        <div className="glass-panel">
          {loading ? (
            <div className="loading-overlay"><div className="spinner" /></div>
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Email</th>
                    <th>Role</th>
                    <th>Status</th>
                    <th>Last Login</th>
                    <th>Created</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {users.map(user => {
                    const RoleIcon = ROLE_ICON[user.role] || Key;
                    return (
                      <tr key={user.id}>
                        <td>
                          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                            <div className="user-avatar" style={{ width: 32, height: 32, fontSize: '0.8rem' }}>
                              {user.email[0].toUpperCase()}
                            </div>
                            <div style={{ fontWeight: 600 }}>{user.email}</div>
                          </div>
                        </td>
                        <td>
                          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                            <RoleIcon size={13} />
                            <span className={`badge badge-${user.role}`}>{user.role}</span>
                          </div>
                        </td>
                        <td>
                          <span className={`badge ${user.is_active ? 'badge-online' : 'badge-offline'}`}>
                            {user.is_active ? 'Active' : 'Disabled'}
                          </span>
                        </td>
                        <td style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                          {user.last_login ? new Date(user.last_login).toLocaleString() : 'Never'}
                        </td>
                        <td style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                          {user.created_at ? new Date(user.created_at).toLocaleDateString() : '—'}
                        </td>
                        <td>
                          <div style={{ display: 'flex', gap: 6 }}>
                            <button className="btn btn-secondary btn-sm" onClick={() => setModal(user)}>
                              <Edit2 size={12} />
                            </button>
                            <button className="btn btn-danger btn-sm" onClick={() => handleDelete(user)}>
                              <Trash2 size={12} />
                            </button>
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>

      {modal && (
        <UserModal
          user={modal === 'new' ? null : modal}
          onClose={() => setModal(null)}
          onSave={load}
        />
      )}
    </>
  );
}
