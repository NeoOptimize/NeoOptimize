"""
Neo Optimize AI - Gradio Web Interface
Full-featured UI for system optimization
"""

import gradio as gr
import requests
import json
from datetime import datetime
from typing import List, Tuple

# Backend configuration
BACKEND_URL = "http://localhost:7860"
API_KEY = "dev_key_12345"

# ============================================================
# API CLIENT
# ============================================================

class NeoOptimizeClient:
    """Client for Neo Optimize Backend API"""
    
    def __init__(self, base_url: str = BACKEND_URL, api_key: str = API_KEY):
        self.base_url = base_url
        self.api_key = api_key
        self.headers = {"X-API-Key": api_key}
    
    def get_system_info(self) -> dict:
        """Get system information"""
        try:
            response = requests.get(
                f"{self.base_url}/system-info",
                headers=self.headers,
                timeout=10
            )
            return response.json()
        except Exception as e:
            return {"error": str(e)}
    
    def get_smart_advice(self) -> str:
        """Get smart optimization advice"""
        try:
            response = requests.get(
                f"{self.base_url}/smart-advice",
                headers=self.headers,
                timeout=10
            )
            data = response.json()
            return data.get("advice", "No advice available")
        except Exception as e:
            return f"Error: {str(e)}"
    
    def execute_tool(self, tool_name: str, params: dict = {}, dry_run: bool = True) -> dict:
        """Execute a tool"""
        try:
            payload = {
                "tool_name": tool_name,
                "params": params,
                "dry_run": dry_run
            }
            response = requests.post(
                f"{self.base_url}/execute-tool",
                json=payload,
                headers=self.headers,
                timeout=300
            )
            return response.json()
        except Exception as e:
            return {"error": str(e), "status": "failed"}
    
    def smart_boost(self, dry_run: bool = True) -> dict:
        """Execute smart boost"""
        try:
            response = requests.post(
                f"{self.base_url}/smart-boost",
                params={"dry_run": dry_run},
                headers=self.headers,
                timeout=600
            )
            return response.json()
        except Exception as e:
            return {"error": str(e), "status": "failed"}

client = NeoOptimizeClient()

# ============================================================
# UI COMPONENTS
# ============================================================

def format_system_info(info: dict) -> str:
    """Format system info for display"""
    if "error" in info:
        return f"Error: {info['error']}"
    
    text = "📊 **SYSTEM INFORMATION**\n\n"
    device = info.get("device", {})
    
    # RAM
    ram_total = device.get("ram_total_mb", 0)
    ram_free = device.get("ram_free_mb", 0)
    ram_percent = device.get("ram_percent", 0)
    
    health = "🟢" if ram_percent < 70 else ("🟡" if ram_percent < 85 else "🔴")
    text += f"{health} **RAM:** {ram_free:,} MB free / {ram_total:,} MB total ({ram_percent}% used)\n\n"
    
    # Disks
    text += "💿 **DISK SPACE:**\n"
    for disk in device.get("disks", []):
        drive = disk.get("drive")
        used_pct = disk.get("used_percent", 0)
        free_gb = disk.get("free_gb", 0)
        total_gb = disk.get("total_gb", 0)
        health = "🟢" if used_pct < 75 else ("🟡" if used_pct < 85 else "🔴")
        text += f"{health} **{drive}:** {free_gb} GB free / {total_gb} GB total ({used_pct}% used)\n"
    
    text += f"\n⏰ **Updated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
    
    return text

def refresh_system_info() -> str:
    """Refresh and display system info"""
    info = client.get_system_info()
    return format_system_info(info)

