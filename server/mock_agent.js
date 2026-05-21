const WebSocket = require('ws');
const crypto = require('crypto');

const SERVER_URL = 'http://127.0.0.1:3000';
const WS_URL = 'ws://127.0.0.1:3000/ws';

const agentId = 'test-agent-' + crypto.randomBytes(4).toString('hex');
const hostname = 'NeoOpt-Test-Endpoint';

async function startAgent() {
  try {
    console.log(`Registering agent ${agentId}...`);
    const regRes = await fetch(`${SERVER_URL}/api/v1/agent/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        hwid: agentId,
        hostname: hostname,
        os_info: 'Windows 11 Pro',
        local_ip: '192.168.1.100',
        neo_version: '6.0.0',
        tags: ['test', 'mock']
      })
    });
    
    const data = await regRes.json();
    if (!regRes.ok) throw new Error(data.error || 'Registration failed');
    
    const token = data.token;
    console.log(`Registered successfully. Token received.`);

    const ws = new WebSocket(`${WS_URL}?token=${token}`);
    
    ws.on('open', () => {
      console.log('WebSocket connected.');
      
      setInterval(() => {
        if(ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({
            type: 'telemetry',
            payload: {
              cpu_usage: Math.floor(Math.random() * 40) + 10,
              mem_total: 16000000000,
              mem_used: Math.floor(Math.random() * 4000000000) + 4000000000,
              disk_free: 50000000000,
              uptime: process.uptime(),
              timestamp: new Date().toISOString()
            }
          }));
        }
      }, 3000);
    });

    ws.on('message', (data) => {
      console.log('Received command:', data.toString());
      try {
        const cmd = JSON.parse(data);
        if(cmd.type === 'command') {
          setTimeout(() => {
            ws.send(JSON.stringify({
              type: 'cmd_result',
              payload: {
                command_id: cmd.payload.id,
                status: 'success',
                output: `Mock executed ${cmd.payload.command} successfully.`
              }
            }));
          }, 1000);
        }
      } catch(e) { }
    });

    ws.on('error', (err) => console.error('WS Error:', err));
    ws.on('close', () => console.log('WS Closed'));

  } catch (error) {
    console.error('Error starting agent:', error.message);
  }
}

startAgent();
