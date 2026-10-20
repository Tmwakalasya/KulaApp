"""Exercise the real local HTTP boundary, including failure and shutdown paths."""

import concurrent.futures
import json
import os
from pathlib import Path
import signal
import subprocess
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
BASE = "http://127.0.0.1:8087"


def request(path, method="GET", payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    headers = {"Content-Type": "application/json"} if data is not None else {}
    req = urllib.request.Request(BASE + path, method=method, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=3) as response:
            return response.status, response.headers, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.headers, error.read()


# CI and local smoke checks must never use a real credential or call Google.
environment = dict(os.environ)
environment.pop("GOOGLE_MAPS_API_KEY", None)
environment.pop("GOOGLE_MAPS_API_KEY_FILE", None)
process = subprocess.Popen([str(ROOT / ".build/kula-api")], env=environment)
try:
    # Startup polling has a deadline; failures after readiness are never retried.
    deadline = time.monotonic() + 5
    while True:
        if process.poll() is not None:
            raise RuntimeError("The test API exited; check whether port 8087 is occupied.")
        try:
            status, _, _ = request("/healthz")
            if status == 200:
                time.sleep(0.1)
                if process.poll() is not None:
                    raise RuntimeError("The test API could not bind port 8087.")
                break
        except urllib.error.URLError:
            pass
        if time.monotonic() >= deadline:
            raise RuntimeError("API did not become ready within five seconds.")
        time.sleep(0.05)

    status, headers, body = request("/v1/restaurants")
    assert status == 200
    assert headers.get_content_type() == "application/json"
    restaurants = json.loads(body)["restaurants"]
    assert restaurants and len({r["id"] for r in restaurants}) == len(restaurants)
    assert {r["area"] for r in restaurants} == {"Oyster Bay", "Masaki"}
    for restaurant in restaurants:
        status, _, detail = request("/v1/restaurants/" + restaurant["id"])
        assert status == 200 and json.loads(detail) == restaurant
        assert restaurant["menu"]
        for item in restaurant["menu"]:
            assert type(item["price_tzs"]) is int and item["price_tzs"] > 0

    assert request("/v1/restaurants/does-not-exist")[0] == 404
    assert request("/v1/restaurants", method="POST")[0] == 405
    assert request("/not-a-route")[0] == 404
    quote_request = {
        "restaurant_id": "kivuli-kitchen",
        "items": [{"menu_item_id": "beef-pilau", "quantity": 2}],
    }
    status, headers, quote_body = request("/v1/quotes", "POST", quote_request)
    quote = json.loads(quote_body)
    assert status == 200 and quote["subtotal_tzs"] == 28000 and quote["demo"] is True
    assert headers["Cache-Control"] == "no-store"
    quote_request["items"][0]["price_tzs"] = 1
    assert request("/v1/quotes", "POST", quote_request)[0] == 400
    assert request("/v1/discovery/restaurants")[0] == 503
    print("PASS: server quote, price tampering rejected, discovery disabled without key")

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        responses = list(pool.map(lambda _: request("/v1/restaurants"), range(32)))
    assert all(status == 200 and data == body for status, _, data in responses)
    print("PASS: catalog, menu details, integer prices, 404/405, and concurrent reads")
finally:
    if process.poll() is None:
        process.send_signal(signal.SIGTERM)
        try:
            process.wait(timeout=7)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
            raise RuntimeError("API did not shut down within seven seconds.")

assert process.returncode == 0, f"API exited with {process.returncode}"
print("PASS: graceful shutdown")