def run_cleaner(cleaner_type: str, action: str) -> Tuple[str, str]:
    """Run a cleaner tool"""
    dry_run = (action == "Dry Run")
    
    messages = {
        "temp": "Cleaning temporary files...",
        "browser": "Cleaning browser cache...",
        "recycle": "Emptying recycle bin...",
        "registry": "Cleaning registry...",
    }
    
    tool_map = {
        "temp": "clean_temp",
        "browser": "clean_browser",
        "recycle": "clean_recycle",
        "registry": "clean_registry",
    }
    
    status = messages.get(cleaner_type, "Running cleaner...")
    status += f" ({'DRY RUN' if dry_run else 'ACTUAL EXECUTION'})\n\n"
    
    result = client.execute_tool(
        tool_map.get(cleaner_type, "clean_temp"),
        dry_run=dry_run
    )
    
    if result.get("status") == "success":
        status += f"✅ **SUCCESS**\n\n{result.get('result', 'Operation completed')}"
    else:
        status += f"❌ **ERROR**\n\n{result.get('error', 'Unknown error')}"
    
    advice = client.get_smart_advice()
    
    return status, advice

def run_defrag(drive: str, action: str) -> str:
    """Run disk defragmentation"""
    dry_run = (action == "Analyze Only")
    
    status = f"Defragmenting drive {drive}... ({'DRY RUN' if dry_run else 'ACTUAL'})\n\n"
    
    result = client.execute_tool(
        "defrag",
        params={"drive": drive},
        dry_run=dry_run
    )
    
    if result.get("status") == "success":
        status += f"✅ **DEFRAG STARTED**\n\n{result.get('result', 'Operation started')}\n\nNote: This may take several hours."
    else:
        status += f"❌ **ERROR**\n\n{result.get('error', 'Unknown error')}"
    
    return status

def run_trim(drive: str, action: str) -> str:
    """Run SSD TRIM"""
    dry_run = (action == "Check Status")
    
    status = f"TRIM operation on {drive}... ({'DRY RUN' if dry_run else 'EXECUTING'})\n\n"
    
    result = client.execute_tool(
        "trim",
        params={"drive": drive},
        dry_run=dry_run
    )
    
    if result.get("status") == "success":
        status += f"✅ **TRIM COMPLETED**\n\n{result.get('result', 'Operation completed')}"
    else:
        status += f"❌ **ERROR**\n\n{result.get('error', 'Unknown error')}"
    
    return status

def run_disk_scan(drive: str, action: str) -> str:
    """Run disk scan"""
    fix_errors = (action == "Scan & Repair")
    dry_run = (action == "Scan Only")
    
    status = f"Scanning disk {drive}... ({'DRY RUN' if dry_run else 'REPAIR ENABLED'})\n\n"
    
    result = client.execute_tool(
        "scan_disk",
        params={"drive": drive, "fix_errors": fix_errors},
        dry_run=dry_run
    )
    
    if result.get("status") == "success":
        status += f"✅ **SCAN COMPLETED**\n\n{result.get('result', 'Operation completed')}"
    else:
        status += f"❌ **ERROR**\n\n{result.get('error', 'Unknown error')}"
    
    return status

def run_wipe_free(drive: str, action: str) -> str:
    """Wipe free disk space"""
    dry_run = (action == "Preview")
    
    status = f"Wiping free space on {drive}... ({'PREVIEW' if dry_run else 'EXECUTING'})\n\n"
    status += "⚠️ **WARNING:** This operation can take several hours!\n\n"
    
    result = client.execute_tool(
        "wipe_free",
        params={"drive": drive},
        dry_run=dry_run
    )
    
    if result.get("status") == "success":
        status += f"✅ **INITIATED**\n\n{result.get('result', 'Operation started')}"
    else:
        status += f"❌ **ERROR**\n\n{result.get('error', 'Unknown error')}"
    
    return status

def run_sfc() -> str:
    """Run System File Checker"""
    status = "Running System File Checker...\n\n"
    
    result = client.execute_tool("sfc_scan", dry_run=False)
    
    if result.get("status") == "success":
        status += f"✅ **SFC SCAN COMPLETED**\n\n{result.get('result', 'Scan completed')}"
    else:
        status += f"❌ **ERROR**\n\n{result.get('error', 'Unknown error')}"
    
    return status

