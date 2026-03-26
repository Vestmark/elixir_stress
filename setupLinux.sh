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
  NEED_ELIXIR_UPGRADE=false
  if command -v elixir &>/dev/null; then
    elixir_version=$(elixir --version 2>/dev/null | grep "Elixir" | awk '{print $2}')
    # Extract major and minor version numbers
    major_version=$(echo "$elixir_version" | cut -d. -f1)
    minor_version=$(echo "$elixir_version" | cut -d. -f2)
    # Check if version is >= 1.19
    if [[ "$major_version" -lt 1 ]] || [[ "$major_version" -eq 1 && "$minor_version" -lt 19 ]]; then
      warn "Elixir $elixir_version is too old (need >= 1.19)"
      NEED_ELIXIR_UPGRADE=true
    else
      ok "Elixir $elixir_version installed"
    fi
  else
    NEED_ELIXIR_UPGRADE=true
  fi

  if [[ "$NEED_ELIXIR_UPGRADE" == true ]]; then
    # Ensure asdf is installed
    if ! command -v asdf &>/dev/null; then
      warn "Elixir 1.19+ not available in system repos. Installing asdf..."
      if [[ ! -d "$HOME/.asdf" ]]; then
        git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0 2>&1 | tail -3
        echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc
        echo '. "$HOME/.asdf/completions/asdf.bash"' >> ~/.bashrc
        ok "asdf installed"
      fi
      # Source asdf in current shell
      source "$HOME/.asdf/asdf.sh"
    fi

    # Check Erlang/OTP version - Elixir 1.19+ requires OTP 26+
    if command -v erl &>/dev/null; then
      otp_version=$(erl -eval 'io:format("~s", [erlang:system_info(otp_release)]), halt().' -noshell 2>/dev/null || echo "0")
      if [[ "$otp_version" -lt 26 ]]; then
        warn "Elixir 1.19+ requires Erlang/OTP 26+, but you have OTP $otp_version"
        info "Installing Erlang/OTP 27 via asdf..."
        asdf plugin add erlang 2>/dev/null || true
        asdf install erlang 27.2 2>&1 | tail -5
        asdf global erlang 27.2
        export PATH="$HOME/.asdf/shims:$PATH"
        ok "Erlang/OTP 27 installed via asdf"
      fi
    fi

    info "Installing Elixir 1.19+ via asdf..."
    asdf plugin add elixir 2>/dev/null || true

    # Install latest Elixir 1.19.x for OTP 27
    info "Fetching and installing Elixir 1.19.5-otp-27..."
    asdf install elixir 1.19.5-otp-27 2>&1 | tail -10
    asdf global elixir 1.19.5-otp-27

    # Ensure asdf shims are in PATH for this script
    export PATH="$HOME/.asdf/shims:$PATH"

    # Verify installation
    if command -v elixir &>/dev/null; then
      new_version=$(elixir --version 2>/dev/null | grep "Elixir" | awk '{print $2}')
      ok "Elixir $new_version installed via asdf"
    else
      fail "Elixir installation failed"
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
  fail "Docker daemon is not accessible"

  # Check if we're using Docker Desktop context but it's not running
  CURRENT_CONTEXT=$(docker context show 2>/dev/null || echo "default")
  if [[ "$CURRENT_CONTEXT" == "desktop-linux" ]] && [[ -f "$HOME/.docker/desktop/docker.sock" ]]; then
    warn "Docker context is set to Docker Desktop, but it's not running"
    info "Switching to native Docker Engine..."
    docker context use default &>/dev/null || true

    # Check if default context works
    if docker info &>/dev/null; then
      ok "Switched to native Docker Engine"
    fi
  fi

  # If still not working, try to start native Docker Engine
  if ! docker info &>/dev/null; then
    info "Attempting to start Docker Engine (you may be prompted for your password)..."
    if sudo systemctl start docker 2>&1; then
      sleep 3
      if docker info &>/dev/null; then
        ok "Docker is now running"
      else
        warn "Docker service started but daemon not responding yet"
        info "Waiting for Docker daemon to be ready..."
        for i in $(seq 1 10); do
          sleep 1
          if docker info &>/dev/null; then
            ok "Docker is now running"
            break
          fi
        done
        if ! docker info &>/dev/null; then
          fail "Docker daemon still not responding"
          echo "  This might be a permissions issue. Try:"
          echo "  1. Log out and log back in (to refresh group membership)"
          echo "  2. Or run: newgrp docker"
          echo "  3. Then try the script again"
          exit 1
        fi
      fi
    elif sudo service docker start 2>&1; then
      sleep 3
      if docker info &>/dev/null; then
        ok "Docker is now running"
      else
        fail "Could not communicate with Docker daemon"
        echo "  Try: sudo systemctl status docker"
        exit 1
      fi
    else
      fail "Could not start Docker. Please start it manually:"
      echo "  sudo systemctl start docker"
      echo "  or"
      echo "  sudo service docker start"
      exit 1
    fi
  fi
fi

# ============================================================
# Step 3: Handle corporate TLS proxy (Zscaler)
# ============================================================
if [[ "$SKIP_INSTALL" == false ]]; then
  # Check for Zscaler cert in common locations
  ZSCALER_FOUND=false
  for dir in /usr/local/share/ca-certificates /etc/pki/ca-trust/source/anchors /etc/ssl/certs; do
    if [[ -d "$dir" ]] && find "$dir" -maxdepth 1 -iname "*zscaler*" 2>/dev/null | grep -q .; then
      ZSCALER_FOUND=true
      break
    fi
  done

  if [[ "$ZSCALER_FOUND" == true ]]; then
    warn "Zscaler TLS proxy detected"

    # Find system CA bundle
    CA_BUNDLE=""
    for path in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/certs/ca-bundle.crt; do
      if [[ -f "$path" ]]; then
        CA_BUNDLE="$path"
        break
      fi
    done

    if [[ -n "$CA_BUNDLE" ]]; then
      # Export multiple SSL-related environment variables for Erlang/Hex
      export HEX_CACERTS_PATH="$CA_BUNDLE"
      export HEX_UNSAFE_HTTPS="1"
      export SSL_CERT_FILE="$CA_BUNDLE"
      export CURL_CA_BUNDLE="$CA_BUNDLE"
      ok "SSL certificates configured for Zscaler"
      ok "  HEX_CACERTS_PATH=$CA_BUNDLE"
      ok "  HEX_UNSAFE_HTTPS=1"
    else
      fail "Could not find system CA bundle"
      echo "  You may need to manually set HEX_CACERTS_PATH"
      exit 1
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
