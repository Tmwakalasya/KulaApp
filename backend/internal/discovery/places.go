// Package discovery exposes live Google listings separately from Kula menus.
package discovery

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"sync/atomic"
	"time"
)

const endpoint = "https://places.googleapis.com/v1/places:searchNearby"
const fieldMask = "places.id,places.displayName,places.formattedAddress,places.googleMapsUri,places.attributions,places.photos"

type attribution struct {
	Provider    string `json:"provider"`
	ProviderURI string `json:"providerUri"`
}

type place struct {
	ID           string        `json:"place_id"`
	Name         string        `json:"name"`
	Address      string        `json:"address"`
	MapsURL      string        `json:"maps_url"`
	Attributions []attribution `json:"attributions"`
	Photo        *photo        `json:"photo,omitempty"`
}

type photo struct {
	Name               string        `json:"name"`
	GoogleMapsURI      string        `json:"googleMapsUri"`
	AuthorAttributions []photoAuthor `json:"authorAttributions"`
}

type photoAuthor struct {
	DisplayName string `json:"displayName"`
	URI         string `json:"uri"`
	PhotoURI    string `json:"photoUri"`
}

// NewHandler makes at most one upstream attempt per user request. It stores no
// Google content. The local rate gate bounds accidental repeated billable calls;
// cloud quotas and authenticated per-user limits remain necessary before hosting.
func NewHandler(apiKey string) http.Handler {
	client := &http.Client{
		Timeout:       8 * time.Second,
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse },
	}
	return newHandler(strings.TrimSpace(apiKey), client, endpoint, 3*time.Second)
}

// newHandler queries the fixed pilot area using the supplied client and endpoint,
// spacing upstream attempts by interval and preserving listing attributions.
func newHandler(apiKey string, client *http.Client, url string, interval time.Duration) http.Handler {
	var nextRequest atomic.Int64
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		fail := func(status int, message string) {
			w.WriteHeader(status)
			if err := json.NewEncoder(w).Encode(map[string]string{"error": message}); err != nil {
				slog.Warn("discovery response write failed", "error", err)
			}
		}
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			fail(http.StatusMethodNotAllowed, "Use GET.")
			return
		}
		if apiKey == "" {
			fail(http.StatusServiceUnavailable, "Nearby restaurants are not connected yet. Sample menus are still available.")
			return
		}
		if r.URL.RawQuery != "" {
			fail(http.StatusBadRequest, "Discovery currently supports only the fixed Dar pilot area.")
			return
		}
		now, previous := time.Now().UnixNano(), nextRequest.Load()
		if now < previous || !nextRequest.CompareAndSwap(previous, now+int64(interval)) {
			w.Header().Set("Retry-After", "3")
			fail(http.StatusTooManyRequests, "Please wait a few seconds before refreshing nearby restaurants.")
			return
		}
		// An approximate discovery circle, not a promised delivery boundary.
		body := []byte(`{"includedTypes":["restaurant"],"maxResultCount":20,"rankPreference":"DISTANCE","languageCode":"en","regionCode":"TZ","locationRestriction":{"circle":{"center":{"latitude":-6.760,"longitude":39.275},"radius":3500}}}`)
		request, err := http.NewRequestWithContext(r.Context(), http.MethodPost, url, bytes.NewReader(body))
		if err != nil {
			fail(http.StatusInternalServerError, "Discovery is unavailable.")
			return
		}
		request.Header.Set("Content-Type", "application/json")
		request.Header.Set("X-Goog-Api-Key", apiKey)
		request.Header.Set("X-Goog-FieldMask", fieldMask)
		response, err := client.Do(request)
		if err != nil {
			fail(http.StatusBadGateway, "Could not reach restaurant discovery. Please try again later.")
			return
		}
		defer response.Body.Close()
		if response.StatusCode != http.StatusOK {
			// Do not expose upstream error bodies, credentials, or project details.
			fail(http.StatusBadGateway, "Nearby restaurant information is temporarily unavailable.")
			return
		}
		data, err := io.ReadAll(io.LimitReader(response.Body, (1<<20)+1))
		if err != nil || len(data) > 1<<20 {
			fail(http.StatusBadGateway, "Invalid discovery response.")
			return
		}
		var upstream struct {
			Places []struct {
				ID          string `json:"id"`
				DisplayName struct {
					Text string `json:"text"`
				} `json:"displayName"`
				Address      string        `json:"formattedAddress"`
				MapsURL      string        `json:"googleMapsUri"`
				Attributions []attribution `json:"attributions"`
				Photos       []photo       `json:"photos"`
			} `json:"places"`
		}
		if err := json.Unmarshal(data, &upstream); err != nil {
			fail(http.StatusBadGateway, "Invalid discovery response.")
			return
		}
		places := make([]place, 0, len(upstream.Places))
		for _, p := range upstream.Places {
			if p.ID == "" || p.DisplayName.Text == "" {
				continue
			}
			attrs := p.Attributions
			if attrs == nil {
				attrs = []attribution{}
			}
			result := place{ID: p.ID, Name: p.DisplayName.Text, Address: p.Address, MapsURL: p.MapsURL, Attributions: attrs}
			for _, candidate := range p.Photos {
				if validPhotoName(candidate.Name) {
					if candidate.AuthorAttributions == nil {
						candidate.AuthorAttributions = []photoAuthor{}
					}
					result.Photo = &candidate
					break
				}
			}
			places = append(places, result)
		}
		if err := json.NewEncoder(w).Encode(struct {
			Source      string  `json:"source"`
			Restaurants []place `json:"restaurants"`
		}{"google_maps", places}); err != nil {
			slog.Warn("discovery response write failed", "error", err)
		}
	})
}
