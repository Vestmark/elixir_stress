defmodule ElixirStress.Router do
  use Plug.Router
  require OpenTelemetry.Tracer, as: Tracer

  plug Plug.Parsers, parsers: [:urlencoded]
  plug :match
  plug :dispatch

  get "/" do
    html = """
    <!DOCTYPE html>
    <html>
    <head>
      <title>Elixir Stress</title>
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; max-width: 800px; margin: 40px auto; padding: 0 20px; color: #333; }
        h1 { color: #6e4aad; }
        .test-card { border: 1px solid #ddd; border-radius: 8px; padding: 20px; margin-bottom: 20px; background: #fafafa; }
        .test-card h3 { margin-top: 0; }
        select, button { padding: 8px 16px; font-size: 14px; border-radius: 4px; }
        button { background: #6e4aad; color: white; border: none; cursor: pointer; font-weight: bold; }
        button:hover { background: #5a3d8e; }
        .tooltip-wrap { position: relative; display: inline-block; }
        .tooltip-wrap .tooltip {
          visibility: hidden; opacity: 0;
          position: absolute; z-index: 10; top: 125%; left: 50%; transform: translateX(-50%);
          width: 420px; max-height: 80vh; overflow-y: auto; padding: 16px; background: #1a1a2e; color: #eee; border-radius: 8px;
          font-size: 12px; line-height: 1.4; box-shadow: 0 4px 20px rgba(0,0,0,0.3);
          transition: opacity 0.2s, visibility 0.2s;
        }
        .tooltip-wrap .tooltip::after {
          content: ""; position: absolute; bottom: 100%; left: 50%; margin-left: -8px;
          border-width: 8px; border-style: solid; border-color: transparent transparent #1a1a2e transparent;
        }
        .tooltip-wrap:hover .tooltip { visibility: visible; opacity: 1; }
        .tooltip h4 { margin: 0 0 8px 0; color: #b794f4; font-size: 14px; }
        .tooltip ul { margin: 4px 0; padding-left: 18px; }
        .tooltip li { margin: 2px 0; }
        .tooltip .section { margin-top: 10px; }
        .tooltip .section-title { color: #f6ad55; font-weight: bold; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; }
        .info-icon { display: inline-block; width: 20px; height: 20px; background: #6e4aad; color: white; border-radius: 50%; text-align: center; line-height: 20px; font-size: 12px; font-weight: bold; cursor: help; margin-left: 6px; vertical-align: middle; }
        .links { margin-top: 30px; padding-top: 15px; border-top: 1px solid #ddd; }
        .links a { color: #6e4aad; text-decoration: none; font-weight: 500; }
        .links a:hover { text-decoration: underline; }
        .duration-info { font-size: 12px; color: #888; margin-top: 4px; }
      </style>
    </head>
    <body>
      <h1>Elixir Stress Test</h1>

      <div class="test-card">
        <h3>
          Full Stress Test
          <span class="tooltip-wrap">
            <span class="info-icon">i</span>
            <span class="tooltip">
              <h4>Full Stress Test</h4>
              <ul>
                <li><b>10x Memory hogs</b> (hold tens to hundreds of MB each)</li>
                <li><b>CPU saturate</b> (2x schedulers — primes, sorting, hashing, fibonacci, matrix multiply)</li>
                <li><b>4x Disk I/O thrash</b> (write/read/hash 20-100MB files)</li>
                <li><b>2x Process explosion</b> (up to 20k live processes)</li>
                <li><b>2x ETS bloat</b> (50k row inserts, full table scans)</li>
                <li><b>4x GC torture</b> (massive garbage + forced collection)</li>
                <li><b>4x Binary heap abuse</b> (2-8MB binaries shared across processes)</li>
                <li><b>2x Message queue pressure</b> (10k messages flooding slow consumers)</li>
                <li><b>2x Port churn</b> (open/pump/close 20-60 ports)</li>
                <li><b>Atom growth</b> (500-1000 atoms per batch)</li>
              </ul>
              <div class="section">
                <span class="section-title">OTel Pipeline Stress (Tier 4)</span>
                <ul>
                  <li><b>2x Span flood</b> (thousands of micro-spans/sec)</li>
                  <li><b>2x High cardinality</b> (unique attribute values stress Tempo indexing)</li>
                  <li><b>Large payloads</b> (spans with massive event data)</li>
                  <li><b>Metric flood</b> (thousands of telemetry events/sec)</li>
                  <li><b>Log flood</b> (structured logs flooding Loki)</li>
                </ul>
              </div>
              <div class="section">
                <span class="section-title">Distributed Tracing (Tier 5)</span>
                <ul>
                  <li><b>2x Distributed callers</b> (HTTP calls to worker service on :4003 with W3C traceparent propagation)</li>
                  <li>Worker service endpoints: compute, store, transform — each with nested child spans</li>
                </ul>
              </div>
            </span>
          </span>
        </h3>
        <form action="/stress" method="post">
          <select name="duration" id="duration-select">
            <option value="15">15 seconds</option>
            <option value="30" selected>30 seconds</option>
            <option value="60">60 seconds</option>
            <option value="120">2 minutes</option>
          </select>
          <span class="tooltip-wrap">
            <span class="info-icon">?</span>
            <span class="tooltip" style="width: 300px;">
              <h4>Duration Guide</h4>
              <ul>
                <li><b>15s</b> — Quick smoke test. Workers start but many only complete 1-2 cycles.</li>
                <li><b>30s</b> — Good default. Enough time to see patterns in Grafana.</li>
                <li><b>60s</b> — Full soak. Memory sawtooth and atom growth become clearly visible.</li>
                <li><b>120s</b> — Extended run. Process explosion hits 20k cap, ETS tables grow large, atom count climbs significantly.</li>
              </ul>
            </span>
          </span>
          <br><br>
          <button type="submit">Run Full Stress Test</button>
        </form>
      </div>

      <div class="test-card">
        <h3>
          Quick Burn
          <span class="tooltip-wrap">
            <span class="info-icon">i</span>
            <span class="tooltip" style="width: 320px;">
              <h4>Quick Burn — lightweight CPU + memory spike</h4>
              <ul>
                <li>Spawns <b>10 processes</b></li>
                <li>Each builds a <b>500k element list</b></li>
                <li>Sums the list <b>20 times</b></li>
                <li>Visible as a brief spike in CPU run queues and process memory</li>
                <li>Completes in ~2-5 seconds</li>
              </ul>
              <p style="margin-top:8px;color:#aaa;">Good for verifying dashboards are working without running the full stress suite.</p>
            </span>
          </span>
        </h3>
        <form action="/burn" method="post">
          <button type="submit">Run Quick Burn</button>
        </form>
      </div>

      <div class="links">
        <a href="http://localhost:4002/dashboard" target="_blank">Phoenix LiveDashboard</a> &nbsp;|&nbsp;
        <a href="http://localhost:3404/d/elixir-stress-test" target="_blank">Grafana: Stress Test</a> &nbsp;|&nbsp;
        <a href="http://localhost:3404/d/elixir-app-metrics" target="_blank">Grafana: App Metrics</a>
      </div>
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  get "/metrics" do
    metrics = ElixirStress.PromMetrics.scrape()

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, metrics)
  end

  post "/stress" do
    duration = String.to_integer(conn.body_params["duration"] || "30")

    Tracer.with_span "stress_test.trigger", attributes: %{duration: duration} do
      :telemetry.execute([:elixir_stress, :run, :start], %{}, %{duration: duration})
      spawn(fn -> ElixirStress.Stress.run(duration) end)
    end

    html = """
    <!DOCTYPE html>
    <html>
    <head>
      <title>Stress Test Running</title>
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; max-width: 800px; margin: 40px auto; padding: 0 20px; color: #333; }
        h1 { color: #6e4aad; }
        #timer { font-size: 72px; font-weight: bold; color: #6e4aad; font-variant-numeric: tabular-nums; margin: 20px 0; }
        .links { margin-top: 30px; padding-top: 15px; border-top: 1px solid #ddd; }
        .links a { color: #6e4aad; text-decoration: none; font-weight: 500; }
        .links a:hover { text-decoration: underline; }
      </style>
    </head>
    <body>
      <h1>Full Stress Test</h1>
      <div id="timer">#{duration}</div>
      <div class="links">
        <a href="http://localhost:4002/dashboard" target="_blank">Phoenix LiveDashboard</a> &nbsp;|&nbsp;
        <a href="http://localhost:3404/d/elixir-stress-test" target="_blank">Grafana: Stress Test</a> &nbsp;|&nbsp;
        <a href="http://localhost:3404/d/elixir-app-metrics" target="_blank">Grafana: App Metrics</a> &nbsp;|&nbsp;
        <a href="/">Go back</a>
      </div>
      <script>
        var remaining = #{duration};
        var el = document.getElementById('timer');
        var interval = setInterval(function() {
          remaining--;
          if (remaining <= 0) { remaining = 0; clearInterval(interval); }
          el.textContent = remaining;
        }, 1000);
      </script>
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  post "/burn" do
    Tracer.with_span "burn.trigger" do
      for _ <- 1..10 do
        spawn(fn ->
          list = Enum.to_list(1..500_000)
          Enum.each(1..20, fn _ -> Enum.sum(list) end)
        end)
      end
    end

    html = """
    <!DOCTYPE html>
    <html>
    <head>
      <title>Quick Burn</title>
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; max-width: 800px; margin: 40px auto; padding: 0 20px; color: #333; }
        h1 { color: #6e4aad; }
        #timer { font-size: 72px; font-weight: bold; color: #6e4aad; font-variant-numeric: tabular-nums; margin: 20px 0; }
        .links { margin-top: 30px; padding-top: 15px; border-top: 1px solid #ddd; }
        .links a { color: #6e4aad; text-decoration: none; font-weight: 500; }
        .links a:hover { text-decoration: underline; }
      </style>
    </head>
    <body>
      <h1>Quick Burn</h1>
      <div id="timer">5</div>
      <div class="links">
        <a href="http://localhost:4002/dashboard" target="_blank">Phoenix LiveDashboard</a> &nbsp;|&nbsp;
        <a href="http://localhost:3404/d/elixir-stress-test" target="_blank">Grafana: Stress Test</a> &nbsp;|&nbsp;
        <a href="/">Go back</a>
      </div>
      <script>
        var remaining = 5;
        var el = document.getElementById('timer');
        var interval = setInterval(function() {
          remaining--;
          if (remaining <= 0) { remaining = 0; clearInterval(interval); }
          el.textContent = remaining;
        }, 1000);
      </script>
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
