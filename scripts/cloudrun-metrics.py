#!/usr/bin/env python3
"""
Cloud Run resource utilization report for ksef-hub.

Queries Google Cloud Monitoring API for CPU, memory, instance count,
and billable time per container (ksef-hub + sidecars).

Prerequisites:
  - gcloud CLI authenticated (gcloud auth login)
  - Access to project au-ksef-ex

Usage:
  scripts/cloudrun-metrics.py                  # last 7 days
  scripts/cloudrun-metrics.py 1                # last 1 day
  scripts/cloudrun-metrics.py 30               # last 30 days
  scripts/cloudrun-metrics.py 7 --csv          # append to CSV log
  scripts/cloudrun-metrics.py 7 --json         # output raw JSON
"""

import json
import subprocess
import sys
import urllib.parse
from datetime import datetime, timedelta, timezone

PROJECT_ID = "au-ksef-ex"
SERVICE_NAME = "ksef-hub"
BASE_URL = f"https://monitoring.googleapis.com/v3/projects/{PROJECT_ID}/timeSeries"

# Resource allocations from cloud-run/service.yaml
ALLOCATIONS = {
    "ksef-hub":             {"cpu": 1.0, "mem_mb": 384},
    "pdf-renderer":         {"cpu": 0.5, "mem_mb": 128},
    "invoice-extractor":    {"cpu": 0.5, "mem_mb": 320},
    "invoice-classifier":   {"cpu": 0.5, "mem_mb": 256},
}
TOTAL_CPU = sum(a["cpu"] for a in ALLOCATIONS.values())
TOTAL_MEM_MB = sum(a["mem_mb"] for a in ALLOCATIONS.values())

# Cloud Run gen2 pricing (europe-west1, request-based)
# Source: https://cloud.google.com/run/pricing (retrieved 2026-04-22)
VCPU_PER_SEC = 0.00002400
MEM_PER_GIB_SEC = 0.00000250

CONTAINER_ORDER = ["ksef-hub", "invoice-extractor", "invoice-classifier", "pdf-renderer"]


def _run_gcloud(args):
    """Run a gcloud command, raising a clear error if gcloud is missing."""
    try:
        return subprocess.run(
            ["gcloud", *args],
            capture_output=True, text=True, check=True,
        )
    except FileNotFoundError:
        print("Error: gcloud CLI not found in PATH.", file=sys.stderr)
        print("Install it from https://cloud.google.com/sdk/docs/install", file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"Error running gcloud {' '.join(args)}:", file=sys.stderr)
        print(e.stderr.strip(), file=sys.stderr)
        sys.exit(1)


def ensure_project():
    """Set gcloud project to PROJECT_ID if not already active."""
    result = _run_gcloud(["config", "get-value", "project"])
    current = result.stdout.strip()
    if current != PROJECT_ID:
        print(f"Switching gcloud project: {current} -> {PROJECT_ID}")
        _run_gcloud(["config", "set", "project", PROJECT_ID])


def get_token():
    result = _run_gcloud(["auth", "print-access-token"])
    return result.stdout.strip()


def query_monitoring(token, metric_type, aligner, reducer=None, group_by=None, alignment_period="86400s", start=None, end=None):
    filt = f'metric.type="{metric_type}" AND resource.labels.service_name="{SERVICE_NAME}"'
    params = {
        "filter": filt,
        "interval.startTime": start,
        "interval.endTime": end,
        "aggregation.alignmentPeriod": alignment_period,
        "aggregation.perSeriesAligner": aligner,
    }
    if group_by:
        params["aggregation.groupByFields"] = group_by
    if reducer:
        params["aggregation.crossSeriesReducer"] = reducer

    url = f"{BASE_URL}?{urllib.parse.urlencode(params)}"
    try:
        resp = subprocess.run(
            ["curl", "-s", "-f", "-H", f"Authorization: Bearer {token}", url],
            capture_output=True, text=True,
            timeout=30,
        )
    except FileNotFoundError:
        print("Error: curl binary not found in PATH.", file=sys.stderr)
        sys.exit(1)
    except subprocess.TimeoutExpired:
        print(f"Error fetching {metric_type}: curl request timed out", file=sys.stderr)
        return {}
    if resp.returncode != 0:
        print(f"Error fetching {metric_type}: curl exited {resp.returncode}", file=sys.stderr)
        print(f"  stderr: {resp.stderr.strip()}", file=sys.stderr)
        return {}
    try:
        return json.loads(resp.stdout)
    except json.JSONDecodeError:
        print(f"Error parsing response for {metric_type}:", file=sys.stderr)
        print(f"  body: {resp.stdout[:200]}", file=sys.stderr)
        return {}


