"""
NeoOptimize App Integration Module
Integration between WPF Desktop App and Neo AI Backend
"""

import json
import asyncio
import logging
from typing import Dict, Any, Optional
from datetime import datetime
import requests

logger = logging.getLogger("NeoOptimizeIntegration")

# ============================================================
# BACKEND API CLIENT
# ============================================================

class NeoAIBackendClient:
    """
    Client for integrating with Neo AI Backend from WebView/Desktop App
    Usage from C# WebView host or JavaScript guest:
    
    C#:
        var client = new NeoAIBackendClient("http://localhost:7860", "api_key");
        var result = await client.ExecuteToolAsync("clean_temp", new { dry_run = true });
    
    JavaScript:
        const client = new NeoAIBackendClient("http://localhost:7860", "api_key");
        const result = await client.executeTool("clean_temp", { dry_run: true });
    """
    
    def __init__(self, base_url: str = "http://localhost:7860", api_key: str = "dev_key_12345"):
        self.base_url = base_url
        self.api_key = api_key
        self.headers = {"X-API-Key": api_key, "Content-Type": "application/json"}
        self.session = requests.Session()
        self.session.headers.update(self.headers)
    
    def health_check(self) -> bool:
        """Check if backend is running"""
        try:
            response = self.session.get(f"{self.base_url}/health", timeout=5)
            return response.status_code == 200
        except Exception as e:
            logger.error(f"Health check failed: {e}")
            return False
    
    def get_system_info(self) -> Optional[Dict[str, Any]]:
        """Get current system information"""
        try:
            response = self.session.get(f"{self.base_url}/system-info", timeout=10)
            return response.json() if response.status_code == 200 else None
        except Exception as e:
            logger.error(f"Get system info failed: {e}")
            return None
    
    def get_smart_advice(self) -> Optional[str]:
        """Get smart optimization advice"""
        try:
            response = self.session.get(f"{self.base_url}/smart-advice", timeout=10)
            if response.status_code == 200:
                return response.json().get("advice")
            return None
        except Exception as e:
            logger.error(f"Get advice failed: {e}")
            return None
    
    def execute_tool(self, tool_name: str, params: Dict[str, Any] = None, dry_run: bool = True) -> Dict[str, Any]:
        """Execute a system optimization tool"""
        try:
            payload = {
                "tool_name": tool_name,
                "params": params or {},
                "dry_run": dry_run
            }
            response = self.session.post(
                f"{self.base_url}/execute-tool",
                json=payload,
                timeout=300
            )
            return response.json() if response.status_code == 200 else {
                "status": "error",
                "error": f"HTTP {response.status_code}"
            }
        except Exception as e:
            logger.error(f"Execute tool failed: {e}")
            return {"status": "error", "error": str(e)}
    
    def smart_boost(self, dry_run: bool = True) -> Dict[str, Any]:
        """Execute smart boost optimization"""
        try:
            response = self.session.post(
                f"{self.base_url}/smart-boost",
                params={"dry_run": dry_run},
                timeout=600
            )
            return response.json() if response.status_code == 200 else {
                "status": "error",
                "error": f"HTTP {response.status_code}"
            }
        except Exception as e:
            logger.error(f"Smart boost failed: {e}")
            return {"status": "error", "error": str(e)}

# ============================================================
# JAVASCRIPT BRIDGE FOR WEBVIEW
# ============================================================

