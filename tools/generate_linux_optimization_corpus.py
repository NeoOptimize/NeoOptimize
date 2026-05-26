#!/usr/bin/env python3
"""
Build a risk-labeled Linux optimization corpus for Neo AI.

This intentionally does not create an executable "run list". Linux tuning
commands can break networking, filesystems, boot, or data integrity when applied
blindly. The output is JSONL knowledge records with risk gates so Neo can explain,
rank, and request approval instead of auto-executing unsafe commands.
"""

from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


COMMAND_TEMPLATES: list[dict[str, Any]] = [
    {
        "category": "memory",
        "intent": "drop page cache after disk sync",
        "template": "sync && echo {val} > /proc/sys/vm/drop_caches",
        "params": {"val": ["1", "2", "3"]},
        "safe_alternative": "free -h && vmstat 1 5",
    },
    {
        "category": "memory",
        "intent": "restart swap devices",
        "template": "swapoff -a && swapon -a",
        "params": {},
        "safe_alternative": "swapon --show && free -h",
    },
    {
        "category": "memory",
        "intent": "adjust swappiness",
        "template": "sysctl -w vm.swappiness={val}",
        "params": {"val": ["10", "20", "30", "60", "80", "100"]},
        "safe_alternative": "sysctl vm.swappiness",
    },
    {
        "category": "memory",
        "intent": "inspect memory pressure and cache",
        "template": "free -h && vmstat 1 5 && cat /proc/pressure/memory",
        "params": {},
        "safe_alternative": "free -h",
    },
    {
        "category": "cpu",
        "intent": "set CPU governor",
        "template": "cpupower frequency-set -g {gov}",
        "params": {"gov": ["performance", "powersave", "schedutil"]},
        "safe_alternative": "grep -H . /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor",
    },
    {
        "category": "cpu",
        "intent": "inspect CPU saturation",
        "template": "ps -eo pid,comm,pcpu,pmem,args --sort=-pcpu | head -20",
        "params": {},
        "safe_alternative": "uptime",
    },
    {
        "category": "cpu",
        "intent": "change process nice priority",
        "template": "renice -n {prio} -p {pid}",
        "params": {"prio": ["-10", "0", "10", "19"], "pid": ["<pid>"]},
        "safe_alternative": "ps -o pid,ni,comm -p <pid>",
    },
    {
        "category": "disk",
        "intent": "trim SSD/NVMe free blocks",
        "template": "fstrim {mount}",
        "params": {"mount": ["/", "/home", "-av"]},
        "safe_alternative": "lsblk -D && systemctl status fstrim.timer --no-pager",
    },
    {
        "category": "disk",
        "intent": "inspect disk usage",
        "template": "df -hT && lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS",
        "params": {},
        "safe_alternative": "df -hT",
    },
    {
        "category": "disk",
        "intent": "change block device read ahead",
        "template": "blockdev --setra {val} {dev}",
        "params": {"val": ["256", "512", "1024", "2048"], "dev": ["/dev/sda", "/dev/nvme0n1"]},
        "safe_alternative": "blockdev --getra <device>",
    },
    {
        "category": "disk",
        "intent": "disable ext filesystem journal",
        "template": "tune2fs -O ^has_journal {dev}",
        "params": {"dev": ["/dev/sda1", "/dev/nvme0n1p1"]},
        "safe_alternative": "tune2fs -l <device> | grep 'Filesystem features'",
    },
    {
        "category": "network",
        "intent": "inspect NetworkManager boot state",
        "template": "systemctl is-enabled NetworkManager && systemctl is-active NetworkManager && nmcli device status",
        "params": {},
        "safe_alternative": "nmcli device status",
    },
    {
        "category": "network",
        "intent": "enable NetworkManager at boot",
        "template": "systemctl enable --now NetworkManager",
        "params": {},
        "safe_alternative": "systemctl status NetworkManager --no-pager",
    },
    {
        "category": "network",
        "intent": "disable NetworkManager",
        "template": "systemctl {action} NetworkManager",
        "params": {"action": ["disable", "mask", "stop"]},
        "safe_alternative": "systemctl status NetworkManager --no-pager",
    },
    {
        "category": "network",
        "intent": "tune TCP congestion control",
        "template": "sysctl -w net.ipv4.tcp_congestion_control={cc}",
        "params": {"cc": ["bbr", "cubic", "reno"]},
        "safe_alternative": "sysctl net.ipv4.tcp_available_congestion_control net.ipv4.tcp_congestion_control",
    },
    {
        "category": "network",
        "intent": "inspect firewall status",
        "template": "ufw status verbose",
        "params": {},
        "safe_alternative": "ufw status verbose",
    },
    {
        "category": "network",
        "intent": "inspect DNS and routes",
        "template": "ip -br address && ip route && resolvectl status",
        "params": {},
        "safe_alternative": "ip route",
    },
    {
        "category": "services",
        "intent": "disable optional desktop services",
        "template": "systemctl {action} {service}",
        "params": {
            "action": ["disable", "stop", "mask"],
            "service": ["bluetooth", "cups", "avahi-daemon", "snapd"],
        },
        "safe_alternative": "systemctl status <service> --no-pager",
    },
    {
        "category": "cleanup",
        "intent": "clean package manager cache",
        "template": "{manager} {operation}",
        "params": {
            "manager": ["apt", "dnf", "yum", "zypper", "flatpak"],
            "operation": ["autoclean", "clean all", "clean", "uninstall --unused"],
        },
        "safe_alternative": "du -sh /var/cache/apt/archives ~/.cache 2>/dev/null",
    },
    {
        "category": "cleanup",
        "intent": "vacuum systemd journal",
        "template": "journalctl --vacuum-time={time}",
        "params": {"time": ["7d", "14d", "30d", "90d"]},
        "safe_alternative": "journalctl --disk-usage",
    },
    {
        "category": "cleanup",
        "intent": "delete old temp files",
        "template": "find {path} -type f -mtime {days} -delete",
        "params": {"path": ["/tmp", "/var/tmp"], "days": ["+3", "+7", "+30"]},
        "safe_alternative": "find <path> -type f -mtime <days> -print | head -100",
    },
    {
        "category": "boot",
        "intent": "inspect boot delay",
        "template": "systemd-analyze blame | head -{n}",
        "params": {"n": ["10", "20", "40"]},
        "safe_alternative": "systemd-analyze critical-chain",
    },
    {
        "category": "boot",
        "intent": "disable CPU vulnerability mitigations",
        "template": "sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"{old}\"/GRUB_CMDLINE_LINUX_DEFAULT=\"{new}\"/' /etc/default/grub && update-grub",
        "params": {"old": ["quiet splash", "quiet"], "new": ["quiet splash mitigations=off", "quiet splash noibrs"]},
        "safe_alternative": "cat /sys/devices/system/cpu/vulnerabilities/*",
    },
    {
        "category": "power",
        "intent": "inspect power profile",
        "template": "powerprofilesctl get 2>/dev/null || true",
        "params": {},
        "safe_alternative": "powerprofilesctl get",
    },
    {
        "category": "power",
        "intent": "auto tune laptop power",
        "template": "powertop --auto-tune",
        "params": {},
        "safe_alternative": "powertop --time=10 --html=/tmp/powertop.html",
    },
    {
        "category": "filesystem",
        "intent": "check filesystem without writing",
        "template": "fsck -n {dev}",
        "params": {"dev": ["/dev/sda1", "/dev/nvme0n1p1"]},
        "safe_alternative": "findmnt -no SOURCE,TARGET,FSTYPE /",
    },
    {
        "category": "filesystem",
        "intent": "repair filesystem with automatic yes",
        "template": "fsck -y {dev}",
        "params": {"dev": ["/dev/sda1", "/dev/nvme0n1p1"]},
        "safe_alternative": "fsck -n <unmounted-device>",
    },
]