def extract_values(data, label_key=None):
    """Extract {label: [values]} from time series response."""
    results = {}
    for ts in data.get("timeSeries", []):
        if label_key:
            label = ts.get("metric", {}).get("labels", {}).get(label_key, "unknown")
        else:
            label = "_aggregate"
        values = []
        for p in ts.get("points", []):
            v = p["value"]
            val = float(v.get("doubleValue", v.get("int64Value", 0)))
            values.append(val)
        if values:
            results[label] = values
    return results


def fetch_memory(token, start, end):
    """Memory usage per container at p50 and p99."""
    mem = {}
    for pct_name, aligner in [("p50", "ALIGN_PERCENTILE_50"), ("p99", "ALIGN_PERCENTILE_99")]:
        data = query_monitoring(
            token,
            "run.googleapis.com/container/memory/usage",
            aligner,
            reducer="REDUCE_MAX",
            group_by="metric.labels.container_name",
            start=start, end=end,
        )
        for container, values in extract_values(data, "container_name").items():
            if container not in mem:
                mem[container] = {}
            mem[container][pct_name] = max(values)
    return mem


def fetch_cpu_aggregate(token, start, end):
    """CPU utilization (aggregate, all containers) at p50 and p99.

    The utilizations metric has no container_name label, so it returns a single
    aggregated series. We concatenate all series values defensively in case the
    API ever returns multiple series (e.g. across revisions).
    """
    cpu = {}
    for pct_name, aligner in [("p50", "ALIGN_PERCENTILE_50"), ("p99", "ALIGN_PERCENTILE_99")]:
        data = query_monitoring(
            token,
            "run.googleapis.com/container/cpu/utilizations",
            aligner,
            reducer="REDUCE_MAX",
            start=start, end=end,
        )
        all_values = []
        for _, values in extract_values(data).items():
            all_values.extend(values)
        if all_values:
            cpu[f"{pct_name}_avg"] = sum(all_values) / len(all_values)
            cpu[f"{pct_name}_max"] = max(all_values)
    return cpu


def fetch_instances(token, start, end):
    """Instance count by state (active/idle)."""
    data = query_monitoring(
        token,
        "run.googleapis.com/container/instance_count",
        "ALIGN_MAX",
        reducer="REDUCE_SUM",
        group_by="metric.labels.state",
        alignment_period="3600s",
        start=start, end=end,
    )
    instances = {}
    for state, values in extract_values(data, "state").items():
        instances[state] = {"avg": sum(values) / len(values), "max": max(values)}
    return instances


def fetch_billing(token, start, end):
    """Billable instance time in seconds."""
    data = query_monitoring(
        token,
        "run.googleapis.com/container/billable_instance_time",
        "ALIGN_SUM",
        reducer="REDUCE_SUM",
        start=start, end=end,
    )
    daily = []
    for _, values in extract_values(data).items():
        daily.extend(values)
    total = sum(daily)
    return {"daily_seconds": daily, "total_seconds": total}


