import React, { useEffect, useRef, useState } from 'react';
import { motion } from 'framer-motion';

// Simulasi data log jika tidak ada data aktual yang masuk
const MOCK_LOGS = [
  { id: 1, type: 'INFO', message: 'System boot sequence initiated.', time: new Date().toISOString() },
  { id: 2, type: 'SUCCESS', message: 'RSA signature verified for cmd_9823.', time: new Date().toISOString() },
  { id: 3, type: 'INFO', message: 'Executing NeoOptimize profile: AGGRESSIVE.', time: new Date().toISOString() },
  { id: 4, type: 'WARN', message: 'High CPU usage detected on Node 3.', time: new Date().toISOString() },
];

export default function TerminalLog({ logs = MOCK_LOGS }) {
  const bottomRef = useRef(null);

  // Auto-scroll ke bawah setiap ada log baru
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [logs]);

  const getColorClass = (type) => {
    switch(type) {
      case 'INFO': return 'terminal-text-cyan';
      case 'WARN': return 'terminal-text-amber';
      case 'SUCCESS': return 'terminal-text-emerald';
      default: return '';
    }
  };

  return (
    <div className="terminal-window" style={{ height: '300px', display: 'flex', flexDirection: 'column' }}>
      {/* Terminal Header */}
      <div style={{ background: 'rgba(0,0,0,0.4)', padding: '8px 16px', display: 'flex', alignItems: 'center', borderBottom: '1px solid rgba(0,240,255,0.1)' }}>
        <div style={{ display: 'flex', gap: '6px' }}>
          <div style={{ width: '10px', height: '10px', borderRadius: '50%', background: 'var(--danger)' }} />
          <div style={{ width: '10px', height: '10px', borderRadius: '50%', background: 'var(--warning)' }} />
          <div style={{ width: '10px', height: '10px', borderRadius: '50%', background: 'var(--success)' }} />
        </div>
        <span style={{ marginLeft: '16px', fontSize: '0.8rem', color: 'var(--text-muted)' }}>bash - root@neo-rmm</span>
      </div>

      {/* Log Output Area */}
      <div style={{ flex: 1, overflowY: 'auto', padding: '16px', fontSize: '0.85rem' }}>
        {logs.map((log) => (
          <motion.div
            key={log.id}
            initial={{ opacity: 0, y: 10, filter: 'blur(5px)' }}
            animate={{ opacity: 1, y: 0, filter: 'blur(0px)' }}
            transition={{ duration: 0.4, ease: "easeOut" }}
            style={{ marginBottom: '8px', display: 'flex', gap: '12px' }}
          >
            <span style={{ color: 'var(--text-muted)', minWidth: '85px' }}>
              {new Date(log.time).toLocaleTimeString('en-US', { hour12: false })}
            </span>
            <span className={getColorClass(log.type)} style={{ minWidth: '70px', fontWeight: '600' }}>
              [{log.type}]
            </span>
            <span style={{ color: 'rgba(255,255,255,0.9)' }}>
              {log.message}
            </span>
          </motion.div>
        ))}
        {/* Blinking Cursor */}
        <div style={{ display: 'flex', gap: '12px', marginTop: '8px' }}>
          <span className="terminal-text-cyan" style={{ fontWeight: '600' }}>neo></span>
          <span style={{ width: '8px', height: '16px', background: 'var(--primary)', animation: 'blink 1s step-end infinite' }} />
        </div>
        <div ref={bottomRef} />
      </div>

      <style>{`
        @keyframes blink { 50% { opacity: 0; } }
      `}</style>
    </div>
  );
}
