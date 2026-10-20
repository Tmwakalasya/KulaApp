// Package catalog serves a small, read-only set of fictional pilot menus.
package catalog

import (
	"encoding/json"
	"log/slog"
	"net/http"
)

type MenuItem struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	PriceTZS    int    `json:"price_tzs"` // Whole Tanzanian shillings; never floating point.
}

type Restaurant struct {
	ID          string     `json:"id"`
	Name        string     `json:"name"`
	Area        string     `json:"area"`
	Cuisine     string     `json:"cuisine"`
	Description string     `json:"description"`
	Menu        []MenuItem `json:"menu"`
}

// Handler owns its immutable demo catalog. Nothing in this milestone accepts
// orders, personal data, payment details, or catalog mutations.
func Handler() http.Handler {
	restaurants := demoRestaurants()
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
	mux.HandleFunc("GET /v1/restaurants", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, struct {
			Restaurants []Restaurant `json:"restaurants"`
		}{restaurants})
	})
	mux.HandleFunc("GET /v1/restaurants/{id}", func(w http.ResponseWriter, r *http.Request) {
		for _, restaurant := range restaurants {
			if restaurant.ID == r.PathValue("id") {
				writeJSON(w, http.StatusOK, restaurant)
				return
			}
		}
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "Restaurant not found."})
	})
	mux.HandleFunc("POST /v1/quotes", quoteHandler(restaurants))
	return mux
}

// writeJSON sends a JSON response with caching disabled and logs encoding errors.
func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(value); err != nil {
		slog.Warn("response write failed", "error", err)
	}
}

// demoRestaurants returns a fresh catalog of fictional restaurants and TZS menus.
func demoRestaurants() []Restaurant {
	return []Restaurant{
		{
			ID: "kivuli-kitchen", Name: "Kivuli Kitchen", Area: "Oyster Bay",
			Cuisine: "Swahili comfort food", Description: "A sample menu inspired by comforting coastal favourites.",
			Menu: []MenuItem{
				{ID: "coconut-fish", Name: "Coconut fish & rice", Description: "Fish in a coconut sauce, served with steamed rice and greens.", PriceTZS: 18000},
				{ID: "beef-pilau", Name: "Beef pilau", Description: "Spiced rice with slow-cooked beef and a fresh kachumbari.", PriceTZS: 14000},
				{ID: "beans-rice", Name: "Maharage & rice", Description: "Coconut beans with rice and seasonal vegetables.", PriceTZS: 9000},
			},
		},
		{
			ID: "bahari-table", Name: "Bahari Table", Area: "Masaki",
			Cuisine: "Coastal plates", Description: "A sample menu of bright flavours and generous seaside plates.",
			Menu: []MenuItem{
				{ID: "grilled-fish", Name: "Grilled fish plate", Description: "Grilled fish with lime, chips and a crunchy salad.", PriceTZS: 24000},
				{ID: "prawn-rice", Name: "Garlic prawns & rice", Description: "Garlic prawns with fragrant rice and a lemon wedge.", PriceTZS: 28000},
				{ID: "vegetable-curry", Name: "Vegetable curry", Description: "Seasonal vegetables in a coconut curry with rice.", PriceTZS: 12000},
			},
		},
		{
			ID: "ember-grain", Name: "Ember & Grain", Area: "Masaki",
			Cuisine: "Grills & bowls", Description: "A sample menu for an easy lunch or a relaxed evening.",
			Menu: []MenuItem{
				{ID: "chicken-bowl", Name: "Grilled chicken bowl", Description: "Grilled chicken, rice, avocado and a tangy house dressing.", PriceTZS: 16000},
				{ID: "mishkaki", Name: "Mishkaki & chips", Description: "Beef skewers with chips, salad and chilli sauce.", PriceTZS: 15000},
				{ID: "roasted-veg", Name: "Roasted vegetable bowl", Description: "Roasted vegetables, rice and a lemon dressing.", PriceTZS: 11000},
			},
		},
	}
}
