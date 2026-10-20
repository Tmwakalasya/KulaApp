package discovery

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"sync/atomic"
	"time"
)

var photoNamePattern = regexp.MustCompile(`^places/[A-Za-z0-9_-]+/photos/[A-Za-z0-9_-]+$`)

func validPhotoName(name string) bool {
	return len(name) <= 4096 && photoNamePattern.MatchString(name)
}

// NewPhotoHandler resolves one photo on demand. Only a Google photo resource
// name is accepted; callers cannot supply a host, image size, or redirect target.
// This localhost-only endpoint still needs authentication before shared hosting.
func NewPhotoHandler(apiKey string) http.Handler {
	client := &http.Client{
		Timeout:       8 * time.Second,
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse },
	}
	return newPhotoHandler(strings.TrimSpace(apiKey), client)
}

func newPhotoHandler(apiKey string, client *http.Client) http.Handler {
	// One request/second replenishment, burst of 20. Atomic reservations prevent
	// simultaneous card loads bypassing the per-process limit. No photo cache.
	var nextSlot atomic.Int64
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		reply := func(status int, value any) {
			w.WriteHeader(status)
			if err := json.NewEncoder(w).Encode(value); err != nil {
				slog.Warn("photo response write failed", "error", err)
			}
		}
		fail := func(status int) {
			reply(status, map[string]string{"error": "This photo is unavailable. Refresh Nearby to try again."})
		}
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			fail(http.StatusMethodNotAllowed)
			return
		}
		if apiKey == "" {
			fail(http.StatusServiceUnavailable)
			return
		}
		query, err := url.ParseQuery(r.URL.RawQuery)
		name := query.Get("name")
		if err != nil || len(query) != 1 || len(query["name"]) != 1 || !validPhotoName(name) {
			fail(http.StatusBadRequest)
			return
		}
		now := time.Now().UnixNano()
		for {
			previous := nextSlot.Load()
			next := max(previous, now) + int64(time.Second)
			if next > now+int64(20*time.Second) {
				w.Header().Set("Retry-After", "1")
				fail(http.StatusTooManyRequests)
				return
			}
			if nextSlot.CompareAndSwap(previous, next) {
				break
			}
		}
		target := "https://places.googleapis.com/v1/" + name + "/media?maxWidthPx=800&maxHeightPx=600&skipHttpRedirect=true"
		request, err := http.NewRequestWithContext(r.Context(), http.MethodGet, target, nil)
		if err != nil {
			fail(http.StatusInternalServerError)
			return
		}
		request.Header.Set("X-Goog-Api-Key", apiKey)
		response, err := client.Do(request)
		if err != nil {
			fail(http.StatusBadGateway)
			return
		}
		defer response.Body.Close()
		if response.StatusCode != http.StatusOK {
			fail(http.StatusBadGateway)
			return
		}
		data, err := io.ReadAll(io.LimitReader(response.Body, (64<<10)+1))
		var media struct {
			PhotoURI string `json:"photoUri"`
		}
		if err != nil || len(data) > 64<<10 || json.Unmarshal(data, &media) != nil {
			fail(http.StatusBadGateway)
			return
		}
		imageURL, err := url.Parse(media.PhotoURI)
		if err != nil || imageURL.Scheme != "https" || imageURL.User != nil || imageURL.Port() != "" ||
			!strings.HasSuffix(strings.ToLower(imageURL.Hostname()), ".googleusercontent.com") ||
			strings.Contains(media.PhotoURI, apiKey) {
			fail(http.StatusBadGateway)
			return
		}
		// The client downloads this public image URL without the server API key.
		reply(http.StatusOK, map[string]string{"url": media.PhotoURI})
	})
}