MODIFIERS = [
    ("none", "{cmd}"),
    ("sudo", "sudo {cmd}"),
    ("capture", "{cmd} 2>&1 | tee /tmp/neo_linux_action.log"),
    ("timeout", "timeout 120s {cmd}"),
]

DENY_PATTERNS = [
    r"\brm\s+-rf\b",
    r"\bmkfs\b",
    r"\bdd\s+if=",
    r"\btune2fs\s+-O\s+\^has_journal\b",
    r"\bfsck\s+-y\b",
    r"\bmitigations=off\b",
    r"\bnoibrs\b",
    r"\bsystemctl\s+(disable|mask|stop)\s+NetworkManager\b",
    r"\bswapoff\s+-a\s+&&\s+swapon\s+-a\b",
    r">\s*/sys/power/state\b",
]

RISK_PATTERNS = [
    r"\bsysctl\s+-w\b",
    r">\s*/proc/sys/",
    r">\s*/sys/",
    r"\bcpupower\s+frequency-set\b",
    r"\bblockdev\s+--setra\b",
    r"\bhdparm\b",
    r"\bethtool\s+-K\b",
    r"\btc\s+qdisc\s+add\b",
    r"\bsystemctl\s+(disable|mask|stop)\b",
    r"\bapt\s+autoremove\b",
    r"\bjournalctl\s+--vacuum-",
    r"\bfind\b.*\s-delete\b",
    r"\bfstrim\b",
    r"\bpowertop\s+--auto-tune\b",
    r"\bfsck\b",
]

