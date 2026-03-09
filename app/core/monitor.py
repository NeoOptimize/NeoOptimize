import logging
import threading
import time
from datetime import datetime, timedelta
from app.services.supabase_client import get_supabase

logger = logging.getLogger(__name__)

class AutonomousMonitor:
    def __init__(self, check_interval=60):
        self.check_interval = check_interval
        self.running = True
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()
        logger.info("AutonomousMonitor started")

    def _run(self):
        while self.running:
            try:
                self._check_anomalies()
                self._cleanup_old_data()
            except Exception as e:
                logger.exception("Error in monitor loop")
            time.sleep(self.check_interval)

    def _check_anomalies(self):
        supabase = get_supabase()
        five_min_ago = (datetime.utcnow() - timedelta(minutes=5)).isoformat()
        clients_resp = supabase.table("clients").select("id").eq("status", "active").gte("last_seen", five_min_ago).execute()
        if not clients_resp.data:
            return

        for client in clients_resp.data:
            client_id = client["id"]
            tel_resp = supabase.table("telemetry_logs") \
                .select("cpu_percent, ram_percent, temperature_celsius") \
                .eq("client_id", client_id) \
                .order("logged_at", desc=True) \
                .limit(1) \
                .execute()
            if not tel_resp.data:
                continue
            data = tel_resp.data[0]
            cpu = data.get("cpu_percent", 0)
            ram = data.get("ram_percent", 0)
            temp = data.get("temperature_celsius", 0)
            alerts = []
            if cpu and cpu > 90:
                alerts.append(f"CPU usage at {cpu}%")
            if ram and ram > 95:
                alerts.append(f"RAM usage at {ram}%")
            if temp and temp > 85:
                alerts.append(f"Temperature at {temp}°C")

            if alerts:
                logger.warning(f"Anomaly detected for client {client_id}: {', '.join(alerts)}")
                # Buat command pembersihan sederhana
                cmd_data = {
                    "client_id": client_id,
                    "tool": "run_cleaner",
                    "params": {"category": "CAT_TEMP_FILES"},
                    "status": "pending"
                }
                supabase.table("commands").insert(cmd_data).execute()

    def _cleanup_old_data(self):
        supabase = get_supabase()
        cutoff = (datetime.utcnow() - timedelta(days=7)).isoformat()
        supabase.table("telemetry_logs").delete().lt("logged_at", cutoff).execute()
        supabase.table("action_logs").delete().lt("created_at", cutoff).execute()
        logger.debug("Old data cleaned up")

    def stop(self):
        self.running = False
        self.thread.join()