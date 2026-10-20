package discovery

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
)

// TestPhotoHTTPContract checks upstream photo requests, response headers and
// rejection of invalid resource queries before they reach the provider.
func TestPhotoHTTPContract(t *testing.T) {
	var calls atomic.Int32
	client := &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		calls.Add(1)
		if r.URL.Host != "places.googleapis.com" || r.URL.Path != "/v1/places/test-place/photos/test-photo/media" ||
			r.URL.Query().Get("maxWidthPx") != "800" || r.URL.Query().Get("skipHttpRedirect") != "true" ||
			r.Header.Get("X-Goog-Api-Key") != "test-key" || strings.Contains(r.URL.String(), "test-key") {
			t.Error("photo request changed origin, dimensions, redirect policy or key handling")
		}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"photoUri":"https://lh3.googleusercontent.com/test-photo"}`))}, nil
	})}
	handler := newPhotoHandler("test-key", client)
	path := "/v1/discovery/photo?name=places/test-place/photos/test-photo"
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, httptest.NewRequest("GET", path, nil))
	if w.Code != 200 || !strings.Contains(w.Body.String(), "https://lh3.googleusercontent.com/test-photo") ||
		strings.Contains(w.Body.String(), "test-key") || w.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("unsafe or invalid photo result: %d", w.Code)
	}
	for _, query := range []string{
		"name=https://example.com/image", "name=places/a/photos/../../secret",
		"name=places/a/photos/b&maxWidthPx=4800", "name=places/a/photos/b&name=places/a/photos/c",
		"name=places/a/photos/%2Fetc", "name=places/a/photos/b%3Fkey=secret",
	} {
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, httptest.NewRequest("GET", "/v1/discovery/photo?"+query, nil))
		if w.Code != 400 {
			t.Fatalf("accepted invalid photo query: %s", query)
		}
	}
	if calls.Load() != 1 {
		t.Fatal("invalid queries reached Google")
	}
}

// TestPhotoFailuresDoNotExposeUpstreamData checks that unsafe URLs and invalid
// provider responses produce generic failures without exposing the API key.
func TestPhotoFailuresDoNotExposeUpstreamData(t *testing.T) {
	for _, body := range []string{
		`{"photoUri":"http://lh3.googleusercontent.com/image"}`,
		`{"photoUri":"https://lh3.googleusercontent.com.attacker.example/image"}`,
		`{"photoUri":"https://test-key@lh3.googleusercontent.com/image"}`,
		`{"photoUri":"https://lh3.googleusercontent.com/image?key=test-key"}`,
		`{"photoUri":"https://127.0.0.1/image"}`,
		`{"error":"test-key private project details"}`,
		strings.Repeat("x", (64<<10)+1),
		`{`,
	} {
		client := &http.Client{Transport: transportFunc(func(*http.Request) (*http.Response, error) {
			return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(body))}, nil
		})}
		w := httptest.NewRecorder()
		newPhotoHandler("test-key", client).ServeHTTP(w, httptest.NewRequest("GET", "/v1/discovery/photo?name=places/a/photos/b", nil))
		if w.Code != 502 || strings.Contains(w.Body.String(), "test-key") {
			t.Fatalf("unsafe photo failure: %d", w.Code)
		}
	}
}

// TestConcurrentPhotosRespectBurstLimit checks that concurrent photo requests
// cannot exceed the initial burst of 20 upstream calls.
func TestConcurrentPhotosRespectBurstLimit(t *testing.T) {
	var calls atomic.Int32
	client := &http.Client{Transport: transportFunc(func(*http.Request) (*http.Response, error) {
		calls.Add(1)
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"photoUri":"https://lh3.googleusercontent.com/image"}`))}, nil
	})}
	handler := newPhotoHandler("test-key", client)
	var workers sync.WaitGroup
	start := make(chan struct{})
	for range 30 {
		workers.Add(1)
		go func() {
			defer workers.Done()
			<-start
			w := httptest.NewRecorder()
			handler.ServeHTTP(w, httptest.NewRequest("GET", "/v1/discovery/photo?name=places/a/photos/b", nil))
			if w.Code != 200 && w.Code != 429 {
				t.Errorf("status: %d", w.Code)
			}
		}()
	}
	close(start)
	workers.Wait()
	if calls.Load() != 20 {
		t.Fatalf("upstream calls %d, want initial burst of 20", calls.Load())
	}
}
