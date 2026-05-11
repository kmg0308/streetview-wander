# AGENTS.md

Behavioral guidelines for coding agents working on this project. These rules are adapted from the Karpathy-inspired agent guidance in `forrestchang/andrej-karpathy-skills` and merged with this app's local needs.

## 1. Think Before Coding

- State assumptions before changing code when the request has more than one reasonable meaning.
- Ask when a choice cannot be safely inferred from the codebase.
- Surface tradeoffs when a simpler fix and a broader refactor are both possible.
- Stop and explain the uncertainty if the code or data contradicts the request.

## 2. Simplicity First

- Build the smallest change that solves the verified problem.
- Do not add features, settings, fallback paths, or abstractions that were not requested.
- Prefer plain functions and local types over new layers when one file or one caller is involved.
- If a change grows much larger than the behavior needs, simplify before continuing.

## 3. Surgical Changes

- Touch only files needed for the current task.
- Match the existing style, naming, and user-facing wording unless the task asks to change them.
- Do not clean up unrelated code, comments, formatting, or data.
- Remove only dead imports, variables, functions, and files created by your own change.

## 4. Goal-Driven Execution

- Convert each non-trivial task into clear success checks before editing.
- For bug fixes, reproduce or identify the failing path before changing behavior.
- For refactors, keep behavior stable and run `swift build` and `swift run StreetViewWanderSelfTest`.
- Keep looping until the checks pass or a real blocker is identified.

## Project-Specific Rules

- This is a SwiftUI macOS app built with Swift Package Manager. Keep app UI code under `Sources/StreetViewWander` and shared logic under `Sources/StreetViewWanderCore`.
- Do not bundle user API keys into releases. Users must enter keys in Settings or import a local `.env` file.
- Do not expose `GOOGLE_STREET_VIEW_METADATA_API_KEY` to the Street View web view. Only `VITE_GOOGLE_MAPS_API_KEY` may be passed to WebKit.
- Treat `data/countries.json` as generated boundary data. Do not manually edit it unless the task is explicitly about country data.
- Random place selection must keep returning the `Panorama` shape used by the Swift app and local visit history.
- For release changes, run `swift build`, `swift run StreetViewWanderSelfTest`, and `./scripts/package.sh`.
