import Foundation
import MCP
import MapKit
import EventKit
import CoreLocation
import OSLog
import Ontology

private let log = Logger.service("travel-planning")

actor TemporalAgent {
    private let calendarService = CalendarService.shared
    
    func detectSchedulingConflicts(_ activities: [TripActivity]) async throws -> [TravelConflict] {
        var conflicts: [TravelConflict] = []
        
        guard activities.count > 1 else { return conflicts }
        // Check for overlapping activities using efficient pairwise comparison
        for (i, activity1) in activities.enumerated() {
            for activity2 in activities.dropFirst(i + 1) {
                if activitiesOverlap(activity1, activity2) {
                    conflicts.append(TravelConflict(
                        type: .scheduleOverlap,
                        severity: .high,
                        description: "\(activity1.name) overlaps with \(activity2.name)",
                        affectedActivityIds: [activity1.id, activity2.id],
                        recommendations: [
                            "Adjust timing of one activity",
                            "Consider shorter duration for one activity"
                        ],
                        estimatedImpact: overlapDuration(activity1, activity2)
                    ))
                }
            }
        }
        
        // Check against existing calendar events
        if await calendarService.isActivated {
            let detectedConflicts = try await checkCalendarConflicts(activities)
            conflicts.append(contentsOf: detectedConflicts)
        }
        
        return conflicts
    }
    
    private func activitiesOverlap(_ a1: TripActivity, _ a2: TripActivity) -> Bool {
        return a1.startTime < a2.endTime && a2.startTime < a1.endTime
    }
    
    private func overlapDuration(_ a1: TripActivity, _ a2: TripActivity) -> TimeInterval {
        let overlapStart = max(a1.startTime, a2.startTime)
        let overlapEnd = min(a1.endTime, a2.endTime)
        return max(0, overlapEnd.timeIntervalSince(overlapStart))
    }
    
    private func checkCalendarConflicts(_ activities: [TripActivity]) async throws -> [TravelConflict] {
        // Check against user's calendar for conflicts
        // Implementation would use CalendarService to fetch events
        return []
    }
}
