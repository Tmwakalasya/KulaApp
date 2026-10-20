# Kula browsing redesign

Reference pages inspected: [DoorDash](https://www.doordash.com/) and
[Uber Eats](https://www.ubereats.com/). The public pages informed location-first
discovery and cuisine browsing. This is an original Kula interface, not a copy
of either app or an inspection of their signed-in experiences.

The SwiftUI interface adds restaurant/dish search, cuisine filtering,
neighbourhood selection, price sorting, and a persistent Saved collection.
Saved IDs use local UserDefaults; they are not an account or server-backed list.
These controls operate on the existing three restaurant fixtures. No API,
database schema, dependencies, or payment behavior changed.

Typography uses iOS's built-in Avenir Next family for the interface and wordmark,
with Georgia Bold for the feature headline. Custom fonts use Dynamic Type text
styles; no font files or remote font requests are required.

Food images were created with the built-in image generation tool. They are
illustrative photos for fictional sample restaurants, not merchant-supplied
images. Originals remain in the image-generation output directory. App copies:

- `ios/Kula/Assets.xcassets/kivuli-food.imageset/food.png`
- `ios/Kula/Assets.xcassets/bahari-food.imageset/food.png`
- `ios/Kula/Assets.xcassets/ember-food.imageset/food.png`

Images are bundled, so browsing makes no remote image requests. The same images
appear on corresponding dish rows only when the pictured dish matches the sample.
The UI does not invent restaurant ratings, delivery fees, or arrival estimates.

## Generation prompts

### kivuli

Use case: photorealistic-natural. Asset type: landscape restaurant card photograph for a Tanzanian food discovery iPhone app. Create one original editorial food photograph of a generous ceramic plate of Tanzanian beef pilau, fragrant spiced brown rice with visible tender beef pieces, a small serving of fresh tomato red onion kachumbari, lime wedge. Warm off-white tabletop with subtle linen, natural soft daylight, appetizing realistic textures, overhead three-quarter angle, plate centered and large in frame with enough margin to crop to a 2:1 restaurant card. Restaurant-quality food photography, rich warm colors, natural imperfect presentation. No text, logos, watermark, people, hands, UI, or borders. Single photograph, not a collage. Landscape 3:2 composition.

### bahari

Use case: photorealistic-natural. Asset type: landscape restaurant card photograph for a Tanzanian food discovery iPhone app. Create one original editorial food photograph of a coastal grilled whole fish with gently charred golden skin, wedges of lime, fresh herbs, golden chips and a side salad on a beautiful simple oval ceramic plate. Turquoise-blue weathered table visible around plate, natural soft coastal daylight, appetizing realistic textures, overhead three-quarter angle. Plate centered and large in frame with enough margin to crop to a 2:1 restaurant card. High quality food photography, natural imperfect presentation. No text, logos, watermark, people, hands, UI, or borders. Single photograph, not a collage. Landscape 3:2 composition.

### ember

Use case: photorealistic-natural. Asset type: landscape restaurant card photograph for a Tanzanian food discovery iPhone app. Create one original editorial food photograph of an abundant grilled chicken rice bowl, tender chargrilled chicken slices, white rice, avocado slices, bright tomato salad, green herbs and light dressing in a matte cream ceramic bowl. Warm terracotta surface, natural soft daylight, appetizing realistic textures, overhead three-quarter angle. Bowl centered and large in frame with enough margin to crop to a 2:1 restaurant card. High quality food photography, natural imperfect presentation. No text, logos, watermark, people, hands, UI, or borders. Single photograph, not a collage. Landscape 3:2 composition.