JS_BRIDGE_CODE = """
// Neo Optimize AI Backend Client - JavaScript Version
// Include this in WebApp to communicate with backend

class NeoAIClient {
    constructor(baseUrl = 'http://localhost:7860', apiKey = 'dev_key_12345') {
        this.baseUrl = baseUrl;
        this.apiKey = apiKey;
        this.headers = {
            'X-API-Key': apiKey,
            'Content-Type': 'application/json'
        };
    }
    
    async healthCheck() {
        try {
            const response = await fetch(`${this.baseUrl}/health`, {
                method: 'GET',
                headers: this.headers,
                timeout: 5000
            });
            return response.ok;
        } catch (error) {
            console.error('Health check failed:', error);
            return false;
        }
    }
    
    async getSystemInfo() {
        try {
            const response = await fetch(`${this.baseUrl}/system-info`, {
                method: 'GET',
                headers: this.headers
            });
            return response.ok ? await response.json() : null;
        } catch (error) {
            console.error('Get system info failed:', error);
            return null;
        }
    }
    
    async getSmartAdvice() {
        try {
            const response = await fetch(`${this.baseUrl}/smart-advice`, {
                method: 'GET',
                headers: this.headers
            });
            if (response.ok) {
                const data = await response.json();
                return data.advice;
            }
            return null;
        } catch (error) {
            console.error('Get advice failed:', error);
            return null;
        }
    }
    
    async executeTool(toolName, params = {}, dryRun = true) {
        try {
            const payload = {
                tool_name: toolName,
                params: params,
                dry_run: dryRun
            };
            
            const response = await fetch(`${this.baseUrl}/execute-tool`, {
                method: 'POST',
                headers: this.headers,
                body: JSON.stringify(payload)
            });
            
            return response.ok ? await response.json() : {
                status: 'error',
                error: `HTTP ${response.status}`
            };
        } catch (error) {
            console.error('Execute tool failed:', error);
            return { status: 'error', error: error.message };
        }
    }
    
    async smartBoost(dryRun = true) {
        try {
            const response = await fetch(`${this.baseUrl}/smart-boost?dry_run=${dryRun}`, {
                method: 'POST',
                headers: this.headers
            });
            
            return response.ok ? await response.json() : {
                status: 'error',
                error: `HTTP ${response.status}`
            };
        } catch (error) {
            console.error('Smart boost failed:', error);
            return { status: 'error', error: error.message };
        }
    }
}

// Create global client instance
const neoAI = new NeoAIClient();

// Expose to WebView host via window.neoai
window.neoai = neoAI;
"""

# ============================================================
# C# INTEGRATION EXAMPLES
# ============================================================

