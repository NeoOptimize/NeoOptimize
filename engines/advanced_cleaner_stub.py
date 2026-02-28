import threading
import time
from typing import List, Optional, Callable
from enum import Enum


class CleanerCategory(Enum):
    SYSTEM_TEMP = "system_temp"
    BROWSER_CACHE = "browser_cache"


class AdvancedCleanerEngine:
    """Safe, non-destructive stub of AdvancedCleanerEngine for UI integration.

    This stub simulates scanning activity and reports progress via callbacks.
    It will NOT delete or modify files.
    """

    def __init__(self,
                 progress_callback: Optional[Callable[[float], None]] = None,
                 status_callback: Optional[Callable[[str], None]] = None,
                 log_callback: Optional[Callable[[str], None]] = None,
                 file_found_callback: Optional[Callable] = None,
                 config_path: Optional[str] = None):
        self.progress_callback = progress_callback
        self.status_callback = status_callback
        self.log_callback = log_callback
        self.file_found_callback = file_found_callback
        self._running = False
        self._thread = None

    def _log(self, message: str):
        if self.log_callback:
            try:
                self.log_callback(message)
            except Exception:
                pass

    def _report_progress(self, percent: float):
        if self.progress_callback:
            try:
                self.progress_callback(percent)
            except Exception:
                pass

    def start_cleaning(self, categories: Optional[List[CleanerCategory]] = None):
        if self._running:
            self._log('[Cleaner] Already running')
            return
        self._running = True
        self._thread = threading.Thread(target=self._run_simulation, args=(categories,))
        self._thread.daemon = True
        self._thread.start()
        self._log('[Cleaner] Start requested')

    def _run_simulation(self, categories: Optional[List[CleanerCategory]]):
        total_steps = 8
        for i in range(total_steps):
            if not self._running:
                self._log('[Cleaner] Stopped')
                break
            time.sleep(0.6)
            percent = (i + 1) / total_steps * 100
            self._report_progress(percent)
            self._log(f'[Cleaner] Scanning... {int(percent)}%')
            # Simulate files found callback
            if self.file_found_callback:
                try:
                    self.file_found_callback({'path': f'C:/temp/fake_{i}.tmp', 'size': 1024}, None)
                except Exception:
                    pass
        self._running = False
        self._log('[Cleaner] Finished')
        self._report_progress(100.0)

    def stop(self):
        if not self._running:
            self._log('[Cleaner] Not running')
            return
        self._running = False
        self._log('[Cleaner] Stop requested')
        # thread will exit naturally

    def is_running(self) -> bool:
        return self._running