def print_report(days, mem, cpu, instances, billing):
    total_s = billing["total_seconds"]
    total_h = total_s / 3600
    daily_avg_h = total_h / max(len(billing["daily_seconds"]), 1)

    print()
    print("MEMORY USAGE")
    print("-" * 75)
    print(f"{'Container':<25} {'Limit':>8} {'p50':>8} {'p99':>8} {'p99 %':>8}")
    print("-" * 75)

    sum_limit = 0
    sum_p99 = 0
    for c in CONTAINER_ORDER:
        if c in mem:
            limit = ALLOCATIONS[c]["mem_mb"]
            p50 = mem[c].get("p50", 0) / 1024 / 1024
            p99 = mem[c].get("p99", 0) / 1024 / 1024
            pct = (p99 / limit * 100) if limit else 0
            sum_limit += limit
            sum_p99 += p99
            print(f"  {c:<23} {limit:>5} MB {p50:>5.0f} MB {p99:>5.0f} MB {pct:>5.0f} %")
    print("-" * 75)
    total_pct = (sum_p99 / sum_limit * 100) if sum_limit else 0
    print(f"  {'TOTAL':<23} {sum_limit:>5} MB {'':>8} {sum_p99:>5.0f} MB {total_pct:>5.0f} %")

    print()
    print("CPU UTILIZATION (aggregate, all containers)")
    print("-" * 55)
    print(f"  Total allocated: {TOTAL_CPU} vCPU per instance")
    print(f"  p50 (median):  avg {cpu.get('p50_avg', 0)*100:>5.1f}%  |  peak {cpu.get('p50_max', 0)*100:>5.1f}%")
    print(f"  p99 (spikes):  avg {cpu.get('p99_avg', 0)*100:>5.1f}%  |  peak {cpu.get('p99_max', 0)*100:>5.1f}%")

    print()
    print("INSTANCE COUNT")
    print("-" * 55)
    for state in ["active", "idle"]:
        if state in instances:
            print(f"  {state:<10}  avg: {instances[state]['avg']:>5.2f}  |  max: {instances[state]['max']:>3.0f}")

    print()
    print("BILLABLE INSTANCE TIME")
    print("-" * 55)
    print(f"  Total:       {total_h:>8.1f} hours over {days} days")
    print(f"  Daily avg:   {daily_avg_h:>8.1f} hours/day")

    total_gib = TOTAL_MEM_MB / 1024
    est_vcpu = total_s * TOTAL_CPU * VCPU_PER_SEC
    est_mem = total_s * total_gib * MEM_PER_GIB_SEC
    est_total = est_vcpu + est_mem
    monthly = est_total / days * 30

    print()
    print("COST ESTIMATE (based on billable time)")
    print("-" * 55)
    print(f"  vCPU cost:   ${est_vcpu:>8.2f}  ({TOTAL_CPU} vCPU x {total_h:.0f}h)")
    print(f"  Memory cost: ${est_mem:>8.2f}  ({total_gib:.1f} GiB x {total_h:.0f}h)")
    print(f"  Total:       ${est_total:>8.2f}  (last {days} days)")
    print(f"  Projected:   ${monthly:>8.2f}  /month")
    print()


def write_csv(days, mem, cpu, billing):
    import os
    csv_path = os.path.join(os.path.dirname(__file__), "metrics-log.csv")
    header = "date,days,ksef_hub_mem_p99_mb,extractor_mem_p99_mb,classifier_mem_p99_mb,renderer_mem_p99_mb,cpu_p50_pct,cpu_p99_pct,billable_hours,est_monthly_cost"
    write_header = not os.path.exists(csv_path)

    def mem_mb(container):
        return mem.get(container, {}).get("p99", 0) / 1024 / 1024

    total_s = billing["total_seconds"]
    total_gib = TOTAL_MEM_MB / 1024
    est_total = total_s * (TOTAL_CPU * VCPU_PER_SEC + total_gib * MEM_PER_GIB_SEC)
    monthly = est_total / days * 30

    row = ",".join([
        datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        str(days),
        f"{mem_mb('ksef-hub'):.0f}",
        f"{mem_mb('invoice-extractor'):.0f}",
        f"{mem_mb('invoice-classifier'):.0f}",
        f"{mem_mb('pdf-renderer'):.0f}",
        f"{cpu.get('p50_max', 0)*100:.1f}",
        f"{cpu.get('p99_max', 0)*100:.1f}",
        f"{total_s / 3600:.1f}",
        f"{monthly:.2f}",
    ])

    with open(csv_path, "a") as f:
        if write_header:
            f.write(header + "\n")
        f.write(row + "\n")

    print(f"Appended to {csv_path}")


def write_json(days, mem, cpu, instances, billing):
    output = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "days": days,
        "allocations": ALLOCATIONS,
        "memory": {k: {pk: pv / 1024 / 1024 for pk, pv in v.items()} for k, v in mem.items()},
        "cpu_aggregate": cpu,
        "instances": instances,
        "billing": {
            "total_seconds": billing["total_seconds"],
            "total_hours": billing["total_seconds"] / 3600,
        },
    }
    print(json.dumps(output, indent=2))


def main():
    days = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 7
    if days < 1:
        print(f"Error: days must be >= 1 (got {days})", file=sys.stderr)
        sys.exit(1)
    mode = sys.argv[2] if len(sys.argv) > 2 else ""

    now = datetime.now(timezone.utc)
    end = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    start = (now - timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%SZ")

    print("=" * 60)
    print(f" Cloud Run Resource Report: {SERVICE_NAME}")
    print(f" Period: last {days} day(s)  ({start} -> {end})")
    print("=" * 60)

    ensure_project()
    token = get_token()

    mem = fetch_memory(token, start, end)
    cpu = fetch_cpu_aggregate(token, start, end)
    instances = fetch_instances(token, start, end)
    billing = fetch_billing(token, start, end)

    print_report(days, mem, cpu, instances, billing)

    if mode == "--csv":
        write_csv(days, mem, cpu, billing)
    elif mode == "--json":
        write_json(days, mem, cpu, instances, billing)


if __name__ == "__main__":
    main()