CS_INTEGRATION_EXAMPLE = """
// C# Integration Example for NeoOptimize.App.exe

using System;
using System.Net.Http;
using System.Threading.Tasks;
using System.Text.Json;
using Newtonsoft.Json.Linq;

namespace NeoOptimize.Services
{
    public class NeoAIBackendService
    {
        private readonly HttpClient _httpClient;
        private readonly string _baseUrl = "http://localhost:7860";
        private readonly string _apiKey = "dev_key_12345";
        
        public NeoAIBackendService()
        {
            _httpClient = new HttpClient();
            _httpClient.DefaultRequestHeaders.Add("X-API-Key", _apiKey);
        }
        
        // Health Check
        public async Task<bool> HealthCheckAsync()
        {
            try
            {
                var response = await _httpClient.GetAsync($"{_baseUrl}/health");
                return response.IsSuccessStatusCode;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Health check failed: {ex.Message}");
                return false;
            }
        }
        
        // Get System Info
        public async Task<JObject> GetSystemInfoAsync()
        {
            try
            {
                var response = await _httpClient.GetAsync($"{_baseUrl}/system-info");
                if (response.IsSuccessStatusCode)
                {
                    var content = await response.Content.ReadAsStringAsync();
                    return JObject.Parse(content);
                }
                return null;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Get system info failed: {ex.Message}");
                return null;
            }
        }
        
        // Get Smart Advice
        public async Task<string> GetSmartAdviceAsync()
        {
            try
            {
                var response = await _httpClient.GetAsync($"{_baseUrl}/smart-advice");
                if (response.IsSuccessStatusCode)
                {
                    var content = await response.Content.ReadAsStringAsync();
                    var data = JObject.Parse(content);
                    return data["advice"]?.ToString();
                }
                return null;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Get advice failed: {ex.Message}");
                return null;
            }
        }
        
        // Execute Tool
        public async Task<JObject> ExecuteToolAsync(string toolName, bool dryRun = true)
        {
            try
            {
                var payload = new
                {
                    tool_name = toolName,
                    params = new { },
                    dry_run = dryRun
                };
                
                var json = JsonSerializer.Serialize(payload);
                var content = new StringContent(json, System.Text.Encoding.UTF8, "application/json");
                
                var response = await _httpClient.PostAsync($"{_baseUrl}/execute-tool", content);
                
                if (response.IsSuccessStatusCode)
                {
                    var responseContent = await response.Content.ReadAsStringAsync();
                    return JObject.Parse(responseContent);
                }
                
                return new JObject { ["status"] = "error", ["error"] = $"HTTP {response.StatusCode}" };
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Execute tool failed: {ex.Message}");
                return new JObject { ["status"] = "error", ["error"] = ex.Message };
            }
        }
        
        // Smart Boost
        public async Task<JObject> SmartBoostAsync(bool dryRun = true)
        {
            try
            {
                var uri = new UriBuilder($"{_baseUrl}/smart-boost")
                {
                    Query = $"dry_run={dryRun.ToString().ToLower()}"
                }.Uri;
                
                var response = await _httpClient.PostAsync(uri, null);
                
                if (response.IsSuccessStatusCode)
                {
                    var content = await response.Content.ReadAsStringAsync();
                    return JObject.Parse(content);
                }
                
                return new JObject { ["status"] = "error", ["error"] = $"HTTP {response.StatusCode}" };
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Smart boost failed: {ex.Message}");
                return new JObject { ["status"] = "error", ["error"] = ex.Message };
            }
        }
    }
    
    // Usage in MainWindow or View:
    public partial class MainWindow
    {
        private NeoAIBackendService _neoAI = new NeoAIBackendService();
        
        public async void OnSmartBoostClick()
        {
            // Show loading UI
            loadingSpinner.Visibility = Visibility.Visible;
            
            // Check backend is running
            bool isHealthy = await _neoAI.HealthCheckAsync();
            if (!isHealthy)
            {
                MessageBox.Show("Neo AI Backend is not running. Start it first.");
                return;
            }
            
            // Get system info
            var systemInfo = await _neoAI.GetSystemInfoAsync();
            UpdateSystemInfoUI(systemInfo);
            
            // Run smart boost in dry-run mode first
            var result = await _neoAI.SmartBoostAsync(dryRun: true);
            
            if (result["status"].ToString() == "success")
            {
                // Show preview results
                previewText.Text = result["result"].ToString();
                
                // Ask user to confirm
                if (MessageBox.Show("Review the changes above. Execute?", "Smart Boost", 
                    MessageBoxButton.YesNo) == MessageBoxResult.Yes)
                {
                    // Run actual execution
                    var execResult = await _neoAI.SmartBoostAsync(dryRun: false);
                    resultText.Text = execResult["result"].ToString();
                }
            }
            else
            {
                resultText.Text = $"Error: {result["error"]}";
            }
            
            // Hide loading UI
            loadingSpinner.Visibility = Visibility.Collapsed;
        }
        
        private void UpdateSystemInfoUI(JObject systemInfo)
        {
            if (systemInfo == null) return;
            
            var device = systemInfo["device"];
            ramPercentText.Text = $"{device["ram_percent"]}%";
            
            foreach (var disk in device["disks"])
            {
                diskListBox.Items.Add($"{disk["drive"]}: {disk["used_percent"]}% used");
            }
        }
    }
}
"""

# ============================================================
# INTEGRATION GUIDE
# ============================================================

INTEGRATION_GUIDE = """
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
1. Check logs: `d:\\NeoOptimize\\logs\\`
2. Run as administrator
3. Check Windows updates
4. Try SFC scan: `sfc /scannow`
"""

# ============================================================
# IMPLEMENTATION
# ============================================================

if __name__ == "__main__":
    print("Neo AI Integration Module")
    print("\nJS Bridge Code Length:", len(JS_BRIDGE_CODE))
    print("C# Integration Code Length:", len(CS_INTEGRATION_EXAMPLE))
    print("Integration Guide Length:", len(INTEGRATION_GUIDE))
    
    # Save integration files
    with open("d:/NeoOptimize/backend/neoai-client.js", "w") as f:
        f.write(JS_BRIDGE_CODE)
    
    with open("d:/NeoOptimize/backend/NeoAIBackendService.cs", "w") as f:
        f.write(CS_INTEGRATION_EXAMPLE)
    
    with open("d:/NeoOptimize/backend/INTEGRATION.md", "w") as f:
        f.write(INTEGRATION_GUIDE)
    
    print("\nIntegration files created successfully!")