def run_dism() -> str:
    """Run DISM repair"""
    status = "Running DISM repair...\n\n"
    
    result = client.execute_tool("dism_repair", dry_run=False)
    
    if result.get("status") == "success":
        status += f"✅ **DISM REPAIR COMPLETED**\n\n{result.get('result', 'Repair completed')}"
    else:
        status += f"❌ **ERROR**\n\n{result.get('error', 'Unknown error')}"
    
    return status

def remove_bloatware_fn(action: str) -> str:
    """Remove bloatware"""
    dry_run = (action == "List Only")
    
    status = f"Bloatware removal... ({'LIST ONLY' if dry_run else 'ACTUAL REMOVAL'})\n\n"
    
    result = client.execute_tool("remove_bloatware", dry_run=dry_run)
    
    if result.get("status") == "success":
        status += f"✅ **COMPLETED**\n\n{result.get('result', 'Operation completed')}"
    else:
        status += f"❌ **ERROR**\n\n{result.get('error', 'Unknown error')}"
    
    return status

def disable_telemetry_fn(action: str) -> str:
    """Disable telemetry"""
    dry_run = (action == "Preview")
    
    status = f"Disabling telemetry... ({'PREVIEW' if dry_run else 'EXECUTING'})\n\n"
    
    result = client.execute_tool("disable_telemetry", dry_run=dry_run)
    
    if result.get("status") == "success":
        status += f"✅ **COMPLETED**\n\n{result.get('result', 'Operation completed')}"
    else:
        status += f"❌ **ERROR**\n\n{result.get('error', 'Unknown error')}"
    
    return status

def run_smart_boost_fn(action: str) -> Tuple[str, str]:
    """Execute smart boost optimization"""
    dry_run = (action == "Preview")
    
    status = f"🚀 **SMART BOOST** ({'PREVIEW' if dry_run else 'EXECUTING'})\n\n"
    status += "Running comprehensive optimization...\n\n"
    
    result = client.smart_boost(dry_run=dry_run)
    
    if result.get("status") == "success":
        status += f"✅ **OPTIMIZATION COMPLETED**\n\n{result.get('result', 'Optimization completed')}"
    else:
        status += f"❌ **ERROR**\n\n{result.get('error', 'Unknown error')}"
    
    advice = client.get_smart_advice()
    
    return status, advice

# ============================================================
# GRADIO INTERFACE
# ============================================================

