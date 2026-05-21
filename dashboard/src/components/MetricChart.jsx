import React from 'react';
import { AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts';

export default function MetricChart({ data, dataKey, color, title, isDanger = false }) {
  // If data is empty or undefined, provide empty array
  const chartData = data || [];

  // Tentukan warna aktual berdasarkan status 'danger'
  const currentColor = isDanger ? '#ff0055' : color;
  const glowShadow = isDanger ? '0 0 20px rgba(255,0,85,0.4)' : `0 0 15px ${color}33`;

  return (
    <div className="glass-panel" style={{ padding: '1.5rem', display: 'flex', flexDirection: 'column', height: '240px', boxShadow: glowShadow, transition: 'box-shadow 0.3s ease' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
        <h3 style={{ fontSize: '1rem', color: isDanger ? '#ff0055' : 'var(--text-main)', textShadow: isDanger ? '0 0 10px rgba(255,0,85,0.5)' : 'none' }}>
          {title}
        </h3>
        {chartData.length > 0 && (
          <span style={{ fontSize: '1.2rem', fontWeight: '700', color: currentColor }}>
            {chartData[chartData.length - 1][dataKey].toFixed(1)}%
          </span>
        )}
      </div>

      <div style={{ flex: 1, width: '100%', minHeight: 0 }}>
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={chartData} margin={{ top: 5, right: 0, left: -20, bottom: 0 }}>
            <defs>
              <linearGradient id={`colorGradient-${dataKey}`} x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor={currentColor} stopOpacity={0.5}/>
                <stop offset="95%" stopColor={currentColor} stopOpacity={0}/>
              </linearGradient>
            </defs>
            <XAxis dataKey="time" hide />
            <YAxis
              domain={[0, 100]}
              tick={{ fill: 'var(--text-muted)', fontSize: 10 }}
              axisLine={false}
              tickLine={false}
            />
            <Tooltip
              contentStyle={{
                backgroundColor: 'rgba(10,10,15,0.9)',
                borderColor: currentColor,
                borderRadius: '8px',
                color: '#fff',
                backdropFilter: 'blur(10px)',
                boxShadow: `0 4px 12px ${currentColor}33`
              }}
              itemStyle={{ color: currentColor, fontWeight: 'bold' }}
              labelStyle={{ display: 'none' }}
              formatter={(value) => [`${value.toFixed(1)}%`, title]}
            />
            <Area
              type="monotone"
              dataKey={dataKey}
              stroke={currentColor}
              strokeWidth={3}
              fillOpacity={1}
              fill={`url(#colorGradient-${dataKey})`}
              isAnimationActive={false} // Disable animation to prevent visual glitches on frequent updates
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
