# Google Places setup

Nearby is live discovery. It does not establish a restaurant partnership, menu,
price, availability, or permission to accept orders.

1. Enable **Places API (New)** and billing in a Google Cloud project.
2. Create a server API key restricted to Places API (New). Use an IP restriction
   for the server's public egress address. A laptop's changing public IP may
   require updating that restriction during local testing.
3. Store the key outside the repository in a private file with permissions `600`.
   Set `GOOGLE_MAPS_API_KEY_FILE` to that path before starting `make api`.
   Alternatively inject `GOOGLE_MAPS_API_KEY` through the process environment.
4. Configure Google API quotas and billing alerts. This prototype's in-process
   refresh limit is not a hard spending cap and resets on restart. Multiple
   server instances each have their own limiter. Shared hosting requires
   authenticated callers and limits enforced across instances.
5. Rotate temporary credentials after testing. Restart the API with the new
   file: credentials are read only at startup.

The API requests only place ID, display name, formatted address, Google Maps
link, provider attributions and photo metadata, using `POST places:searchNearby`. It asks for
up to 20 restaurants nearest to (-6.760, 39.275) within 3,500 meters. That
approximate search area does not determine Kula delivery eligibility.

The key goes to Google in a header, never a URL. There is no automatic retry loop.
Provider errors are replaced with a generic client message. Automatic redirects
are refused. Go limits the response size and propagates request cancellation.

The backend does not write Google results to files, logs, or a database. Its
response uses `Cache-Control: no-store`; iOS holds results only as transient
display state and requests without using its local response cache. No Google
restaurant is added to the saved sample restaurants.

Each card can display the first available Google photo. The client resolves its
resource through Go on demand (`skipHttpRedirect=true`); Go returns only a public
HTTPS image URL on a `googleusercontent.com` subdomain. It does not follow
credential-bearing redirects or forward the key to the image host. Photo
requests are fixed at a maximum of 800 × 600 pixels and add billable API calls.
The resolver has a per-process burst of 20 with one request/second replenishment,
an eight-second timeout and a 64 KiB metadata-response limit.

iOS downloads the image and available author avatars through an ephemeral
session without a URL cache, cookies or credentials. Downloads and redirects
are restricted to Google image hosts, capped at 3 MiB per image, and cancelled
when their task is cancelled. A missing or failed photo leaves the listing
usable with a placeholder. Refresh Nearby to get fresh photo references if
Google has expired a reference; references and image bytes are not persisted.

Nearby separates Google content from Kula sample menus, displays the exact
**Google Maps** text attribution and any returned third-party attributions.
Photo credits include available author names, avatars, profile links and
photo-source links. It uses no Google reviews or ratings. Bundled illustrative
food photos belong only to fictional sample restaurants.

Before public release, provide publicly accessible terms and a privacy policy
with the required Google references, then recheck the current storage and
attribution requirements. Do not turn discovery results into a persistent
restaurant database without checking the permitted uses; place IDs have a
specific storage exception.

Official references checked for this implementation:

- [Nearby Search (New)](https://developers.google.com/maps/documentation/places/web-service/nearby-search)
- [Place Photos (New)](https://developers.google.com/maps/documentation/places/web-service/place-photos)
- [Places API policies and attribution](https://developers.google.com/maps/documentation/places/web-service/policies)
- [Google Maps API security practices](https://developers.google.com/maps/api-security-best-practices)

Google API usage may incur charges. Automated tests use simulated responses and
do not require credentials or a Google connection.
