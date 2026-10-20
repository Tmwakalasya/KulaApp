# Simulator acceptance checks

Start the API as described in the README. Open `ios/Kula.xcodeproj`, select
**Kula** and an installed iPhone simulator, and press **Command-R**. This
milestone does not connect physical iPhones or Release builds to an API.

## Nearby

- Open **Nearby**. With a working Places key, real names and addresses should
  appear on cards with available place photos, Google Maps attribution and
  working map links. Photos should load as the cards appear.
- Check photo author credits, profile links and **Photo source** links.
  Missing photos should show a neutral storefront placeholder. Failed photo
  downloads should show a retry action while leaving the listing usable.
- These listings have no Add button, generated sample photo, menu or invented price.
- Pull to refresh immediately after a successful load. The API may show its
  three-second rate-limit message; wait, then use **Try again**.
- Restart the API without a key. Nearby should explain that it is not connected,
  while Explore and the sample cart continue working.

## Cart and quote

- Open **Kivuli Kitchen**, add two **Beef pilau**, and open the cart.
- Tap **Get fresh food quote**. Expect **TZS 28,000**, a five-minute validity
  time, and a notice that delivery, service fees and taxes are not calculated.
- Add one **Maharage & rice**, then request a fresh quote. Expect **TZS 37,000**.
- Change a quantity. The old quote should disappear immediately. Requesting
  another quote should reflect the current quantities.
- Start a quote request and edit a quantity before it completes, if the network
  is slow enough to observe this. The old response must not restore the quote.
- Add a dish from **Bahari Table**. Keep the existing cart first, then repeat and
  confirm **Replace cart**. The cart must contain only the chosen restaurant.
- Reduce a quantity to zero. The line should disappear; removing the last line
  should show the empty state.
- Leave a quote visible for five minutes. It should be replaced by an expiry
  prompt. There is no checkout or payment action.
- Stop the API and request a quote. Expect an error, then restart the API and
  retry. Old quote totals must not be presented as a successful new quote.

Also check scrolling, larger accessibility text, VoiceOver button labels, and
light/dark appearance. Automated API checks do not verify the rendered UI.

## Automated checks

`make check-backend` builds, vets, runs HTTP handler contract tests, and runs
those tests under Go's race detector. `make smoke` owns a separate server on
8087, so stop your development API first. `make build-ios` compiles an unsigned
simulator app. The GitHub Actions workflow runs all three.

No automated test calls Google. Live discovery verification is a separate,
explicit operation that can incur an API charge.