READ_ONLY_PATTERNS = [
    r"\b(systemctl status|systemctl is-enabled|systemctl is-active|nmcli|ufw status|ip -br|ip route|resolvectl|free|vmstat|df|lsblk|journalctl --disk-usage|systemd-analyze|ps )",
    r"\b(sysctl [a-z0-9_.]+|blockdev --getra|findmnt|cat /sys/devices/system/cpu/vulnerabilities)",
]


def sha256(value: str | bytes) -> str:
    if isinstance(value, str):
        value = value.encode("utf-8")
    return hashlib.sha256(value).hexdigest()


def expand(template: dict[str, Any]) -> list[str]:
    params = template.get("params", {})
    if not params:
        return [template["template"]]

    keys = list(params.keys())
    commands = []
    for values in itertools.product(*(params[key] for key in keys)):
        commands.append(template["template"].format(**dict(zip(keys, values))))
    return commands


def classify(command: str) -> tuple[str, str, bool]:
    lowered = command.lower()
    if any(re.search(pattern, lowered) for pattern in DENY_PATTERNS):
        return "deny", "never_auto_execute", False
    if any(re.search(pattern, lowered) for pattern in READ_ONLY_PATTERNS):
        return "read_only", "allow_without_elevation", False
    if any(re.search(pattern, lowered) for pattern in RISK_PATTERNS):
        return "high", "human_approval_required", True
    return "medium", "human_approval_required", True


def build_records(max_records: int) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in COMMAND_TEMPLATES:
        for command in expand(item):
            for modifier_name, modifier in MODIFIERS:
                full_command = modifier.format(cmd=command)
                digest = sha256(full_command)
                if digest in seen:
                    continue
                seen.add(digest)
                risk, execution_policy, requires_root = classify(full_command)
                text = (
                    f"Linux optimization command knowledge.\n"
                    f"Intent: {item['intent']}.\n"
                    f"Command: {full_command}\n"
                    f"Risk: {risk}. Execution policy: {execution_policy}.\n"
                    f"Requires root: {str(requires_root).lower()}.\n"
                    f"Safe alternative: {item['safe_alternative']}.\n"
                    f"Neo guidance: use as advisory knowledge first; execute only through a signed manifest, preflight checks, timeout, transcript logging, and rollback note."
                )
                records.append(
                    {
                        "id": f"neo-linux-corpus-{len(records) + 1:05d}",
                        "schema_version": "1.0",
                        "corpus": "neo-ai-linux-admin",
                        "content_sha256": digest,
                        "source_name": "generate_linux_optimization_corpus.py",
                        "source_path": "tools/generate_linux_optimization_corpus.py",
                        "source_ext": ".py",
                        "section": f"{item['category']} :: {item['intent']}",
                        "categories": ["linux", item["category"], "optimization", risk],
                        "keywords": sorted(set(re.findall(r"[a-zA-Z0-9_.:/-]{3,}", full_command)))[:24],
                        "risk_level": risk,
                        "execution_policy": execution_policy,
                        "requires_root": requires_root,
                        "command": full_command,
                        "safe_alternative": item["safe_alternative"],
                        "text": text,
                    }
                )
                if len(records) >= max_records:
                    return records
    add_scenario_records(records, seen, max_records)
    return records


