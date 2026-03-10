
# Neo Optimize AI - Integration Guide

## Overview
This guide explains how to integrate the Neo AI Backend with your WPF desktop application.

## Prerequisites
1. Neo AI Backend running on localhost:7860
2. API key configured in backend .env
3. Network access to localhost (or remote backend)

## Integration Methods

### Method 1: JavaScript Bridge (Simplest)
If using WebView2 to host web content:

1. Include the JS bridge code in your HTML:
```html
<script src="neoai-client.js"></script>
```

2. Use in your JavaScript:
```javascript
// Check backend is running
const isHealthy = await neoAI.healthCheck();

// Get system info
const info = await neoAI.getSystemInfo();
console.log(info.device.ram_percent);

// Run tool
const result = await neoAI.executeTool('clean_temp', {}, true);
if (result.status === 'success') {
    console.log(result.result);
}

// Run smart boost
const boostResult = await neoAI.smartBoost(true);
```

### Method 2: C# Native Integration
For WPF desktop applications:

1. Add NeoAIBackendService to your project
2. Inject into your ViewModels
3. Call methods as needed:

```csharp
var neoAI = new NeoAIBackendService();
var isHealthy = await neoAI.HealthCheckAsync();
var result = await neoAI.SmartBoostAsync(dryRun: true);
```

### Method 3: HTTP Client (Generic)
Use any HTTP client to call API:

```
GET http://localhost:7860/system-info
Headers: X-API-Key: dev_key_12345
```

## UI Integration Points

### 1. System Monitor Widget
Display real-time system information:

```javascript
async function updateSystemMonitor() {
    const info = await neoAI.getSystemInfo();
    document.getElementById('ram-percent').innerText = 
        info.device.ram_percent.toFixed(1) + '%';
    document.getElementById('disk-usage').innerText =
        info.device.disks[0].used_percent.toFixed(1) + '%';
}
setInterval(updateSystemMonitor, 5000);
```

### 2. Smart Advice Display
Show optimization recommendations:

```javascript
async function updateAdvice() {
    const advice = await neoAI.getSmartAdvice();
    document.getElementById('advice-box').innerText = advice;
}
```

### 3. Quick Action Buttons
Add buttons for common operations:

```html
<button onclick="runCleanup()">Clean Temp Files</button>
<button onclick="runSmartBoost()">Smart Boost</button>
<button onclick="runDefrag()">Defragment</button>
```

### 4. Operation Results Dialog
Show operation results in modal:

```javascript
async function runSmartBoost() {
    showLoadingDialog();
    const result = await neoAI.smartBoost(dryRun: true);
    
    if (result.status === 'success') {
        showResultsDialog(result.result);
    } else {
        showErrorDialog(result.error);
    }
}
```

## Error Handling

Always handle connection failures gracefully:

```javascript
const neoAI = new NeoAIClient();

async function safeExecuteTool(toolName) {
    try {
        // Check backend first
        if (!await neoAI.healthCheck()) {
            showMessage("Backend is not running. Start it first.");
            return;
        }
        
        const result = await neoAI.executeTool(toolName, {}, true);
        if (result.status === 'success') {
            showMessage("Success: " + result.result);
        } else {
            showError("Error: " + result.error);
        }
    } catch (error) {
        showError("Connection failed: " + error.message);
    }
}
```

## API Configuration

### Changing Backend URL
If running backend on different machine:

JavaScript:
```javascript
const neoAI = new NeoAIClient('http://192.168.1.100:7860', 'api_key');
```

C#:
```csharp
var service = new NeoAIBackendService();
service._baseUrl = "http://192.168.1.100:7860";
```

### Changing API Key
Update in backend .env:
```env
CLIENT_API_KEY=your_new_secure_key
```

Then update clients:
```javascript
const neoAI = new NeoAIClient('http://localhost:7860', 'your_new_secure_key');
```

## Deployment

### Development
- Backend: localhost:7860
- UI: localhost:7861 (Gradio) or localhost:5000 (your app)

### Production
1. Deploy backend to secure server
2. Update base URL in clients
3. Use strong API key
4. Enable HTTPS/SSL
5. Configure firewall rules
6. Monitor logs and usage

## Troubleshooting

### Backend not responding
1. Check backend is running: `curl http://localhost:7860/health`
2. Check firewall allows port 7860
3. Check API key is correct
4. Check network connectivity

### CORS Issues (JavaScript)
If using from different domain:
```javascript
const neoAI = new NeoAIClient();
// Add CORS headers to backend if needed
fetch(url, {
    mode: 'cors',
    credentials: 'include'
})
```

### Operation Failures
1. Check logs: `d:\NeoOptimize\logs\`
2. Run as administrator
3. Check Windows updates
4. Try SFC scan: `sfc /scannow`
