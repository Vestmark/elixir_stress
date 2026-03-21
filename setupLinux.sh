#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Elixir Stress Test — Linux Setup Script
# ============================================================
# Installs all prerequisites and starts the complete stack:
#   - Erlang + Elixir (via apt/dnf or asdf)
#   - Docker Engine check
#   - Grafana LGTM stack (Docker)
#   - Elixir dependencies
#   - Application (ports 4001, 4002, 4003)
#
# Supports: Ubuntu/Debian, Fedora/RHEL/CentOS, and any distro
#           with asdf already installed.
#
# Usage:
#   ./setupLinux.sh           # Full install + start
#   ./setupLinux.sh --start   # Skip install, just start services
#   ./setupLinux.sh --stop    # Stop everything
#   ./setupLinux.sh --status  # Check what's running
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}▸${NC} $1"; }
ok()    { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}!${NC} $1"; }
fail()  { echo -e "${RED}✗${NC} $1"; }

# Detect package manager
detect_pkg_manager() {
  if command -v apt-get &>/dev/null; then
    echo "apt"
  elif command -v dnf &>/dev/null; then
    echo "dnf"
  elif command -v yum &>/dev/null; then
    echo "yum"
  else
    echo "unknown"
  fi
}

# ============================================================
# --stop: Kill everything
# ============================================================
if [[ "${1:-}" == "--stop" ]]; then
  info "Stopping Elixir app..."
  for port in 4001 4002 4003; do
    pids=$(lsof -ti:"$port" 2>/dev/null || ss -tlnp "sport = :$port" 2>/dev/null | grep -oP 'pid=\K[0-9]+' || true)
    if [[ -n "$pids" ]]; then
      echo "$pids" | xargs kill -9 2>/dev/null || true
      ok "Killed processes on port $port"
    fi
  done

  info "Stopping Docker containers..."
  docker compose down 2>/dev/null && ok "Docker containers stopped" || warn "No containers running"
  exit 0
fi

# ============================================================
# --status: Show what's running
# ============================================================
if [[ "${1:-}" == "--status" ]]; then
  echo ""
  echo "=== Services ==="
  for port in 4001 4002 4003; do
    if (lsof -ti:"$port" || ss -tlnp "sport = :$port" | grep -q LISTEN) &>/dev/null; then
      ok "Port $port — running"
    else
      fail "Port $port — not running"
    fi
  done

  echo ""
  echo "=== Docker ==="
  if docker compose ps 2>/dev/null | grep -q "running\|Up"; then
    docker compose ps 2>/dev/null
  else
    fail "LGTM container not running"
  fi

  echo ""
  echo "=== URLs ==="
  echo "  Web UI:           http://localhost:4001"
  echo "  LiveDashboard:    http://localhost:4002/dashboard"
  echo "  Grafana:          http://localhost:3404  (admin/admin)"
  echo "  Stress Dashboard: http://localhost:3404/d/elixir-stress-test"
  echo "  App Metrics:      http://localhost:3404/d/elixir-app-metrics"
  exit 0
fi

# ============================================================
# Header
# ============================================================
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║    Elixir Stress Test — Linux Setup          ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

SKIP_INSTALL=false
if [[ "${1:-}" == "--start" ]]; then
  SKIP_INSTALL=true
fi

