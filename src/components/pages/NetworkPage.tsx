import { useEffect, useMemo, useState } from 'react';
import { motion } from 'framer-motion';
import { Activity, ArrowDown, ArrowUp, Globe } from 'lucide-react';
import { apiFetch } from '../../lib/api';

type NetStat = {
  interfaces: Array<{ name: string; addrs: Array<{ address: string; family: string; mac: string; internal?: boolean }> }>;
  throughput: { rxKBs: number; txKBs: number };
  latencyMs: number | null;
  packetsPerSec: number;
  dnsResolvers: string[];
};

type Connection = { local: string; remote: string; state: string; pid: number; process: string };

export function NetworkPage() {
  const [stats, setStats] = useState<NetStat>({ interfaces: [], throughput: { rxKBs: 0, txKBs: 0 }, latencyMs: null, packetsPerSec: 0, dnsResolvers: [] });
  const [connections, setConnections] = useState<Connection[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [lastUpdated, setLastUpdated] = useState('');

  useEffect(() => {
    let mounted = true;
    const refresh = async () => {
      try {
        const [sRes, cRes] = await Promise.all([apiFetch('/api/network/stats'), apiFetch('/api/network/connections')]);
        const s = await sRes.json();
        const c = await cRes.json();
        if (!mounted) return;
        if (s?.ok) setStats({
          interfaces: s.interfaces || [],
          throughput: s.throughput || { rxKBs: 0, txKBs: 0 },
          latencyMs: s.latencyMs ?? null,
          packetsPerSec: Number(s.packetsPerSec || 0),
          dnsResolvers: s.dnsResolvers || []
        });
        if (c?.ok) setConnections(c.connections || []);
        setLastUpdated(new Date().toLocaleTimeString());
        setError('');
      } catch (err: any) {
        setError(String(err?.message || err));
      } finally {
        setLoading(false);
      }
    };
    refresh();
    const iv = setInterval(refresh, 2000);
    return () => { mounted = false; clearInterval(iv); };
  }, []);

  const cards = useMemo(() => [
    { label: 'Download', value: `${(stats.throughput.rxKBs / 1024).toFixed(2)} MB/s`, icon: <ArrowDown size={14} />, color: 'var(--ansi-green)' },
    { label: 'Upload', value: `${(stats.throughput.txKBs / 1024).toFixed(2)} MB/s`, icon: <ArrowUp size={14} />, color: 'var(--ansi-blue)' },
    { label: 'Latency', value: `${stats.latencyMs == null ? '-' : stats.latencyMs} ms`, icon: <Activity size={14} />, color: 'var(--ansi-yellow)' },
    { label: 'Packets/s', value: String(stats.packetsPerSec), icon: <Globe size={14} />, color: 'var(--ansi-cyan)' }
  ], [stats]);

  return (
    <div className="space-y-4">
      <div className="text-xs flex items-center gap-2" style={{ color: 'var(--text-muted)' }}>
        <span style={{ color: 'var(--ansi-green)', fontWeight: 700 }}>$</span>
        <span>netstat -ano && ipconfig /all</span>
        <span style={{ color: 'var(--ansi-cyan)' }}>{lastUpdated ? `updated ${lastUpdated}` : ''}</span>
      </div>

      {(loading || error) && (
        <div className="px-3 py-2 text-xs border" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-tertiary)', color: error ? 'var(--ansi-red)' : 'var(--text-primary)' }}>
          {loading ? 'Loading network data...' : error}
        </div>
      )}

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {cards.map((card, i) => (
          <motion.div key={card.label} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: i * 0.05 }} className="p-3 border" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
            <div className="flex items-center gap-2 mb-2 text-xs" style={{ color: 'var(--text-muted)' }}>{card.icon} {card.label}</div>
            <div className="text-xl font-bold font-mono" style={{ color: card.color }}>{card.value}</div>
          </motion.div>
        ))}
      </div>

      <div className="border" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="px-3 py-2 text-[10px] font-bold border-b flex justify-between" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-tertiary)', color: 'var(--text-muted)' }}>
          <span>ACTIVE CONNECTIONS</span>
          <span>{connections.length} total</span>
        </div>
        <div className="grid grid-cols-12 gap-2 px-3 py-2 text-[10px] font-bold border-b" style={{ borderColor: 'var(--border-color)', color: 'var(--text-muted)' }}>
          <div className="col-span-3">LOCAL ADDRESS</div>
          <div className="col-span-3">REMOTE ADDRESS</div>
          <div className="col-span-2">STATE</div>
          <div className="col-span-2">PID</div>
          <div className="col-span-2">PROCESS</div>
        </div>
        <div className="max-h-72 overflow-y-auto">
          {connections.map((c, i) => (
            <div key={`${c.local}-${c.remote}-${c.pid}-${i}`} className="grid grid-cols-12 gap-2 px-3 py-1.5 text-xs font-mono items-center" style={{ backgroundColor: i % 2 === 0 ? 'var(--bg-primary)' : 'transparent' }}>
              <div className="col-span-3 truncate" style={{ color: 'var(--text-primary)' }}>{c.local}</div>
              <div className="col-span-3 truncate" style={{ color: 'var(--text-muted)' }}>{c.remote}</div>
              <div className="col-span-2" style={{ color: c.state === 'LISTEN' ? 'var(--ansi-green)' : c.state === 'ESTABLISHED' ? 'var(--ansi-blue)' : 'var(--text-muted)' }}>{c.state}</div>
              <div className="col-span-2" style={{ color: 'var(--ansi-yellow)' }}>{c.pid}</div>
              <div className="col-span-2 truncate" style={{ color: 'var(--text-primary)' }}>{c.process}</div>
            </div>
          ))}
          {connections.length === 0 && <div className="px-3 py-2 text-xs" style={{ color: 'var(--text-muted)' }}>No active connections</div>}
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div className="border p-3 space-y-3" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
          <div className="text-xs font-bold border-b pb-2" style={{ borderColor: 'var(--border-color)', color: 'var(--text-muted)' }}>NETWORK INTERFACES</div>
          {stats.interfaces.length === 0 ? <div style={{ color: 'var(--text-muted)' }} className="text-xs">No interfaces found</div> : stats.interfaces.map((iface) => (
            <div key={iface.name} className="text-xs space-y-1">
              <div className="flex justify-between">
                <span style={{ color: 'var(--ansi-green)', fontWeight: 'bold' }}>{iface.name}</span>
                <span style={{ color: 'var(--text-muted)' }}>{iface.addrs.find((a) => !a.internal)?.mac || iface.addrs[0]?.mac || '-'}</span>
              </div>
              <div className="pl-2 border-l-2" style={{ borderColor: 'var(--border-color)' }}>
                <div style={{ color: 'var(--text-primary)' }}>{iface.addrs.map((a) => a.address).filter(Boolean).join(', ') || '-'}</div>
                <div style={{ color: 'var(--text-muted)' }}>RX: {stats.throughput.rxKBs} KB/s | TX: {stats.throughput.txKBs} KB/s</div>
              </div>
            </div>
          ))}
        </div>

        <div className="border p-3 space-y-3" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
          <div className="text-xs font-bold border-b pb-2 flex justify-between" style={{ borderColor: 'var(--border-color)', color: 'var(--text-muted)' }}>
            <span>DNS & ROUTING</span>
            <span className="px-1.5 py-0.5 text-[9px] bg-[rgba(0,255,65,0.1)] text-[var(--ansi-green)]">LIVE</span>
          </div>
          <div className="space-y-2 text-xs">
            <div className="flex justify-between"><span style={{ color: 'var(--text-muted)' }}>Resolvers</span><span style={{ color: 'var(--text-primary)' }}>{stats.dnsResolvers.length}</span></div>
            <div className="pt-2 border-t" style={{ borderColor: 'var(--border-color)' }}>
              <div className="text-[10px] mb-1" style={{ color: 'var(--ansi-blue)' }}>DNS RESOLVERS</div>
              <div style={{ color: 'var(--text-primary)' }}>{stats.dnsResolvers.length > 0 ? stats.dnsResolvers.join(', ') : '-'}</div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
