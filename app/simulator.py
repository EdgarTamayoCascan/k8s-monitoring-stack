"""Monte Carlo Pi estimator.

Throws random darts at a unit circle inscribed in a 2x2 square.
The ratio of hits (inside circle) to total throws converges to pi/4,
giving a running estimate of Pi.

Exposes Prometheus metrics on :8080/metrics and emits structured JSON
logs to stdout for the OTel Collector to pick up.
"""

import http.server
import json
import math
import os
import random
import threading
import time

HOSTNAME = os.environ.get("HOSTNAME", "unknown")

throws_total = 0
hits_total = 0
pi_estimate = 0.0
abs_error = math.pi
last_x = 0.0
last_y = 0.0
last_distance = 0.0
last_hit = False

DIST_BUCKETS = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, float("inf")]
dist_counts = [0] * len(DIST_BUCKETS)


def throw_dart():
    global throws_total, hits_total, pi_estimate, abs_error
    global last_x, last_y, last_distance, last_hit

    x = random.uniform(-1, 1)
    y = random.uniform(-1, 1)
    distance = math.sqrt(x * x + y * y)
    hit = distance <= 1.0

    throws_total += 1
    if hit:
        hits_total += 1

    pi_estimate = 4.0 * hits_total / throws_total
    abs_error = abs(pi_estimate - math.pi)

    last_x, last_y, last_distance, last_hit = x, y, distance, hit

    for i, bound in enumerate(DIST_BUCKETS):
        if distance <= bound:
            dist_counts[i] += 1
            break

    quadrant = (
        "I" if x >= 0 and y >= 0
        else "II" if x < 0 and y >= 0
        else "III" if x < 0 and y < 0
        else "IV"
    )

    log_entry = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "level": "INFO",
        "msg": "dart_throw",
        "x": round(x, 6),
        "y": round(y, 6),
        "distance": round(distance, 6),
        "hit": hit,
        "quadrant": quadrant,
        "throws": throws_total,
        "hits": hits_total,
        "pi_estimate": round(pi_estimate, 8),
        "error": round(abs_error, 8),
        "pod": HOSTNAME,
    }
    print(json.dumps(log_entry), flush=True)

    if throws_total % 100 == 0:
        milestone = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "level": "INFO",
            "msg": "milestone",
            "throws": throws_total,
            "hits": hits_total,
            "hit_rate": round(hits_total / throws_total, 6),
            "pi_estimate": round(pi_estimate, 8),
            "error": round(abs_error, 8),
            "true_pi": round(math.pi, 8),
            "pod": HOSTNAME,
        }
        print(json.dumps(milestone), flush=True)


class MetricsHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            hit_rate = hits_total / throws_total if throws_total > 0 else 0
            lines = [
                "# HELP monte_carlo_throws_total Total darts thrown",
                "# TYPE monte_carlo_throws_total counter",
                f"monte_carlo_throws_total {throws_total}",
                "# HELP monte_carlo_hits_total Darts landing inside the circle",
                "# TYPE monte_carlo_hits_total counter",
                f"monte_carlo_hits_total {hits_total}",
                "# HELP monte_carlo_pi_estimate Current estimate of Pi",
                "# TYPE monte_carlo_pi_estimate gauge",
                f"monte_carlo_pi_estimate {pi_estimate}",
                "# HELP monte_carlo_hit_rate Fraction of darts inside circle",
                "# TYPE monte_carlo_hit_rate gauge",
                f"monte_carlo_hit_rate {hit_rate}",
                "# HELP monte_carlo_error Absolute error from true Pi",
                "# TYPE monte_carlo_error gauge",
                f"monte_carlo_error {abs_error}",
                "# HELP monte_carlo_last_x X coordinate of last throw",
                "# TYPE monte_carlo_last_x gauge",
                f"monte_carlo_last_x {last_x}",
                "# HELP monte_carlo_last_y Y coordinate of last throw",
                "# TYPE monte_carlo_last_y gauge",
                f"monte_carlo_last_y {last_y}",
                "# HELP monte_carlo_last_distance Distance from center of last throw",
                "# TYPE monte_carlo_last_distance gauge",
                f"monte_carlo_last_distance {last_distance}",
                "# HELP monte_carlo_distance_bucket Histogram of throw distances",
                "# TYPE monte_carlo_distance_bucket counter",
            ]
            cumulative = 0
            for i, bound in enumerate(DIST_BUCKETS):
                cumulative += dist_counts[i]
                le = f"{bound}" if bound != float("inf") else "+Inf"
                lines.append(f'monte_carlo_distance_bucket{{le="{le}"}} {cumulative}')

            body = "\n".join(lines) + "\n"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.end_headers()
            self.wfile.write(body.encode())
        elif self.path == "/healthz":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, fmt, *args):
        pass


def serve():
    srv = http.server.HTTPServer(("0.0.0.0", 8080), MetricsHandler)
    srv.serve_forever()


def main():
    threading.Thread(target=serve, daemon=True).start()

    start_msg = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "level": "INFO",
        "msg": "started",
        "description": "Monte Carlo Pi estimator — throwing darts at a unit circle inscribed in a 2x2 square",
        "pod": HOSTNAME,
        "metrics_port": 8080,
    }
    print(json.dumps(start_msg), flush=True)

    while True:
        throw_dart()
        time.sleep(random.uniform(0.5, 2.0))


if __name__ == "__main__":
    main()
