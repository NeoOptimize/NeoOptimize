import unittest

from neocortex import NeoCortexModel, normalize_telemetry


def sample(index, **overrides):
    data = {
        "ts": f"2026-05-19T01:{index:02d}:00",
        "cpu_pct": 24 + (index % 3),
        "ram_used_mb": 3200 + (index % 4) * 20,
        "disk_free_gb": 42,
        "net_rx_kbps": 110 + (index % 5) * 7,
    }
    data.update(overrides)
    return data


class NeoCortexModelTest(unittest.TestCase):
    def test_normalizes_agent_ram_percent(self):
        normalized = normalize_telemetry({"c": 40, "r": 4096, "d": 12}, {"ram_mb": 8192})

        self.assertEqual(normalized["cpu_pct"], 40)
        self.assertEqual(normalized["ram_pct"], 50)
        self.assertEqual(normalized["disk_free_gb"], 12)

    def test_detects_anomalous_endpoint(self):
        model = NeoCortexModel()
        result = model.analyze(
            latest=sample(30, cpu_pct=97, ram_used_mb=7900, disk_free_gb=4, net_rx_kbps=4000),
            history=[sample(index) for index in range(24)],
            alerts=[{"severity": "high"}],
            agent={"id": "agent-1", "hostname": "lab-win-01", "ram_mb": 8192},
        )

        self.assertEqual(result["model"], "neocortex-hybrid-v1")
        self.assertLess(result["health_score"], 70)
        self.assertIn(result["risk_level"], {"critical", "high"})
        self.assertGreater(result["anomaly_score"], 0)
        self.assertTrue(result["signals"])
        self.assertFalse(result["guardrails"]["autonomous_actions"])
        self.assertNotIn("SNAPSHOT", result["guardrails"]["allowed_commands"])


if __name__ == "__main__":
    unittest.main()
