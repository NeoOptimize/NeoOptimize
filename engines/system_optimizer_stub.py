import threading
import time
from typing import Optional, Callable


class SystemOptimizationEngine:
    """Safe, non-destructive stub for SystemOptimizationEngine.

    Provides start/stop methods and simple logging/progress callbacks.
    """

    def __init__(self, status_callback: Optional[Callable[[str], None]] = None,
                 log_callback: Optional[Callable[[str], None]] = None,
                 progress_callback: Optional[Callable[[float], None]] = None):
        self.status_callback = status_callback
        self.log_callback = log_callback
        self.progress_callback = progress_callback
        self._running = False
        self._thread = None

    def _log(self, msg: str):
        if self.log_callback:
            try:
                self.log_callback(msg)
            except Exception:
                pass

    def _report_progress(self, p: float):
        if self.progress_callback:
            try:
                self.progress_callback(p)
            except Exception:
                pass

    def start(self):
        if self._running:
            self._log('[Optimizer] Already running')
            return
        self._running = True
        self._thread = threading.Thread(target=self._simulate_work)
        self._thread.daemon = True
        self._thread.start()
        self._log('[Optimizer] Started')

    def _simulate_work(self):
        steps = 5
        for i in range(steps):
            if not self._running:
                break
            time.sleep(0.8)
            pct = (i + 1) / steps * 100
            self._report_progress(pct)
            self._log(f'[Optimizer] Step {i+1}/{steps} ({int(pct)}%)')
        self._running = False
        self._log('[Optimizer] Finished')
        self._report_progress(100.0)

    def stop(self):
        if not self._running:
            self._log('[Optimizer] Not running')
            return
        self._running = False
        self._log('[Optimizer] Stop requested')

    def is_running(self) -> bool:
        return self._running
