package discovery

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

type transportFunc func(*http.Request) (*http.Response, error)

// RoundTrip delegates to f so tests can simulate the upstream HTTP transport.
func (f transportFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

// TestDiscoveryHTTPContract checks the bounded upstream query, returned listing
// and photo attributions, credential handling, cache policy and refresh rate gate.
func TestDiscoveryHTTPContract(t *testing.T) {
	var calls atomic.Int32
	client := &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		calls.Add(1)
		if r.Method != "POST" || r.Header.Get("X-Goog-Api-Key") != "test-only-key" || r.Header.Get("X-Goog-FieldMask") != fieldMask {
			t.Error("incorrect upstream request")
		}
		var payload struct {
			MaxResultCount int      `json:"maxResultCount"`
			IncludedTypes  []string `json:"includedTypes"`
		}
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatal(err)
		}
		if payload.MaxResultCount != 20 || len(payload.IncludedTypes) != 1 || payload.IncludedTypes[0] != "restaurant" {
			t.Error("unbounded discovery")
		}
		body := `{"places":[{"id":"sample-place","displayName":{"text":"Provider Test Restaurant"},"formattedAddress":"Dar es Salaam","googleMapsUri":"https://maps.google.com/example","attributions":[{"provider":"Example provider","providerUri":"https://example.com"}],"photos":[{"name":"places/sample-place/photos/test-photo","googleMapsUri":"https://maps.google.com/photo","authorAttributions":[{"displayName":"Test Author","uri":"https://maps.google.com/author","photoUri":"https://lh3.googleusercontent.com/avatar"}]}]}]}`
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(body)), Header: make(http.Header)}, nil
	})}
	handler := newHandler("test-only-key", client, endpoint, time.Second)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, httptest.NewRequest("GET", "/v1/discovery/restaurants", nil))
	if w.Code != 200 {
		t.Fatalf("status: %d", w.Code)
	}
	var result struct {
		Source      string  `json:"source"`
		Restaurants []place `json:"restaurants"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if result.Source != "google_maps" || len(result.Restaurants) != 1 || len(result.Restaurants[0].Attributions) != 1 {
		t.Fatalf("missing result/attribution: %+v", result)
	}
	p := result.Restaurants[0].Photo
	if p == nil || len(p.AuthorAttributions) != 1 || p.AuthorAttributions[0].DisplayName != "Test Author" || p.GoogleMapsURI != "https://maps.google.com/photo" {
		t.Fatal("photo credit or source link was lost")
	}
	if strings.Contains(w.Body.String(), "test-only-key") || w.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("credential exposure or caching")
	}
	w = httptest.NewRecorder()
	handler.ServeHTTP(w, httptest.NewRequest("GET", "/v1/discovery/restaurants", nil))
	if w.Code != 429 || calls.Load() != 1 {
		t.Fatal("rate gate did not prevent extra upstream request")
	}
}

// TestDiscoveryFailures checks request rejection and generic provider failures
// without exposing upstream credentials or project details.
func TestDiscoveryFailures(t *testing.T) {
	for _, tc := range []struct {
		name, key, method, path string
		status                  int
	}{
		{"no key", "", "GET", "/v1/discovery/restaurants", 503},
		{"write", "test", "POST", "/v1/discovery/restaurants", 405},
		{"arbitrary area", "test", "GET", "/v1/discovery/restaurants?lat=0", 400},
	} {
		t.Run(tc.name, func(t *testing.T) {
			client := &http.Client{Transport: transportFunc(func(*http.Request) (*http.Response, error) { t.Fatal("unexpected upstream call"); return nil, nil })}
			w := httptest.NewRecorder()
			newHandler(tc.key, client, endpoint, 0).ServeHTTP(w, httptest.NewRequest(tc.method, tc.path, nil))
			if w.Code != tc.status {
				t.Fatalf("status %d, want %d", w.Code, tc.status)
			}
		})
	}
	for _, tc := range []struct {
		name   string
		status int
		body   string
	}{
		{"provider denied", 403, `{"error":"test-only-key private project details"}`},
		{"malformed", 200, `{`},
		{"oversize", 200, strings.Repeat("x", (1<<20)+1)},
	} {
		t.Run(tc.name, func(t *testing.T) {
			client := &http.Client{Transport: transportFunc(func(*http.Request) (*http.Response, error) {
				return &http.Response{StatusCode: tc.status, Body: io.NopCloser(strings.NewReader(tc.body))}, nil
			})}
			w := httptest.NewRecorder()
			newHandler("test-only-key", client, endpoint, 0).ServeHTTP(w, httptest.NewRequest("GET", "/v1/discovery/restaurants", nil))
			if w.Code != 502 || strings.Contains(w.Body.String(), "test-only-key") {
				t.Fatalf("unsafe failure: %d %s", w.Code, w.Body)
			}
		})
	}
}

// TestDiscoveryForwardsCancellation checks that canceling a discovery request
// cancels its upstream request and returns a gateway failure.
func TestDiscoveryForwardsCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	client := &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		if r.Context().Err() == nil {
			t.Error("request context lost")
		}
		return nil, r.Context().Err()
	})}
	w := httptest.NewRecorder()
	newHandler("test", client, endpoint, 0).ServeHTTP(w, httptest.NewRequest("GET", "/v1/discovery/restaurants", nil).WithContext(ctx))
	if w.Code != 502 {
		t.Fatalf("status %d", w.Code)
	}
}

// TestConcurrentRefreshesMakeOneUpstreamCall checks that simultaneous refreshes
// share a rate gate that permits only one upstream attempt in the interval.
func TestConcurrentRefreshesMakeOneUpstreamCall(t *testing.T) {
	var calls atomic.Int32
	client := &http.Client{Transport: transportFunc(func(*http.Request) (*http.Response, error) {
		calls.Add(1)
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"places":[]}`))}, nil
	})}
	handler := newHandler("test", client, endpoint, time.Hour)
	start := make(chan struct{})
	statuses := make(chan int, 24)
	var workers sync.WaitGroup
	for range 24 {
		workers.Add(1)
		go func() {
			defer workers.Done()
			<-start
			w := httptest.NewRecorder()
			handler.ServeHTTP(w, httptest.NewRequest("GET", "/v1/discovery/restaurants", nil))
			statuses <- w.Code
		}()
	}
	close(start)
	workers.Wait()
	close(statuses)
	success := 0
	for status := range statuses {
		switch status {
		case 200:
			success++
		case 429:
		default:
			t.Fatalf("unexpected status: %d", status)
		}
	}
	if success != 1 || calls.Load() != 1 {
		t.Fatalf("successes %d, upstream calls %d", success, calls.Load())
	}
}
