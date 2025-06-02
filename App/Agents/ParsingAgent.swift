import CoreLocation
import EventKit
import Foundation
import MCP
import MapKit
import OSLog
import Ontology
import RegexBuilder

private let log = Logger.service("travel-planning")

actor ParsingAgent {
    func parseInput(_ input: String, context: [String: Value]?) async throws -> ParsedActivity? {
        let lowercaseInput = input.lowercased()

        // Extract time information
        let timeResult: (startTime: Date?, endTime: Date?) = extractTime(from: input)

        // Extract location information
        let locationResult: (coordinate: CLLocationCoordinate2D?, name: String?) = extractLocation(
            from: input)

        // Determine activity type
        let category: String = determineCategory(from: input)

        // Extract activity name
        let name: String = extractActivityName(from: input, category: category)

        guard let startTime: Date = timeResult.startTime else {
            return nil
        }

        let endTime = timeResult.endTime ?? startTime.addingTimeInterval(3600)  // Default 1 hour

        return ParsedActivity(
            name: name,
            category: category,
            startTime: startTime,
            endTime: endTime,
            coordinate: locationResult.coordinate
                ?? CLLocationCoordinate2D(latitude: 0, longitude: 0),
            locationName: locationResult.name ?? "TBD",
            estimatedDuration: endTime.timeIntervalSince(startTime),
            confidence: calculateConfidence(
                input: input, hasTime: timeResult.startTime != nil,
                hasLocation: locationResult.coordinate != nil),
            suggestions: generateSuggestions(for: input)
        )
    }

    private func extractTime(from input: String) -> (startTime: Date?, endTime: Date?) {
        // Define regex patterns using RegexBuilder
        let timeWithAmPm = Regex {
            Capture {
                One(.digit)
                Optionally {
                    One(.digit)
                }
            }
            Optionally {
                ":"
                Capture {
                    Repeat(.digit, count: 2)
                }
            }
            ZeroOrMore(.whitespace)
            Capture {
                ChoiceOf {
                    "am"
                    "pm"
                    "AM"
                    "PM"
                }
            }
        }

        let timeWithAt = Regex {
            "at"
            OneOrMore(.whitespace)
            Capture {
                One(.digit)
                Optionally {
                    One(.digit)
                }
            }
            Optionally {
                ":"
                Capture {
                    Repeat(.digit, count: 2)
                }
            }
            Optionally {
                ZeroOrMore(.whitespace)
                Capture {
                    ChoiceOf {
                        "am"
                        "pm"
                        "AM"
                        "PM"
                    }
                }
            }
        }

        let timeRange = Regex {
            "from"
            OneOrMore(.whitespace)
            Capture {
                One(.digit)
                Optionally {
                    One(.digit)
                }
            }
            Optionally {
                ":"
                Capture {
                    Repeat(.digit, count: 2)
                }
            }
            Optionally {
                ZeroOrMore(.whitespace)
                Capture {
                    ChoiceOf {
                        "am"
                        "pm"
                        "AM"
                        "PM"
                    }
                }
            }
            OneOrMore(.whitespace)
            "to"
            OneOrMore(.whitespace)
            Capture {
                One(.digit)
                Optionally {
                    One(.digit)
                }
            }
            Optionally {
                ":"
                Capture {
                    Repeat(.digit, count: 2)
                }
            }
            Optionally {
                ZeroOrMore(.whitespace)
                Capture {
                    ChoiceOf {
                        "am"
                        "pm"
                        "AM"
                        "PM"
                    }
                }
            }
        }

        // Try to match time range first
        if let match = input.firstMatch(of: timeRange) {
            let startTime = createDate(
                hour: Int(match.output.1) ?? 0,
                minute: Int(match.output.2 ?? "0") ?? 0,
                amPm: String(match.output.3 ?? "")
            )
            let endTime = createDate(
                hour: Int(match.output.4) ?? 0,
                minute: Int(match.output.5 ?? "0") ?? 0,
                amPm: String(match.output.6 ?? "")
            )

            return (startTime, endTime)
        }

        // Try to match time with "at"
        if let match = input.firstMatch(of: timeWithAt) {
            let hour = Int(match.output.1) ?? 0
            let minute = Int(match.output.2 ?? "0") ?? 0
            let amPm = String(match.output.3 ?? "")

            let time = createDate(hour: hour, minute: minute, amPm: amPm)
            return (time, nil)
        }

        // Try to match regular time with am/pm
        if let match = input.firstMatch(of: timeWithAmPm) {
            let hour = Int(match.output.1) ?? 0
            let minute = Int(match.output.2 ?? "0") ?? 0
            let amPm = String(match.output.3)

            let time = createDate(hour: hour, minute: minute, amPm: amPm)
            return (time, nil)
        }

        return (nil, nil)
    }

    private func extractLocation(from input: String) -> (
        coordinate: CLLocationCoordinate2D?, name: String?
    ) {
        // Define location extraction regex
        let locationPattern = Regex {
            ChoiceOf {
                "at"
                "in"
                "near"
                "by"
            }
            OneOrMore(.whitespace)
            Capture {
                OneOrMore {
                    ChoiceOf {
                        .word
                            .whitespace
                        "'"
                        "-"
                    }
                }
            }
        }

        if let match = input.firstMatch(of: locationPattern) {
            let locationName = String(match.output.1)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (nil, locationName)
        }

        return (nil, nil)
    }

    private func extractActivityName(from input: String, category: String) -> String {
        // Remove time patterns using regex
        let timePattern = Regex {
            ChoiceOf {
                // Pattern for "8pm", "8:30pm", etc.
                Regex {
                    One(.digit)
                    Optionally {
                        One(.digit)
                    }
                    Optionally {
                        ":"
                        Repeat(.digit, count: 2)
                    }
                    ZeroOrMore(.whitespace)
                    ChoiceOf {
                        "am"
                        "pm"
                        "AM"
                        "PM"
                    }
                }
                // Pattern for "at 8", "at 8:30", etc.
                Regex {
                    "at"
                    OneOrMore(.whitespace)
                    One(.digit)
                    Optionally {
                        One(.digit)
                    }
                    Optionally {
                        ":"
                        Repeat(.digit, count: 2)
                    }
                }
            }
        }

        let locationPattern = Regex {
            OneOrMore(.whitespace)
            ChoiceOf {
                "at"
                "in"
                "near"
                "by"
            }
            OneOrMore(.whitespace)
            OneOrMore(.word)
        }

        var cleanedInput = input

        // Remove time patterns
        cleanedInput = cleanedInput.replacing(timePattern, with: "")

        // Remove location patterns
        cleanedInput = cleanedInput.replacing(locationPattern, with: "")

        return
            cleanedInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized
    }

    private func createDate(hour: Int, minute: Int, amPm: String) -> Date? {
        let calendar = Calendar.current
        let now = Date()

        var adjustedHour = hour

        // Handle AM/PM conversion
        if amPm.lowercased() == "pm" && hour != 12 {
            adjustedHour += 12
        } else if amPm.lowercased() == "am" && hour == 12 {
            adjustedHour = 0
        }

        return calendar.date(bySettingHour: adjustedHour, minute: minute, second: 0, of: now)
    }

    private func determineCategory(from input: String) -> String {
        let categoryKeywords: [String: String] = [
            "dinner": "restaurant",
            "lunch": "restaurant",
            "breakfast": "restaurant",
            "eat": "restaurant",
            "museum": "museum",
            "hotel": "accommodation",
            "flight": "transportation",
            "meeting": "business",
            "coffee": "cafe",
        ]

        for (keyword, category) in categoryKeywords {
            if input.localizedCaseInsensitiveContains(keyword) {
                return category
            }
        }

        return "activity"
    }

    private func calculateConfidence(input: String, hasTime: Bool, hasLocation: Bool) -> Double {
        var confidence = 0.3  // Base confidence

        if hasTime { confidence += 0.4 }
        if hasLocation { confidence += 0.3 }

        return min(1.0, confidence)
    }

    private func generateSuggestions(for input: String) -> [String] {
        var suggestions: [String] = []

        let timePattern = Regex {
            ChoiceOf {
                Regex {
                    One(.digit)
                    Optionally {
                        One(.digit)
                    }
                    ":"
                    Repeat(.digit, count: 2)
                }
                Regex {
                    ChoiceOf {
                        "am"
                        "pm"
                        "AM"
                        "PM"
                    }
                }
            }
        }

        let locationPattern = Regex {
            ChoiceOf {
                "at"
                "in"
                "near"
                "by"
            }
        }

        if input.firstMatch(of: timePattern) == nil {
            suggestions.append("Try adding a specific time, like 'at 7pm'")
        }

        if input.firstMatch(of: locationPattern) == nil {
            suggestions.append("Add a location like 'at the restaurant' or 'in downtown'")
        }

        return suggestions
    }

    private func generateSuggestions(for input: String) -> [String] {
        // Generate helpful suggestions for ambiguous input
        var suggestions: [String] = []

        if !input.contains(":") && !input.contains("am") && !input.contains("pm") {
            suggestions.append("Try adding a specific time, like 'at 7pm'")
        }

        if !input.contains("at") && !input.contains("in") {
            suggestions.append("Add a location like 'at the restaurant' or 'in downtown'")
        }

        return suggestions
    }
}
