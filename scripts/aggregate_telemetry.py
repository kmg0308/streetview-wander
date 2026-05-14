#!/usr/bin/env python3
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EVENTS = ROOT / "telemetry" / "events"
SUMMARY = ROOT / "telemetry" / "summary" / "latest.json"
CONFIG = ROOT / "sampler-config" / "latest.json"


def parse_date(value):
    if not value:
        return datetime.min.replace(tzinfo=timezone.utc)
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return datetime.min.replace(tzinfo=timezone.utc)


def load_events():
    events = []
    if not EVENTS.exists():
        return events
    for path in sorted(EVENTS.glob("**/*.ndjson")):
        with path.open("r", encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, start=1):
                line = line.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                except json.JSONDecodeError as exc:
                    raise SystemExit(f"{path}:{line_number}: invalid JSON: {exc}") from exc
                event["_path"] = str(path.relative_to(ROOT))
                events.append(event)
    events.sort(key=lambda item: parse_date(item.get("createdAt")))
    return events


def count(events, key, *, where=None):
    counter = Counter()
    for event in events:
        if where and not where(event):
            continue
        value = event.get(key)
        if value:
            counter[value] += 1
    return dict(sorted(counter.items(), key=lambda item: (-item[1], item[0])))


def clamp(value, lower, upper):
    return max(lower, min(upper, value))


def generated_config(events):
    visits = [event for event in events if event.get("kind") == "visitRecorded"]
    recent_visits = visits[-100:]
    feedback = [event for event in events if event.get("kind") == "feedbackGiven"]
    feedback_counts = Counter(event.get("feedbackKind") for event in feedback if event.get("feedbackKind"))
    recent_country_counts = Counter(event.get("countryLabel") for event in recent_visits if event.get("countryLabel"))
    recent_continent_counts = Counter(event.get("continentLabel") for event in recent_visits if event.get("continentLabel"))

    scene_multipliers = {}
    too_many_roads = feedback_counts.get("tooManyRoads", 0)
    more_city = feedback_counts.get("moreCity", 0)
    if too_many_roads:
        road_factor = clamp(1 - min(0.30, too_many_roads * 0.03), 0.65, 1.0)
        scene_multipliers["road"] = road_factor
        scene_multipliers["remote"] = clamp(road_factor * 0.92, 0.60, 1.0)
    if more_city:
        scene_multipliers["city"] = clamp(1 + min(0.25, more_city * 0.03), 1.0, 1.25)

    country_multipliers = {}
    if recent_visits:
        recent_total = len(recent_visits)
        for country, count_value in recent_country_counts.items():
            share = count_value / recent_total
            if count_value >= 3 and share > 0.10:
                country_multipliers[country] = round(clamp(1 - (share - 0.10) * 2.0, 0.55, 0.95), 3)

    continent_multipliers = {}
    if recent_visits:
        recent_total = len(recent_visits)
        for continent, count_value in recent_continent_counts.items():
            share = count_value / recent_total
            if share > 0.25:
                continent_multipliers[continent] = round(clamp(1 - (share - 0.25), 0.75, 0.98), 3)

    return {
        "schemaVersion": 1,
        "source": "telemetry aggregate",
        "targetCityShare": 0.35,
        "minimumWeightMultiplier": 0.08,
        "recentScenePenalty": 1.25,
        "recentCountryPenalty": 1.15,
        "recentContinentPenalty": 0.55,
        "recentDensityPenalty": 0.85,
        "nonCityClusterPenalty": 1.65,
        "longTermExplorationBoost": 0.35,
        "feedbackInfluence": 0.25,
        "sceneMultipliers": scene_multipliers,
        "countryMultipliers": country_multipliers,
        "continentMultipliers": continent_multipliers,
    }


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main():
    events = load_events()
    visits = [event for event in events if event.get("kind") == "visitRecorded"]
    metadata = [event for event in events if event.get("kind") == "metadataResult"]
    feedback = [event for event in events if event.get("kind") == "feedbackGiven"]
    generated_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    summary = {
        "schemaVersion": 1,
        "generatedAt": generated_at,
        "eventCount": len(events),
        "visitCount": len(visits),
        "metadataCount": len(metadata),
        "feedbackCount": len(feedback),
        "eventsByKind": count(events, "kind"),
        "visitsBySceneKind": count(visits, "sceneKind"),
        "visitsByCountry": count(visits, "countryLabel"),
        "visitsByContinent": count(visits, "continentLabel"),
        "metadataByStatus": count(metadata, "status"),
        "feedbackByKind": count(feedback, "feedbackKind"),
    }

    attempts = [event.get("attempts") for event in visits if isinstance(event.get("attempts"), int)]
    if attempts:
        summary["visitAttempts"] = {
            "average": round(sum(attempts) / len(attempts), 3),
            "max": max(attempts),
        }

    config = generated_config(events)
    config["source"] = f"telemetry aggregate generated {generated_at}"

    write_json(SUMMARY, summary)
    write_json(CONFIG, config)


if __name__ == "__main__":
    main()
