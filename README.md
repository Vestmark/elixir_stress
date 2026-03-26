# Elixir Stress — BEAM + OpenTelemetry Stress Test

A BEAM VM stress testing tool with full observability: Phoenix LiveDashboard, Grafana (Loki, Tempo, Mimir), OpenTelemetry distributed tracing, structured logging, and Prometheus metrics. Exercises memory, CPU, disk, processes, ETS, message passing, ports, GC, and the OTel pipeline itself.

## Prerequisites

- Elixir ~> 1.19
- Erlang/OTP
- Docker (Desktop on macOS, Engine on Linux) for the Grafana LGTM stack

## Automated Setup (Recommended)

Setup scripts install all prerequisites, start Docker/Grafana, compile the app, and open the browser — one command to go from zero to running.

### macOS

```bash
./setupMac.sh
```

Installs (if missing): Homebrew → Erlang → Elixir → Docker Desktop check → Zscaler TLS proxy fix → mix deps → Grafana LGTM → Elixir app.

### Linux (Ubuntu/Debian, Fedora/RHEL/CentOS)

```bash
./setupLinux.sh
```

Installs (if missing): build tools → Erlang → Elixir (via apt/dnf/yum or asdf) → Docker Engine → Docker Compose plugin → Grafana LGTM → Elixir app.

### Script Flags

| Flag | What it does |
|------|-------------|
| *(no flag)* | Full install + start everything |
| `--start` | Skip installs, just start Docker + app |
| `--stop` | Stop Elixir app + docker compose down |
| `--status` | Show what's running and all URLs |

Example:
```bash
./setupMac.sh --status    # Check if everything is up
./setupMac.sh --stop      # Shut it all down
./setupLinux.sh --start   # Quick restart (skip installs)
```

## Manual Setup

If you prefer to set things up step by step:

### 1. Install dependencies

```bash
cd elixir_stress
mix deps.get
mix compile
```

**Note:** If behind a corporate TLS proxy (e.g. Zscaler):

**macOS:**
```bash
security find-certificate -a -p /Library/Keychains/System.keychain \
  /System/Library/Keychains/SystemRootCertificates.keychain > /tmp/all_cas.pem

HEX_CACERTS_PATH=/tmp/all_cas.pem mix deps.get
```

**Linux:**
```bash
export HEX_CACERTS_PATH=/etc/ssl/certs/ca-certificates.crt
export HEX_UNSAFE_HTTPS=1
mix deps.get
```

### 2. Start the Grafana LGTM stack (Docker)

Make sure Docker is running, then:

```bash
docker compose up -d
```

This starts a single container (`grafana/otel-lgtm`) with:
- **Grafana** on port 3404 (dashboards UI)
- **Mimir** on port 9090 (Prometheus-compatible metrics storage)
- **Tempo** on port 4418 (distributed trace storage)
- **Loki** on port 3100 (structured log storage)
- **OTel Collector** on ports 4317 (gRPC) and 4318 (HTTP) — receives traces/metrics/logs from the app and scrapes `/metrics` every 5s

Grafana dashboards are **automatically provisioned** — they load on container start via volume mounts, no manual import needed.

Wait ~10 seconds for the container to become healthy:

```bash
docker compose ps   # should show "healthy"
```

### 3. Start the Elixir application

```bash
mix run --no-halt
```

This starts three HTTP services:

| Port | Service | URL |
|------|---------|-----|
| 4001 | Main web app | http://localhost:4001 |
| 4002 | Phoenix LiveDashboard | http://localhost:4002/dashboard |
| 4003 | Worker service (Tier 5) | http://localhost:4003/work/* |

### 4. Open the dashboards

Grafana dashboards are pre-loaded and available at:

- **http://localhost:3404/d/elixir-stress-test** — BEAM resources, worker activity, traces, logs, OTel pipeline stress
- **http://localhost:3404/d/elixir-app-metrics** — application-level metrics (latency histograms, throughput, gauges)

Login: `admin` / `admin`

### 5. Run a stress test

Go to **http://localhost:4001**, select a duration, and click **Run Full Stress Test**.

Then watch all the panels in Grafana light up in real time.

## Grafana Dashboard Sections