def add_scenario_records(records: list[dict[str, Any]], seen: set[str], max_records: int) -> None:
    distros = ["linux mint", "ubuntu", "debian", "fedora", "arch", "opensuse", "rhel-compatible"]
    symptoms_by_category = {
        "memory": [
            "RAM cepat penuh saat browser, VM, dan local model berjalan bersama",
            "swap tinggi dan desktop terasa freeze",
            "zram perlu diverifikasi sebelum workload AI lokal",
            "cache memori besar tetapi tidak ada proses jelas yang bocor",
        ],
        "cpu": [
            "CPU tinggi saat proses user berjalan lama",
            "sistem terasa berat karena process priority tidak seimbang",
            "governor CPU tidak sesuai profil kerja",
        ],
        "disk": [
            "disk I/O tinggi dan desktop freezing",
            "NVMe atau SSD perlu dicek TRIM dan free space",
            "read ahead perlu diaudit sebelum tuning",
        ],
        "network": [
            "NetworkManager sering mati setelah boot",
            "DNS lambat dan route default tidak stabil",
            "UFW perlu diaudit tanpa memutus akses admin",
            "latency jaringan naik setelah perubahan adapter",
        ],
        "services": [
            "service opsional memakan resource saat boot",
            "boot lambat karena service dependency chain",
            "service kritis tidak boleh dimatikan otomatis",
        ],
        "cleanup": [
            "cache paket dan journal membesar",
            "folder tmp penuh tetapi perlu dry-run sebelum delete",
            "cleanup harus dapat dibuktikan dengan before-after disk usage",
        ],
        "boot": [
            "boot lambat dan perlu critical-chain analysis",
            "perubahan grub berisiko membuat sistem tidak boot",
            "mitigasi CPU tidak boleh dimatikan untuk mengejar benchmark",
        ],
        "power": [
            "profil power tidak sesuai mode kerja",
            "laptop panas dan battery cepat habis",
            "power tuning perlu rollback karena bisa mematikan perangkat input",
        ],
        "filesystem": [
            "filesystem error perlu dicek dari live system secara read-only",
            "repair filesystem wajib dari unmounted volume atau rescue mode",
            "bad sector harus dibedakan dari filesystem corruption",
        ],
    }
    approval_modes = ["advisory", "dry-run", "operator-approved", "signed-manifest-only"]

    base_records = list(records)
    round_index = 0
    while len(records) < max_records:
        made_progress = False
        for record in base_records:
            if len(records) >= max_records:
                return
            category = next((item for item in record["categories"] if item in symptoms_by_category), "linux")
            symptoms = symptoms_by_category.get(category, ["general Linux maintenance question"])
            distro = distros[round_index % len(distros)]
            symptom = symptoms[round_index % len(symptoms)]
            approval = approval_modes[round_index % len(approval_modes)]
            digest = sha256(f"{record['command']}|{distro}|{symptom}|{approval}")
            if digest in seen:
                continue
            seen.add(digest)
            made_progress = True
            risk = record["risk_level"]
            text = (
                f"Linux scenario knowledge for Neo AI.\n"
                f"Distro/context: {distro}.\n"
                f"Symptom: {symptom}.\n"
                f"Candidate command: {record['command']}.\n"
                f"Risk: {risk}. Execution policy: {record['execution_policy']}.\n"
                f"Approval mode: {approval}.\n"
                f"Safe alternative: {record['safe_alternative']}.\n"
                f"Decision rule: prefer read-only evidence first; if risk is high or deny, explain only and require operator review. Never execute deny records automatically."
            )
            records.append(
                {
                    **record,
                    "id": f"neo-linux-corpus-{len(records) + 1:05d}",
                    "content_sha256": digest,
                    "section": f"{category} scenario :: {symptom}",
                    "keywords": sorted(set(record["keywords"] + re.findall(r"[a-zA-Z0-9_.:/-]{3,}", f"{distro} {symptom} {approval}")))[:24],
                    "scenario": symptom,
                    "distro_context": distro,
                    "approval_mode": approval,
                    "text": text,
                }
            )
        if not made_progress:
            return
        round_index += 1


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="client/knowledge/linux-optimization-corpus.jsonl")
    parser.add_argument("--manifest", default="client/knowledge/linux-optimization-corpus.manifest.json")
    parser.add_argument("--max-records", type=int, default=5000)
    args = parser.parse_args()

    records = build_records(max(1, args.max_records))
    jsonl = "\n".join(json.dumps(record, ensure_ascii=False) for record in records) + "\n"
    out = Path(args.out)
    manifest_path = Path(args.manifest)
    out.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(jsonl, encoding="utf-8")

    risk_counts: dict[str, int] = {}
    category_counts: dict[str, int] = {}
    for record in records:
        risk_counts[record["risk_level"]] = risk_counts.get(record["risk_level"], 0) + 1
        for category in record["categories"]:
            category_counts[category] = category_counts.get(category, 0) + 1

    manifest = {
        "schema_version": "1.0",
        "corpus": "neo-ai-linux-admin",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "record_count": len(records),
        "corpus_sha256": sha256(jsonl),
        "risk_counts": risk_counts,
        "categories": category_counts,
        "policy": {
            "raw_command_corpus": False,
            "auto_execute": False,
            "deny_records_are_for_detection_and_explanation_only": True,
            "requires_signed_manifest_for_write_actions": True,
        },
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Generated {len(records)} Linux corpus records: {out}")
    print(f"Manifest: {manifest_path}")


if __name__ == "__main__":
    main()
