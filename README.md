# Kula — Dar restaurant discovery and sample cart

A native SwiftUI app and a Go API for the Oyster Bay / Masaki pilot.
**Explore and Saved use fictional restaurants, menus and prices. Nearby shows
live Google Places listings, without menus or ordering.** A sample cart can request
a server-calculated food subtotal. No orders or payments are accepted.

## Run it

Requirements: Go 1.26+, Xcode with an installed iOS simulator, and Python 3 for the
HTTP smoke check. The app and backend have no third-party dependencies; local
Make targets disable dependency and toolchain downloads. CI provisions Go using
GitHub Actions.

1. In Terminal:

   ```sh
   cd path/to/KulaApp
   make api
   ```

2. Open `ios/Kula.xcodeproj` in Xcode.
3. Choose the **Kula** scheme and an installed **iPhone simulator**, then press
   **Command-R**. A signing team is not needed for the simulator.
4. Browse the three sample restaurants, choose a neighbourhood from the header,
   filter by cuisine, or search for a restaurant or dish. Tap a restaurant to
   fetch its menu, or a heart to keep it in **Saved**. Add dishes, open **Cart**,
   and tap **Get fresh food quote**. Pull down to refresh menus.

For live **Nearby** listings, enable Places API (New) and billing in your Google
Cloud project. Save your key in a private file outside this repository (file
permissions `600`), stop the existing API, then run:

```sh
GOOGLE_MAPS_API_KEY_FILE="$HOME/.config/kula/google-places-key" make api
```

`GOOGLE_MAPS_API_KEY` is also supported and takes precedence over the file. Never
put a key in the iOS app, a committed file, a URL, or CI. Without a key, sample
menus and quotes still work; Nearby explains that it is not connected.

The interface uses built-in Avenir Next typography, a Georgia feature headline,
and three locally bundled, AI-generated food photos. The photos illustrate the
fictional sample menus. Search, cuisine filters, price sorting, menu search, and
device-local saved restaurants remain available. Design references,
asset paths, and generation prompts are in [docs/UI-DESIGN.md](docs/UI-DESIGN.md).

Keep the API terminal running. Stop it with Control-C. The API binds only to
`127.0.0.1:8087`; this first milestone is for a simulator on the same Mac. Physical
iPhones and Release builds deliberately have no backend URL yet. Deployment will
require an HTTPS endpoint and an explicit configuration decision.

To check the unavailable-server experience, stop the API, refresh in the app,
then start the API and tap **Try again**.

## Follow a quote request

1. `ios/Kula/RestaurantDetailView.swift`: add a dish; confirm replacing another restaurant's cart.
2. `ios/Kula/Cart.swift`: in-memory cart, quantity limits, quote invalidation and expiry.
3. `ios/Kula/CatalogAPI.swift`: POST only IDs and quantities; decode the server response.
4. `backend/internal/catalog/quote.go`: validate dishes and calculate integer TZS totals.
5. `backend/internal/catalog/quote_test.go`: exercise that HTTP contract and rejection paths.

The server owns menu prices. The client formats prices and filters this tiny
catalog locally. Every price is an integer in **whole TZS**. This response is
intentionally bounded by three fixtures; real catalog growth requires pagination,
server-side filtering, and excluding full menus from list responses.

The cart contains one restaurant. Editing it invalidates the quote; a response
for an older cart revision is discarded. Quotes expire after five minutes, are
not stored, and are not reservations or redeemable checkout tokens. The food
subtotal excludes delivery, service fees and taxes. The cart is cleared when
the app process restarts.

## Local API

| Request | Response |
| --- | --- |
| `GET /healthz` | `{"status":"ok"}` |
| `GET /v1/restaurants` | `{"restaurants":[...]}` |
| `GET /v1/restaurants/{id}` | Restaurant with menu, or HTTP 404 |
| `POST /v1/quotes` | Validated sample food subtotal and five-minute expiry |
| `GET /v1/discovery/restaurants` | Up to 20 live Google listings around the pilot area |

Example quote request:

```json
{
  "restaurant_id": "kivuli-kitchen",
  "items": [{"menu_item_id": "beef-pilau", "quantity": 2}]
}
```

Send `Content-Type: application/json`. This returns a food subtotal of 28000 TZS
from the sample menu. Client prices and unknown fields are rejected. Limits:
8 KiB request body, 30 distinct dishes, 20 of each dish, 50 items total.
Invalid JSON returns 400, unknown restaurants 404, unsupported content types 415,
and invalid dish/quantity combinations 422. Unsupported methods return 405.

Discovery uses a fixed approximate 3.5 km circle; it is not a delivery boundary
or a complete restaurant census. It makes at most one Google attempt per request,
uses an eight-second timeout and a 1 MiB response limit, and stores no Google
content on disk or in a database. Google and third-party attributions appear in
Nearby. Missing credentials return 503, upstream failure 502, and refreshes within
the per-process three-second interval return 429. Errors do not include upstream
response bodies or credentials. Details: [Google setup](docs/GOOGLE-PLACES.md).

There is no authentication, database, customer data, or location permission yet.
The localhost-only App Transport Security exception is for local development;
production configuration must remove it when adding HTTPS. Do not expose this
unauthenticated prototype on the internet.

## Verification commands

```sh
make check-backend
make smoke
make build-ios
```

Stop `make api` before `make smoke`, which starts and stops its own server on 8087.
The smoke check exercises the real HTTP API, quote calculation and tampering,
missing credentials, missing resources, unsupported methods, concurrent reads,
and shutdown. It removes Google credentials from its child process and never
calls Google.

The focused Go handler tests cover quote validation and discovery success,
failure, cancellation, attribution and simultaneous refreshes. Discovery tests
use a simulated upstream transport; CI needs no Google secrets or billing.
These are functional checks, **not load benchmarks**. To additionally exercise
the real HTTP server with the race detector:

```sh
cd backend
env GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off GOTELEMETRY=off go build -race -o ../.build/kula-api ./cmd/api
cd ..
python3 scripts/smoke.py
```

For simulator acceptance checks, see [TESTING.md](docs/TESTING.md).

## CI and deployment

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs Go build/vet/tests/race
checks, the HTTP smoke check, and an unsigned iOS simulator build on pull requests
and pushes to `main`. Actions are pinned to commit hashes; the workflow has
read-only repository permissions and no application secrets.

Deployment is not configured. A hosting target, HTTPS, production secrets and
access controls must be agreed before backend CD. Physical-device/TestFlight
distribution also needs an Apple developer team, signing, a production bundle
identifier and an HTTPS API URL. The simulator build does not produce an
App Store-ready archive.

## Next milestones

Discuss each milestone before expanding scope:

1. Review Nearby and the sample cart; settle English/Kiswahili presentation and
   begin restaurant onboarding for real, merchant-approved menus and prices.
2. Persistent orders and restaurant acceptance/rejection. Agree on PostgreSQL
   setup, its driver, schema, authentication, and authorization before adding them.
3. Payment sandbox, duplicate-request protection, ambiguous outcomes, refunds,
   and reconciliation.
4. Manual rider assignment and a controlled operational pilot.

Security review, load measurements, privacy obligations, production hosting,
restaurant onboarding, and the delivery operating model remain ahead. This
milestone demonstrates app-to-server communication; it is not launch-ready or a
demonstration of national-scale capacity.
