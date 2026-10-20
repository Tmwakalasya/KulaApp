package catalog

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// TestQuoteHTTPContract checks pricing, expiry, cache headers and rejection of
// invalid carts, client-supplied prices, malformed bodies and unsupported methods.
func TestQuoteHTTPContract(t *testing.T) {
	handler := Handler()
	valid := `{"restaurant_id":"kivuli-kitchen","items":[{"menu_item_id":"beef-pilau","quantity":2},{"menu_item_id":"beans-rice","quantity":1}]}`
	request := httptest.NewRequest(http.MethodPost, "/v1/quotes", strings.NewReader(valid))
	request.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusOK {
		t.Fatalf("quote status: %d: %s", recorder.Code, recorder.Body)
	}
	var result quote
	if err := json.Unmarshal(recorder.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if result.SubtotalTZS != 37000 || len(result.Items) != 2 || result.Items[0].UnitPriceTZS != 14000 || result.Items[0].LineTotalTZS != 28000 || !result.Demo || result.Currency != "TZS" {
		t.Fatalf("incorrect quote: %+v", result)
	}
	remaining := time.Until(result.ExpiresAt)
	if remaining < 298*time.Second || remaining > 301*time.Second {
		t.Fatalf("expiry: %s", remaining)
	}
	if recorder.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("quotes must not be cached")
	}

	cases := []struct {
		name, body string
		status     int
	}{
		{"unknown restaurant", `{"restaurant_id":"google-place-id","items":[{"menu_item_id":"beef-pilau","quantity":1}]}`, 404},
		{"cross restaurant dish", `{"restaurant_id":"kivuli-kitchen","items":[{"menu_item_id":"chicken-bowl","quantity":1}]}`, 422},
		{"tampered price", `{"restaurant_id":"kivuli-kitchen","items":[{"menu_item_id":"beef-pilau","quantity":1,"price_tzs":1}]}`, 400},
		{"zero", `{"restaurant_id":"kivuli-kitchen","items":[{"menu_item_id":"beef-pilau","quantity":0}]}`, 422},
		{"negative", `{"restaurant_id":"kivuli-kitchen","items":[{"menu_item_id":"beef-pilau","quantity":-1}]}`, 422},
		{"large quantity", `{"restaurant_id":"kivuli-kitchen","items":[{"menu_item_id":"beef-pilau","quantity":21}]}`, 422},
		{"fractional quantity", `{"restaurant_id":"kivuli-kitchen","items":[{"menu_item_id":"beef-pilau","quantity":1.5}]}`, 400},
		{"duplicate dish", `{"restaurant_id":"kivuli-kitchen","items":[{"menu_item_id":"beef-pilau","quantity":1},{"menu_item_id":"beef-pilau","quantity":1}]}`, 422},
		{"total limit", `{"restaurant_id":"kivuli-kitchen","items":[{"menu_item_id":"beef-pilau","quantity":20},{"menu_item_id":"beans-rice","quantity":20},{"menu_item_id":"coconut-fish","quantity":20}]}`, 422},
		{"empty cart", `{"restaurant_id":"kivuli-kitchen","items":[]}`, 422},
		{"null", `null`, 422},
		{"malformed", `{`, 400},
		{"extra document", valid + `{}`, 400},
		{"oversize", `{"restaurant_id":"` + strings.Repeat("a", 8192) + `"}`, 400},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			r := httptest.NewRequest(http.MethodPost, "/v1/quotes", strings.NewReader(tc.body))
			r.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()
			handler.ServeHTTP(w, r)
			if w.Code != tc.status {
				t.Fatalf("got %d, want %d: %s", w.Code, tc.status, w.Body)
			}
		})
	}
	for _, method := range []string{http.MethodGet, http.MethodDelete} {
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, httptest.NewRequest(method, "/v1/quotes", nil))
		if w.Code != 405 {
			t.Fatalf("%s status: %d", method, w.Code)
		}
	}
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/v1/quotes", strings.NewReader(valid)))
	if w.Code != 415 {
		t.Fatalf("content-type status: %d", w.Code)
	}
}