The dashboard at `http://localhost:3404/d/elixir-stress-test/elixir-stress-test` has 6 sections:

### BEAM Resources
- **Memory Usage** — total, process, binary, ETS, atom, system memory over time
- **Run Queue Lengths** — scheduler pressure (CPU, IO, total)
- **Process / Port / Atom Counts** — live system resource gauges

### Worker Activity
- **Worker Cycles (rate/s)** — how fast each worker type is completing cycles
- **Worker Start/Stop Rate** — worker lifecycle events
- **Stress Runs** — total runs started/completed (stat panel)
- **Worker Cycle Totals** — cumulative cycles per worker (bar gauge)

### Distributed Traces (Tempo)
- **Recent Traces** — table of traces from the `elixir_stress` service
- Click any trace to see the full waterfall with nested child spans, span events, and cross-service calls

### Structured Logs (Loki)
- **Application Logs** — live stream of structured logs with trace correlation
- **Log Volume by Severity** — stacked time series of DEBUG/INFO/WARNING/ERROR
- **Error Logs** — filtered view of ERROR-level logs only

### OTel Pipeline Stress (Tier 4)
- **OTel Stress Worker Cycles** — rates for span_flood, high_cardinality, large_payloads, metric_flood, log_flood
- **Metric Flood Events/s** — telemetry event throughput by endpoint

### Distributed Tracing (Tier 5)
- **Distributed Call Cycles** — rate of cross-service HTTP calls
- **Worker Service Logs** — logs from the downstream worker service

## Exploring Traces in Grafana

1. Go to the dashboard or click **Explore** in the sidebar
2. Select **Tempo** as the datasource
3. Search by service name `elixir_stress`
4. Click a trace to open the waterfall view — you'll see:
   - Parent span `stress_test.run` containing all worker spans
   - Per-worker spans like `stress.worker.memory_hog` with child spans per cycle
   - Span events like `allocation`, `gc_forced`, `processes_spawned`
   - Cross-service spans from `distributed.http_call` to `worker_service.compute/store/transform`

## Exploring Logs in Grafana

1. Click **Explore** → select **Loki** datasource
2. Query: `{service_name="elixir_stress"}`
3. Each log entry includes `trace_id` and `span_id` — click the trace link to jump directly to the correlated trace in Tempo

## Architecture

```
                        +------------------+
                        |  Grafana (:3404) |
                        |  Dashboards UI   |
                        +--------+---------+
                                 |
                    +------------+------------+
                    |            |            |
               +----+----+ +----+----+ +-----+-----+
               |  Mimir  | |  Tempo  | |   Loki    |
               | metrics | | traces  | |   logs    |
               | (:9090) | | (:4418) | |  (:3100)  |
               +----+----+ +----+----+ +-----+-----+
                    |            |            |
               +----+------------+------------+----+
               |        OTel Collector             |
               |  OTLP (:4317/:4318)               |
               |  Prometheus scrape (:4001/metrics) |
               +---+-------------------+------------+
                   |                   |
          OTLP traces/logs    Prometheus scrape
                   |                   |
    +--------------+---+        +------+--------+
    | Elixir App       |        | /metrics      |
    | (:4001) main     +--------+ endpoint      |
    | (:4002) dashboard|        | (Prom format) |
    | (:4003) worker   |        +---------------+
    +------------------+
```

## Services Summary

| Port | Service | Purpose |
|------|---------|---------|
| 4001 | Elixir Plug.Cowboy | Web control panel + `/metrics` Prometheus endpoint |
| 4002 | Phoenix Endpoint | LiveDashboard at `/dashboard` |
| 4003 | Worker Service | Downstream microservice for distributed tracing (Tier 5) |
| 3404 | Grafana (Docker) | Dashboards, Explore UI |
| 4317 | OTLP gRPC (Docker) | Receives traces from app |
| 4318 | OTLP HTTP (Docker) | Receives traces/metrics/logs from app |
| 9090 | Mimir (Docker) | Prometheus-compatible metrics DB |
| 3100 | Loki (Docker) | Structured log storage |

## Stress Test Workers

### BEAM Stress (Tier 1 — Deep Tracing)

