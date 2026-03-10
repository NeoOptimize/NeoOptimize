
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