# ============================================================
# Step 1: Check / Install prerequisites
# ============================================================
if [[ "$SKIP_INSTALL" == false ]]; then
  info "Checking prerequisites..."
  echo ""
  PKG=$(detect_pkg_manager)

  # --- Build tools ---
  if [[ "$PKG" == "apt" ]]; then
    info "Ensuring build tools are installed (apt)..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq curl git build-essential autoconf m4 libncurses5-dev \
      libwxgtk3.2-dev libwxgtk-webview3.2-dev libgl1-mesa-dev libglu1-mesa-dev \
      libpng-dev libssh-dev unixodbc-dev xsltproc fop libxml2-utils libssl-dev \
      lsof >/dev/null 2>&1
    ok "Build tools installed"
  elif [[ "$PKG" == "dnf" || "$PKG" == "yum" ]]; then
    info "Ensuring build tools are installed ($PKG)..."
    sudo $PKG groupinstall -y "Development Tools" >/dev/null 2>&1 || true
    sudo $PKG install -y curl git autoconf ncurses-devel openssl-devel \
      wxGTK3-devel lsof >/dev/null 2>&1
    ok "Build tools installed"
  fi

  # --- Erlang ---
  if command -v erl &>/dev/null; then
    erl_version=$(erl -eval 'io:format("~s", [erlang:system_info(otp_release)]), halt().' -noshell 2>/dev/null || echo "unknown")
    ok "Erlang/OTP $erl_version installed"
  else
    if command -v asdf &>/dev/null; then
      info "Installing Erlang via asdf..."
      asdf plugin add erlang 2>/dev/null || true
      asdf install erlang latest
      asdf global erlang latest
      ok "Erlang installed via asdf"
    elif [[ "$PKG" == "apt" ]]; then
      info "Installing Erlang via apt..."
      sudo apt-get install -y -qq erlang >/dev/null 2>&1
      ok "Erlang installed"
    elif [[ "$PKG" == "dnf" || "$PKG" == "yum" ]]; then
      info "Installing Erlang via $PKG..."
      sudo $PKG install -y erlang >/dev/null 2>&1
      ok "Erlang installed"
    else
      fail "Cannot install Erlang automatically. Please install manually."
      echo "  See: https://www.erlang.org/downloads"
      exit 1
    fi
  fi

  # --- Elixir ---
  if command -v elixir &>/dev/null; then
    elixir_version=$(elixir --version 2>/dev/null | grep "Elixir" | awk '{print $2}')
    ok "Elixir $elixir_version installed"
  else
    if command -v asdf &>/dev/null; then
      info "Installing Elixir via asdf..."
      asdf plugin add elixir 2>/dev/null || true
      asdf install elixir latest
      asdf global elixir latest
      ok "Elixir installed via asdf"
    elif [[ "$PKG" == "apt" ]]; then
      info "Installing Elixir via apt..."
      sudo apt-get install -y -qq elixir >/dev/null 2>&1
      ok "Elixir installed"
    elif [[ "$PKG" == "dnf" || "$PKG" == "yum" ]]; then
      info "Installing Elixir via $PKG..."
      sudo $PKG install -y elixir >/dev/null 2>&1
      ok "Elixir installed"
    else
      fail "Cannot install Elixir automatically. Please install manually."
      echo "  See: https://elixir-lang.org/install.html"
      exit 1
    fi
  fi

  # --- Docker ---
  if command -v docker &>/dev/null; then
    ok "Docker installed"
  else
    info "Docker not found. Attempting to install Docker Engine..."
    if [[ "$PKG" == "apt" ]]; then
      # Docker official convenience script
      curl -fsSL https://get.docker.com | sudo sh
      sudo usermod -aG docker "$USER" 2>/dev/null || true
      ok "Docker installed. You may need to log out/in for group changes."
    elif [[ "$PKG" == "dnf" || "$PKG" == "yum" ]]; then
      sudo $PKG install -y dnf-plugins-core 2>/dev/null || true
      sudo $PKG config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null || \
        sudo $PKG config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null || true
      sudo $PKG install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
      sudo systemctl start docker
      sudo systemctl enable docker
      sudo usermod -aG docker "$USER" 2>/dev/null || true
      ok "Docker installed"
    else
      fail "Cannot install Docker automatically."
      echo "  See: https://docs.docker.com/engine/install/"
      exit 1
    fi
  fi

  # --- docker compose plugin ---
  if docker compose version &>/dev/null; then
    ok "Docker Compose plugin available"
  else
    warn "Docker Compose plugin not found. Installing..."
    sudo mkdir -p /usr/local/lib/docker/cli-plugins
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    sudo curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-$(uname -m)" \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    ok "Docker Compose plugin installed"
  fi

  echo ""
fi

# ============================================================
# Step 2: Check Docker is running
# ============================================================
info "Checking Docker daemon..."
if docker info &>/dev/null; then
  ok "Docker is running"
else
  fail "Docker daemon is not running"
  info "Attempting to start Docker..."
  sudo systemctl start docker 2>/dev/null || sudo service docker start 2>/dev/null || true
  sleep 3
  if docker info &>/dev/null; then
    ok "Docker is now running"
  else
    fail "Could not start Docker. Please start it manually:"
    echo "  sudo systemctl start docker"
    exit 1
  fi
