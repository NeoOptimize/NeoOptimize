
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
