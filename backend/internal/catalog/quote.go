package catalog

import (
	"encoding/json"
	"io"
	"mime"
	"net/http"
	"time"
)

type quoteRequest struct {
	RestaurantID string `json:"restaurant_id"`
	Items        []struct {
		MenuItemID string `json:"menu_item_id"`
		Quantity   int    `json:"quantity"`
	} `json:"items"`
}

type quoteLine struct {
	MenuItemID   string `json:"menu_item_id"`
	Name         string `json:"name"`
	Quantity     int    `json:"quantity"`
	UnitPriceTZS int64  `json:"unit_price_tzs"`
	LineTotalTZS int64  `json:"line_total_tzs"`
}

type quote struct {
	RestaurantID   string      `json:"restaurant_id"`
	RestaurantName string      `json:"restaurant_name"`
	Currency       string      `json:"currency"`
	Items          []quoteLine `json:"items"`
	SubtotalTZS    int64       `json:"subtotal_tzs"`
	ExpiresAt      time.Time   `json:"expires_at"`
	Demo           bool        `json:"demo"`
}

// quoteHandler validates cart IDs and quantities against the supplied catalog
// and returns server-priced TZS subtotals that expire after five minutes.
func quoteHandler(restaurants []Restaurant) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		fail := func(status int, message string) { writeJSON(w, status, map[string]string{"error": message}) }
		mediaType, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
		if err != nil || mediaType != "application/json" {
			fail(http.StatusUnsupportedMediaType, "Use application/json.")
			return
		}
		r.Body = http.MaxBytesReader(w, r.Body, 8192)
		decoder := json.NewDecoder(r.Body)
		decoder.DisallowUnknownFields() // Prices and totals are never accepted from clients.
		var input quoteRequest
		if err := decoder.Decode(&input); err != nil {
			fail(http.StatusBadRequest, "Invalid quote request (maximum 8 KiB).")
			return
		}
		if err := decoder.Decode(new(any)); err != io.EOF {
			fail(http.StatusBadRequest, "Provide exactly one JSON object.")
			return
		}
		if input.RestaurantID == "" || len(input.Items) < 1 || len(input.Items) > 30 {
			fail(http.StatusUnprocessableEntity, "Choose one restaurant and between 1 and 30 different dishes.")
			return
		}
		var restaurant *Restaurant
		for i := range restaurants {
			if restaurants[i].ID == input.RestaurantID {
				restaurant = &restaurants[i]
				break
			}
		}
		if restaurant == nil {
			fail(http.StatusNotFound, "This restaurant has no Kula menu available for quotes.")
			return
		}
		result := quote{RestaurantID: restaurant.ID, RestaurantName: restaurant.Name, Currency: "TZS", Demo: true, ExpiresAt: time.Now().UTC().Add(5 * time.Minute).Truncate(time.Second)}
		seen := make(map[string]bool, len(input.Items))
		count := 0
		for _, requested := range input.Items {
			if requested.Quantity < 1 || requested.Quantity > 20 || seen[requested.MenuItemID] {
				fail(http.StatusUnprocessableEntity, "Use unique dishes with quantities between 1 and 20.")
				return
			}
			seen[requested.MenuItemID] = true
			count += requested.Quantity
			if count > 50 {
				fail(http.StatusUnprocessableEntity, "A cart may contain at most 50 items.")
				return
			}
			var item *MenuItem
			for i := range restaurant.Menu {
				if restaurant.Menu[i].ID == requested.MenuItemID {
					item = &restaurant.Menu[i]
					break
				}
			}
			if item == nil {
				fail(http.StatusUnprocessableEntity, "A dish is not available from this restaurant. Refresh the menu.")
				return
			}
			unit := int64(item.PriceTZS)
			line := quoteLine{MenuItemID: item.ID, Name: item.Name, Quantity: requested.Quantity, UnitPriceTZS: unit, LineTotalTZS: unit * int64(requested.Quantity)}
			result.Items = append(result.Items, line)
			result.SubtotalTZS += line.LineTotalTZS
		}
		writeJSON(w, http.StatusOK, result)
	}
}