fi

# ============================================================
# Step 3: Handle corporate TLS proxy (Zscaler)
# ============================================================
if [[ "$SKIP_INSTALL" == false ]]; then
  # Check for Zscaler cert in common locations
  if find /usr/local/share/ca-certificates /etc/pki/ca-trust/source/anchors -name "*scaler*" -o -name "*Zscaler*" 2>/dev/null | grep -qi scaler; then
    warn "Zscaler TLS proxy detected"
    # On Linux the system CA bundle is usually already updated via update-ca-certificates
    # but Hex/Erlang may need an explicit path
    CA_BUNDLE=""
    for path in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/certs/ca-bundle.crt; do
      if [[ -f "$path" ]]; then
        CA_BUNDLE="$path"
        break
      fi
    done
    if [[ -n "$CA_BUNDLE" ]]; then
      export HEX_CACERTS_PATH="$CA_BUNDLE"
      ok "HEX_CACERTS_PATH set to $CA_BUNDLE"
    fi
  fi
fi

# ============================================================
# Step 4: Install Elixir dependencies
# ============================================================
if [[ "$SKIP_INSTALL" == false ]]; then
  echo ""
  info "Installing Elixir dependencies..."
  mix local.hex --force --if-missing >/dev/null 2>&1
  mix local.rebar --force --if-missing >/dev/null 2>&1
  mix deps.get
  ok "Dependencies installed"

  info "Compiling..."
  mix compile
  ok "Compilation complete"
  echo ""
fi

# ============================================================
# Step 5: Start Grafana LGTM stack
# ============================================================
info "Starting Grafana LGTM stack (Docker)..."
docker compose up -d
echo "  Waiting for Grafana to become healthy..."
for i in $(seq 1 60); do
  if curl -sf http://localhost:3404/api/health &>/dev/null; then
    break
  fi
  sleep 1
  printf "."
done
echo ""

if curl -sf http://localhost:3404/api/health &>/dev/null; then
  ok "Grafana LGTM stack is healthy"
else
  fail "Grafana did not become healthy in 60s. Check: docker compose logs"
  exit 1
fi

# ============================================================
# Step 6: Kill any existing Elixir processes on our ports
# ============================================================
for port in 4001 4002 4003; do
  pids=$(lsof -ti:"$port" 2>/dev/null || ss -tlnp "sport = :$port" 2>/dev/null | grep -oP 'pid=\K[0-9]+' || true)
  if [[ -n "$pids" ]]; then
    warn "Port $port already in use — killing existing processes"
    echo "$pids" | xargs kill -9 2>/dev/null || true
    sleep 1
  fi
done

# ============================================================
# Step 7: Start Elixir application
# ============================================================
echo ""
info "Starting Elixir application..."
mix run --no-halt > /tmp/elixir_stress.log 2>&1 &
APP_PID=$!
echo "  PID: $APP_PID (log: /tmp/elixir_stress.log)"

# Wait for app to be ready
for i in $(seq 1 30); do
  if curl -sf http://localhost:4001/ &>/dev/null; then
    break
  fi
  sleep 1
  printf "."
done
echo ""

if curl -sf http://localhost:4001/ &>/dev/null; then
  ok "Elixir app is running"
else
  fail "App did not start. Check /tmp/elixir_stress.log"
  exit 1
fi

# ============================================================
# Done
# ============================================================
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║              All systems go!                 ║"
echo "╠══════════════════════════════════════════════╣"
echo "║                                              ║"
echo "║  Web UI        http://localhost:4001          ║"
echo "║  LiveDashboard http://localhost:4002/dashboard║"
echo "║  Grafana       http://localhost:3404          ║"
echo "║                (admin / admin)                ║"
echo "║                                              ║"
echo "║  Dashboards:                                  ║"
echo "║  ▸ /d/elixir-stress-test                     ║"
echo "║  ▸ /d/elixir-app-metrics                     ║"
echo "║                                              ║"
echo "║  Stop:   ./setupLinux.sh --stop              ║"
echo "║  Status: ./setupLinux.sh --status            ║"
echo "║                                              ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# Open browser if available
if command -v xdg-open &>/dev/null; then
  xdg-open http://localhost:4001 2>/dev/null || true
fi
