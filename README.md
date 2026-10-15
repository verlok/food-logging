# Food Lodge

A native iOS food diary and macronutrient calculator built with Swift, SwiftUI, SwiftData and Swift Charts. It is built around the parts that matter day to day: logging food in very few taps, a built-in food database you can extend, AI-assisted dish creation from a description or a photo, an energy-expenditure estimate that adapts to the weight you log, and charts for weight, calories and macros.

## Features

- **Diary** – one screen per day with a calorie ring, protein/carb/fat bars and a free-form timeline of everything eaten, ordered by time (no fixed meal slots). The current date and time are pre-selected when adding; the time can be adjusted from the search toolbar. A one-tap "+" on every food row logs a serving immediately. Quick add for calories and macros without a food.
- **Copy and move** – any entry can be copied or moved to another day and time (with Today / Yesterday / Tomorrow / Now shortcuts), copied to "now" in one tap, and a whole day can be copied into the selected day.
- **Food database** – 134 bundled foods (Italian and international staples) with per-100 g macros and a set of micronutrients, localised names, servings, favourites, recents and search. Create your own foods, edit them, or build dishes.
- **AI dish creation** – describe a dish or photograph it; Claude breaks it into ingredients with gram estimates and nutrition, you review and save it as a reusable food. Uses the Claude Messages API directly (no SDK) with structured JSON output.
- **Adaptive expenditure** – starts from Mifflin-St Jeor × activity level, then blends in the energy balance observed from your logged intake and the smoothed weight trend over the last 28 days. Daily calorie and macro targets follow your goal (lose / maintain / gain, kg per week) and macro strategy.
- **Weight** – daily log, exponential-moving-average trend line, 7- and 30-day change.
- **Charts** – weight (measurements and trend), calories versus target and expenditure, stacked macro calories, average micronutrient coverage against reference intakes.
- **Micronutrients** – per-day breakdown of fibre, sugars, lipids, minerals and vitamins against reference daily intakes.
- **Localisation** – English and Italian via a String Catalog. The structure is ready for Spanish, French and Portuguese.

## Project layout

```
project.yml                 xcodegen spec → FoodLodge.xcodeproj
FoodLodge/
  App/                      entry point, root tab view
  Models/                   SwiftData models, nutrients, persistence (+ type-check shim)
  Services/                 nutrition engine, app store, AI service, seeder, keychain
  Views/                    Diary, Foods, Weight, Charts, Settings, Onboarding, Components
  Resources/                Localizable.xcstrings, foods_seed.json, Assets.xcassets
FoodLodgeTests/              XCTest unit tests for the nutrition engine and seed data
scripts/typecheck.sh        type-checks everything with the bare Swift toolchain
```

## Requirements

- Xcode 16 or later, iOS 17 deployment target.
- [xcodegen](https://github.com/yonaskolb/XcodeGen) to regenerate the project after adding files: `xcodegen generate`.

## Running

```bash
xcodegen generate
open FoodLodge.xcodeproj
```

Select the FoodLodge scheme and an iPhone simulator, then run. On first launch the app seeds the food database and shows onboarding (sex, birth date, height, activity, goal, starting weight).

### AI dish creation

Enter a Claude API key in **Settings → AI dish creation**. The key is stored in the Keychain and sent only to `api.anthropic.com`. The default model is `claude-opus-5-5`; it can be changed in the same section. Requests use structured output (`output_config.format`) so the response is always a valid ingredient list, and the server-side refusal fallback is enabled.

## Tests

Run the FoodLodgeTests target in Xcode (⌘U). The tests cover the metabolic-rate formula, weight-trend smoothing, the adaptive expenditure estimator, target calculation (including the calorie floor), nutrient profile maths, seed-database consistency and meal suggestion.

`scripts/typecheck.sh` type-checks the whole code base without Xcode, replacing the SwiftData macros with a shim (`-D SWIFTDATA_SHIM`). It is a fast sanity check, not a substitute for a real build.

## How the numbers work

- **Trend weight**: exponential moving average with α = 0.1 over a daily series; missing days carry the previous trend.
- **Expenditure**: `formula × (1 − w) + observed × w`, where `observed = average intake − Δtrend × 7700 / days` over complete logged days (≥ 800 kcal) in the last 28 days, and `w` grows from 0 at 7 logged days to 0.85 at 21. The observed value is clamped to 0.6–1.6 × formula.
- **Targets**: calories = expenditure ± (weekly rate × 7700 / 7), floored at 1200 kcal (female) / 1500 kcal (male). Protein = g/kg × trend weight, fat = fat share of calories, carbohydrates take the rest with a 50 g minimum.