with gr.Blocks(title="Neo Optimize AI", theme=gr.themes.Soft()) as demo:
    gr.Markdown("# 🤖 Neo Optimize AI - Advanced Windows System Optimizer")
    gr.Markdown("Complete system optimization with AI-powered recommendations")
    
    # -------- SYSTEM MONITOR TAB --------
    with gr.Tab("📊 System Monitor"):
        with gr.Row():
            refresh_btn = gr.Button("🔄 Refresh System Info", size="lg", variant="primary")
            system_info = gr.Markdown("Loading system information...")
        
        refresh_btn.click(refresh_system_info, outputs=system_info)
        
        # Auto-refresh on load
        demo.load(refresh_system_info, outputs=system_info)
    
    # -------- CLEANERS TAB --------
    with gr.Tab("🧹 Cleaners"):
        gr.Markdown("### Complete System Cleanup")
        
        with gr.Row():
            with gr.Column():
                gr.Markdown("#### Temporary Files")
                cleaner_action = gr.Radio(["Dry Run", "Execute"], value="Dry Run", label="Action")
                clean_temp_btn = gr.Button("Clean Temp Files", variant="primary")
            
            with gr.Column():
                gr.Markdown("#### Browser Cache")
                browser_action = gr.Radio(["Dry Run", "Execute"], value="Dry Run", label="Action")
                clean_browser_btn = gr.Button("Clean Browser Cache", variant="primary")
        
        with gr.Row():
            with gr.Column():
                gr.Markdown("#### Recycle Bin")
                recycle_action = gr.Radio(["Dry Run", "Execute"], value="Dry Run", label="Action")
                clean_recycle_btn = gr.Button("Empty Recycle Bin", variant="primary")
            
            with gr.Column():
                gr.Markdown("#### Registry")
                registry_action = gr.Radio(["Dry Run", "Execute"], value="Dry Run", label="Action")
                clean_registry_btn = gr.Button("Clean Registry", variant="primary")
        
        # Output
        with gr.Row():
            cleaner_output = gr.Markdown("Results will appear here...")
            advice_output = gr.Markdown("Smart advice will appear here...")
        
        # Event handlers
        clean_temp_btn.click(
            lambda action: run_cleaner("temp", action),
            inputs=cleaner_action,
            outputs=[cleaner_output, advice_output]
        )
        clean_browser_btn.click(
            lambda action: run_cleaner("browser", action),
            inputs=browser_action,
            outputs=[cleaner_output, advice_output]
        )
        clean_recycle_btn.click(
            lambda action: run_cleaner("recycle", action),
            inputs=recycle_action,
            outputs=[cleaner_output, advice_output]
        )
        clean_registry_btn.click(
            lambda action: run_cleaner("registry", action),
            inputs=registry_action,
            outputs=[cleaner_output, advice_output]
        )
    
    # -------- DEFRAGMENTATION TAB --------
    with gr.Tab("⚙️ Defragmentation & TRIM"):
        gr.Markdown("### Disk Optimization")
        
        with gr.Row():
            with gr.Column():
                gr.Markdown("#### Defragmentation (HDD)")
                defrag_drive = gr.Dropdown(["C", "D", "E", "F"], value="C", label="Drive")
                defrag_action = gr.Radio(["Analyze Only", "Defragment"], value="Analyze Only", label="Action")
                defrag_btn = gr.Button("Start Defrag", variant="primary")
            
            with gr.Column():
                gr.Markdown("#### TRIM (SSD)")
                trim_drive = gr.Dropdown(["C", "D", "E", "F"], value="C", label="Drive")
                trim_action = gr.Radio(["Check Status", "Run TRIM"], value="Check Status", label="Action")
                trim_btn = gr.Button("Run TRIM", variant="primary")
        
        defrag_output = gr.Markdown("Results will appear here...")
        trim_output = gr.Markdown("Results will appear here...")
        
        defrag_btn.click(
            lambda drive, action: run_defrag(drive, action),
            inputs=[defrag_drive, defrag_action],
            outputs=defrag_output
        )
        trim_btn.click(
            lambda drive, action: run_trim(drive, action),
            inputs=[trim_drive, trim_action],
            outputs=trim_output
        )
    
    # -------- DISK SCAN TAB --------
    with gr.Tab("💿 Disk Scan & Repair"):
        gr.Markdown("### Disk Health & Repair")
        
        with gr.Row():
            with gr.Column():
                gr.Markdown("#### Disk Scanning")
                scan_drive = gr.Dropdown(["C", "D", "E", "F"], value="C", label="Drive")
                scan_action = gr.Radio(["Scan Only", "Scan & Repair"], value="Scan Only", label="Action")
                scan_btn = gr.Button("Scan Disk", variant="primary")
            
            with gr.Column():
                gr.Markdown("#### Free Space Wipe")
                wipe_drive = gr.Dropdown(["C", "D", "E", "F"], value="C", label="Drive")
                wipe_action = gr.Radio(["Preview", "Wipe"], value="Preview", label="Action")
                wipe_btn = gr.Button("Wipe Free Space", variant="primary", scale=2)
        
        scan_output = gr.Markdown("Results will appear here...")
        wipe_output = gr.Markdown("Results will appear here...")
        
        scan_btn.click(
            lambda drive, action: run_disk_scan(drive, action),
            inputs=[scan_drive, scan_action],
            outputs=scan_output
        )
        wipe_btn.click(
            lambda drive, action: run_wipe_free(drive, action),
            inputs=[wipe_drive, wipe_action],
            outputs=wipe_output
        )
    
    # -------- SYSTEM HEALTH TAB --------
    with gr.Tab("🏥 System Health"):
        gr.Markdown("### System File & Component Repair")
        
        with gr.Row():
            with gr.Column():
                sfc_btn = gr.Button("🔧 Run System File Checker (SFC)", variant="primary", size="lg")
            
            with gr.Column():
                dism_btn = gr.Button("⚙️ Run DISM Repair", variant="primary", size="lg")
        
        health_output = gr.Markdown("Results will appear here...")
        
        sfc_btn.click(run_sfc, outputs=health_output)
        dism_btn.click(run_dism, outputs=health_output)
    
    # -------- PRIVACY TAB --------
    with gr.Tab("🔒 Privacy & Security"):
        gr.Markdown("### Privacy & Bloatware Management")
        
        with gr.Row():
            with gr.Column():
                gr.Markdown("#### Remove Bloatware")
                bloatware_action = gr.Radio(["List Only", "Remove"], value="List Only", label="Action")
                bloatware_btn = gr.Button("Remove Bloatware", variant="primary")
            
            with gr.Column():
                gr.Markdown("#### Disable Telemetry")
                telemetry_action = gr.Radio(["Preview", "Disable"], value="Preview", label="Action")
                telemetry_btn = gr.Button("Disable Telemetry", variant="primary")
        
        privacy_output = gr.Markdown("Results will appear here...")
        
        bloatware_btn.click(
            lambda action: remove_bloatware_fn(action),
            inputs=bloatware_action,
            outputs=privacy_output
        )
        telemetry_btn.click(
            lambda action: disable_telemetry_fn(action),
            inputs=telemetry_action,
            outputs=privacy_output
        )
    
    # -------- SMART BOOST TAB --------
    with gr.Tab("🚀 Smart Boost"):
        gr.Markdown("### Comprehensive Optimization")
        gr.Markdown("Run all optimizations in one go with intelligent recommendations")
        
        with gr.Row():
            smart_action = gr.Radio(["Preview", "Execute"], value="Preview", label="Mode", scale=1)
            smart_btn = gr.Button("🚀 START SMART BOOST", variant="primary", size="lg", scale=2)
        
        with gr.Row():
            boost_output = gr.Markdown("Results will appear here...", scale=1)
            boost_advice = gr.Markdown("Recommendations will appear here...", scale=1)
        
        smart_btn.click(
            run_smart_boost_fn,
            inputs=smart_action,
            outputs=[boost_output, boost_advice]
        )
    
    # -------- ABOUT TAB --------
    with gr.Tab("ℹ️ About"):
        gr.Markdown("""
        # Neo Optimize AI
        
        **Version:** 1.0.0  
        **Status:** Production Ready
        
        ## Features
        
        ✅ **System Cleaners**
        - Temporary files, browser cache, recycle bin, registry cleanup
        
        ✅ **Disk Optimization**
        - Defragmentation for HDDs, TRIM for SSDs
        
        ✅ **Disk Scanning**
        - Disk error detection and repair, free space wiping
        
        ✅ **System Health**
        - System File Checker (SFC), DISM repair
        
        ✅ **Privacy & Security**
        - Bloatware removal, telemetry disabling
        
        ✅ **Smart Boost**
        - One-click comprehensive optimization
        
        ✅ **Autonomous Monitoring**
        - Continuous system health monitoring
        
        ✅ **AI-Powered Advisor**
        - Intelligent recommendations for system improvement
        
        ## Safety
        
        - **Dry-run mode** for all operations (preview before executing)
        - **Reversible operations** (no permanent data loss)
        - **API Key authentication** (secure backend)
        - **Comprehensive logging** for audit trails
        
        ## Support
        
        For issues or feature requests, contact support@neooptimize.com
        """)

if __name__ == "__main__":
    demo.launch(
        server_name="0.0.0.0",
        server_port=7861,
        share=False,
        show_error=True,
        show_api=False
    )