All workers have per-cycle child spans, span events, error recording, and structured logging.

| Worker | Count | What it does |
|--------|-------|-------------|
| Memory hog | 10 | Hold 50-200MB each with sawtooth pattern, allocating lists/binaries/maps/nested structures |
| CPU saturate | 2x schedulers | Pin all schedulers: fibonacci, sorting, SHA-256 chains, matrix multiply, Ackermann, permutations |
| Disk thrash | 4 | Write/read/hash/delete 20-100MB files per cycle |
| Process explosion | 2 | Spawn 2,000-10,000 processes per cycle, maintain up to 20,000 alive |
| ETS bloat | 2 | 50,000 row inserts, full table scans, concurrent read/write on shared tables |
| GC torture | 4 | Allocate massive garbage + forced GC, spawn 50 sub-processes per cycle |
| Binary abuse | 4 | 2-8MB binaries with sub-binary slices across spawned processes |
| Message queue | 2 | 10,000 messages flooding slow consumers (100ms per message) |
| Port churn | 2 | Open/pump/close 20-60 OS ports per cycle |
| Atom growth | 1 | 500-1,000 unique atoms per batch (never GC'd) |

### OTel Pipeline Stress (Tier 4)

| Worker | Count | What it stresses |
|--------|-------|-----------------|
| Span flood | 2 | Thousands of micro-spans per second — tests batch processor and Tempo ingestion |
| High cardinality | 2 | Unique attribute values per span — tests Tempo indexing |
| Large payloads | 1 | Spans with massive event data — tests OTLP exporter throughput |
| Metric flood | 1 | Thousands of telemetry events per second — tests Prometheus scrape and Mimir writes |
| Log flood | 1 | Structured logs flooding Loki via OTLP HTTP |

### Distributed Tracing (Tier 5)

| Worker | Count | What it does |
|--------|-------|-------------|
| Distributed call | 2 | HTTP calls to worker service (:4003) with W3C `traceparent` header propagation |

The worker service exposes three endpoints, each with nested child spans:
- `POST /work/compute` — fibonacci, sorting, SHA-256 hashing
- `POST /work/store` — ETS insert, scan, cleanup
- `POST /work/transform` — data generation, filtering, aggregation

## Project Structure

```
elixir_stress/
├── config/
│   └── config.exs                 # Phoenix endpoint + OpenTelemetry config
├── grafana/
│   ├── dashboards/                # Provisioned dashboard JSON (auto-loaded by Grafana)
│   │   ├── stress-test-dashboard.json
│   │   └── app-metrics-dashboard.json
│   ├── provisioning/
│   │   └── dashboards/
│   │       └── dashboards.yml     # Grafana provisioning config
│   ├── stress-test-dashboard.json # API-format JSON (for manual import)
│   └── app-metrics-dashboard.json
├── lib/
│   ├── elixir_stress.ex
│   └── elixir_stress/
│       ├── application.ex         # OTP app (starts all services)
│       ├── router.ex              # Main web routes (:4001)
│       ├── endpoint.ex            # Phoenix endpoint for dashboard (:4002)
│       ├── dashboard_router.ex    # LiveDashboard route config
│       ├── telemetry.ex           # Telemetry metrics definitions
│       ├── prom_metrics.ex        # Prometheus metrics exporter
│       ├── otel_logger.ex         # Structured logger -> OTLP HTTP -> Loki
│       ├── otel_stress.ex         # Tier 4: OTel pipeline stress workers
│       ├── worker_service.ex      # Tier 5: Downstream microservice (:4003)
│       └── stress.ex              # Main stress test suite with deep tracing
├── docker-compose.yml             # Grafana LGTM stack (with dashboard provisioning)
├── otel-collector-config.yml      # OTel Collector: receivers, exporters, pipelines
├── setupMac.sh                    # One-command setup for macOS
├── setupLinux.sh                  # One-command setup for Linux
├── mix.exs
└── README.md
```

## Stopping

```bash
# Using setup scripts (recommended)
./setupMac.sh --stop     # macOS
./setupLinux.sh --stop   # Linux

# Or manually
Ctrl+C (twice)           # Stop the Elixir app
docker compose down      # Stop Grafana/LGTM
```
