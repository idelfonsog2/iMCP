import Foundation
import MCP
import MapKit
import EventKit
import CoreLocation
import OSLog
import Ontology

private let log = Logger.service("travel-planning")

final class TravelPlanningService: Service {
    static let shared: TravelPlanningService = TravelPlanningService()
    
    // Swift Actor-based agents
    private let spatialAgent = SpatialAgent()
    private let temporalAgent = TemporalAgent()
    private let contextAgent = ContextAgent()
    private let parsingAgent = ParsingAgent()
    private let collaborationAgent = CollaborationAgent()
    
    var tools: [Tool] {
        // Tool 1: Parse natural language input into structured activities
        Tool(
            name: "travel_parse_input",
            description: "Parse natural language travel input into structured activity data. Handles phrases like 'dinner at 8pm', 'Louvre Museum tomorrow', 'meet John at cafe'.",
            inputSchema: .object(
                properties: [
                    "input": .string(
                        description: "Natural language input to parse"
                    ),
                    "tripContext": .object(
                        description: "Current trip context for better parsing",
                        properties: [
                            "currentLocation": .string(),
                            "tripDates": .object(
                                properties: [
                                    "startDate": .string(format: .dateTime),
                                    "endDate": .string(format: .dateTime)
                                ]
                            ),
                            "existingActivities": .array(items: .object())
                        ]
                    )
                ],
                required: ["input"]
            ),
            annotations: .init(
                title: "Parse Travel Input",
                readOnlyHint: false,
                openWorldHint: true
            )
        ) { arguments in
            return try await self.parseNaturalLanguageInput(arguments: arguments)
        }
        
        // Tool 2: Real-time conflict detection
        Tool(
            name: "travel_detect_conflicts",
            description: "Detect scheduling and routing conflicts in a trip itinerary in real-time.",
            inputSchema: .object(
                properties: [
                    "activities": .array(
                        description: "Array of trip activities to check for conflicts",
                        items: .object(
                            properties: [
                                "id": .string(),
                                "name": .string(),
                                "startTime": .string(format: .dateTime),
                                "endTime": .string(format: .dateTime),
                                "location": .object(
                                    properties: [
                                        "name": .string(),
                                        "latitude": .number(),
                                        "longitude": .number()
                                    ]
                                )
                            ]
                        )
                    ),
                    "transportMode": .string(
                        default: "walking",
                        enum: ["walking", "driving", "transit"]
                    )
                ],
                required: ["activities"]
            ),
            annotations: .init(
                title: "Detect Travel Conflicts",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { arguments in
            return try await self.detectTravelConflicts(arguments: arguments)
        }
        
        // Tool 3: Smart activity suggestions
        Tool(
            name: "travel_suggest_activities",
            description: "Suggest activities based on location, time gaps, and user preferences.",
            inputSchema: .object(
                properties: [
                    "location": .object(
                        properties: [
                            "latitude": .number(),
                            "longitude": .number(),
                            "radius": .number(default: 1000)
                        ],
                        required: ["latitude", "longitude"]
                    ),
                    "timeSlot": .object(
                        properties: [
                            "startTime": .string(format: .dateTime),
                            "endTime": .string(format: .dateTime)
                        ],
                        required: ["startTime", "endTime"]
                    ),
                    "preferences": .array(
                        default: [], items: .string()
                    )
                ]
            ),
            annotations: .init(
                title: "Suggest Activities",
                readOnlyHint: true,
                openWorldHint: true
            )
        ) { arguments in
            return try await self.suggestActivities(arguments: arguments)
        }
        
        // Tool 4: Optimize trip routing
        Tool(
            name: "travel_optimize_route",
            description: "Optimize the order of activities to minimize travel time and maximize efficiency.",
            inputSchema: .object(
                properties: [
                    "activities": .array(
                        items: .object(
                            properties: [
                                "id": .string(),
                                "name": .string(),
                                "location": .object(
                                    properties: [
                                        "latitude": .number(),
                                        "longitude": .number()
                                    ]
                                ),
                                "flexibility": .string(
                                    default: "flexible", enum: ["fixed", "flexible", "very_flexible"]
                                ),
                                "duration": .number()
                            ]
                        )
                    ),
                    "startLocation": .object(
                        properties: [
                            "latitude": .number(),
                            "longitude": .number()
                        ]
                    ),
                    "transportMode": .string(default: "walking")
                ],
                required: ["activities"]
            ),
            annotations: .init(
                title: "Optimize Route",
                readOnlyHint: false,
                openWorldHint: false
            )
        ) { arguments in
            return try await self.optimizeTripRoute(arguments: arguments)
        }
        
        // Tool 5: Real-time collaboration
        Tool(
            name: "travel_sync_changes",
            description: "Sync trip changes across multiple users in real-time for collaborative planning.",
            inputSchema: .object(
                properties: [
                    "tripId": .string(),
                    "changes": .array(
                        items: .object(
                            properties: [
                                "type": .string(enum: ["add", "update", "delete"]),
                                "activityId": .string(),
                                "data": .object(),
                                "userId": .string(),
                                "timestamp": .string(format: .dateTime)
                            ]
                        )
                    ),
                    "userId": .string()
                ],
                required: ["tripId", "changes", "userId"]
            ),
            annotations: .init(
                title: "Sync Trip Changes",
                readOnlyHint: false,
                openWorldHint: false
            )
        ) { arguments in
            return try await self.syncTripChanges(arguments: arguments)
        }
    }
}

// MARK: - Implementation Methods

extension TravelPlanningService {
    
    private func parseNaturalLanguageInput(arguments: [String: Value]) async throws -> Value {
        guard let input = arguments["input"]?.stringValue else {
            throw TravelPlanningError.invalidInput
        }
        
        let tripContext = arguments["tripContext"]?.objectValue
        let parsedActivity = try await parsingAgent.parseInput(input, context: tripContext)
        
        if let activity = parsedActivity {
            return .object([
                "success": .bool(true),
                "activity": encodeActivity(activity),
                "confidence": .double(activity.confidence),
                "suggestions": .array(activity.suggestions.map { .string($0) })
            ])
        } else {
            return .object([
                "success": .bool(false),
                "error": .string("Could not parse input: \(input)"),
                "suggestions": .array([])
            ])
        }
    }
    
    private func detectTravelConflicts(arguments: [String: Value]) async throws -> Value {
        guard let activitiesData = arguments["activities"]?.arrayValue else {
            throw TravelPlanningError.invalidActivities
        }
        
        let activities = try parseActivities(activitiesData)
        let transportMode = arguments["transportMode"]?.stringValue ?? "walking"
        
        // Use both temporal and spatial agents for comprehensive conflict detection
        async let temporalConflicts = temporalAgent.detectSchedulingConflicts(activities)
        async let spatialConflicts = spatialAgent.detectRoutingConflicts(activities, transportMode: transportMode)
        
        let (timeConflicts, routeConflicts) = try await (temporalConflicts, spatialConflicts)
        
        return .object([
            "hasConflicts": .bool(!timeConflicts.isEmpty || !routeConflicts.isEmpty),
            "temporalConflicts": .array(timeConflicts.map { encodeConflict($0) }),
            "spatialConflicts": .array(routeConflicts.map { encodeConflict($0) }),
            "recommendations": .array((timeConflicts + routeConflicts).flatMap { $0.recommendations }.map { .string($0) })
        ])
    }
    
    private func suggestActivities(arguments: [String: Value]) async throws -> Value {
        guard let locationData = arguments["location"]?.objectValue,
              let lat = locationData["latitude"]?.doubleValue,
              let lng = locationData["longitude"]?.doubleValue,
              let timeSlotData = arguments["timeSlot"]?.objectValue,
              let startTimeStr = timeSlotData["startTime"]?.stringValue,
              let endTimeStr = timeSlotData["endTime"]?.stringValue,
              let startTime = ISO8601DateFormatter().date(from: startTimeStr),
              let endTime = ISO8601DateFormatter().date(from: endTimeStr) else {
            throw TravelPlanningError.invalidInput
        }
        
        let location = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        let radius = locationData["radius"]?.doubleValue ?? 1000
        let preferences = arguments["preferences"]?.arrayValue?.compactMap { $0.stringValue } ?? []
        
        // Use context agent to get contextual suggestions
        let suggestions = try await contextAgent.suggestActivities(
            location: location,
            radius: radius,
            timeSlot: DateInterval(start: startTime, end: endTime),
            preferences: preferences
        )
        
        return Value.object([
            "suggestions": Value.array(suggestions.map { suggestion in
                Value.object([
                    "name": Value.string(suggestion.name),
                    "category": Value.string(suggestion.category),
                    "location": Value.object([
                        "latitude": Value.double(suggestion.coordinate.latitude),
                        "longitude": Value.double(suggestion.coordinate.longitude),
                        "name": Value.string(suggestion.locationName)
                    ]),
                    "estimatedDuration": Value.double(suggestion.estimatedDuration),
                    "confidence": Value.double(suggestion.confidence),
                    "reason": Value.string(suggestion.reason)
                ])
            }),
            "contextualFactors": .array(suggestions.compactMap { $0.contextualFactor }.map { .string($0) })
        ])
    }
    
    private func optimizeTripRoute(arguments: [String: Value]) async throws -> Value {
        guard let activitiesData = arguments["activities"]?.arrayValue else {
            throw TravelPlanningError.invalidActivities
        }
        
        let activities = try parseActivities(activitiesData)
        let transportMode = arguments["transportMode"]?.stringValue ?? "walking"
        
        let startLocation = arguments["startLocation"]?.objectValue.flatMap { (locationData: [String: Value]) -> CLLocationCoordinate2D? in
            guard let lat = locationData["latitude"]?.doubleValue, let lng = locationData["longitude"]?.doubleValue else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        
        let optimization = try await spatialAgent.optimizeRoute(
            activities,
            startLocation: startLocation,
            transportMode: transportMode
        )
        
        return Value.object([
            "optimizedOrder": Value.array(optimization.optimizedOrder.map { Value.string($0) }),
            "totalTimeSaved": Value.double(optimization.timeSavings),
            "totalDistance": Value.double(optimization.totalDistance),
            "recommendations": Value.array(optimization.recommendations.map { Value.string($0) }),
            "routeSegments": Value.array(optimization.routeSegments.map { segment in
                Value.object([
                    "from": Value.string(segment.from),
                    "to": Value.string(segment.to),
                    "duration": Value.double(segment.duration),
                    "distance": Value.double(segment.distance),
                    "mode": Value.string(segment.transportMode)
                ])
            })
        ])
    }
    
    private func syncTripChanges(arguments: [String: Value]) async throws -> Value {
        guard let tripId = arguments["tripId"]?.stringValue,
              let changesData = arguments["changes"]?.arrayValue,
              let userId = arguments["userId"]?.stringValue else {
            throw TravelPlanningError.invalidInput
        }
        
        let changes = try parseChanges(changesData)
        let syncResult = try await collaborationAgent.syncChanges(
            tripId: tripId,
            changes: changes,
            userId: userId
        )
        
        return .object([
            "success": .bool(syncResult.success),
            "conflicts": .array(syncResult.conflicts.map { conflict in
                .object([
                    "type": .string(conflict.type),
                    "description": .string(conflict.description),
                    "resolution": .string(conflict.suggestedResolution)
                ])
            }),
            "appliedChanges": .array(syncResult.appliedChanges.map { .string($0) }),
            "nextSyncToken": .string(syncResult.nextSyncToken)
        ])
    }
    
    // MARK: - Helper Methods
    
    private func parseActivities(_ activitiesData: [Value]) throws -> [TripActivity] {
        return try activitiesData.compactMap { activityValue in
            guard let activityObj = activityValue.objectValue,
                  let id = activityObj["id"]?.stringValue,
                  let name = activityObj["name"]?.stringValue,
                  let startTimeStr = activityObj["startTime"]?.stringValue,
                  let endTimeStr = activityObj["endTime"]?.stringValue,
                  let startTime = ISO8601DateFormatter().date(from: startTimeStr),
                  let endTime = ISO8601DateFormatter().date(from: endTimeStr),
                  let locationObj = activityObj["location"]?.objectValue,
                  let locationName = locationObj["name"]?.stringValue,
                  let lat = locationObj["latitude"]?.doubleValue,
                  let lng = locationObj["longitude"]?.doubleValue else {
                return nil
            }
            
            return TripActivity(
                id: id,
                name: name,
                startTime: startTime,
                endTime: endTime,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                locationName: locationName
            )
        }
    }
    
    private func parseChanges(_ changesData: [Value]) throws -> [TripChange] {
        return try changesData.compactMap { changeValue in
            guard let changeObj = changeValue.objectValue,
                  let type = changeObj["type"]?.stringValue,
                  let activityId = changeObj["activityId"]?.stringValue,
                  let userId = changeObj["userId"]?.stringValue,
                  let timestampStr = changeObj["timestamp"]?.stringValue,
                  let timestamp = ISO8601DateFormatter().date(from: timestampStr) else {
                return nil
            }
            
            return TripChange(
                type: TripChangeType(rawValue: type) ?? .update,
                activityId: activityId,
                data: changeObj["data"]?.objectValue ?? [:],
                userId: userId,
                timestamp: timestamp
            )
        }
    }
    
    private func encodeActivity(_ activity: ParsedActivity) -> Value {
        return .object([
            "name": .string(activity.name),
            "category": .string(activity.category),
            "startTime": .string(ISO8601DateFormatter().string(from: activity.startTime)),
            "endTime": .string(ISO8601DateFormatter().string(from: activity.endTime)),
            "location": .object([
                "name": .string(activity.locationName),
                "latitude": .double(activity.coordinate.latitude),
                "longitude": .double(activity.coordinate.longitude)
            ]),
            "estimatedDuration": .double(activity.estimatedDuration),
            "confidence": .double(activity.confidence)
        ])
    }
    
    private func encodeConflict(_ conflict: TravelConflict) -> Value {
        return .object([
            "type": .string(conflict.type.rawValue),
            "severity": .string(conflict.severity.rawValue),
            "description": .string(conflict.description),
            "affectedActivities": .array(conflict.affectedActivityIds.map { .string($0) }),
            "recommendations": .array(conflict.recommendations.map { .string($0) }),
            "estimatedImpact": .double(conflict.estimatedImpact)
        ])
    }
}

// MARK: - Data Models

struct TripActivity {
    let id: String
    let name: String
    let startTime: Date
    let endTime: Date
    let coordinate: CLLocationCoordinate2D
    let locationName: String
}

struct ParsedActivity {
    let name: String
    let category: String
    let startTime: Date
    let endTime: Date
    let coordinate: CLLocationCoordinate2D
    let locationName: String
    let estimatedDuration: TimeInterval
    let confidence: Double
    let suggestions: [String]
}

struct TravelConflict {
    let type: ConflictType
    let severity: ConflictSeverity
    let description: String
    let affectedActivityIds: [String]
    let recommendations: [String]
    let estimatedImpact: TimeInterval
    
    enum ConflictType: String {
        case impossibleTransition = "impossible_transition"
        case scheduleOverlap = "schedule_overlap"
        case calendarConflict = "calendar_conflict"
        case weatherImpact = "weather_impact"
    }
    
    enum ConflictSeverity: String {
        case low, medium, high
    }
}

struct ActivitySuggestion {
    let name: String
    let category: String
    let coordinate: CLLocationCoordinate2D
    let locationName: String
    let estimatedDuration: TimeInterval
    let confidence: Double
    let reason: String
    let contextualFactor: String?
}

struct RouteOptimization {
    let optimizedOrder: [String]
    let timeSavings: TimeInterval
    let totalDistance: Double
    let recommendations: [String]
    let routeSegments: [RouteSegment]
}

struct RouteSegment {
    let from: String
    let to: String
    let duration: TimeInterval
    let distance: Double
    let transportMode: String
}

struct RouteResult {
    let duration: TimeInterval
    let distance: Double
}

struct TripChange {
    let type: TripChangeType
    let activityId: String
    let data: [String: Value]
    let userId: String
    let timestamp: Date
}

enum TripChangeType: String {
    case add, update, delete
}

struct TripSession {
    let tripId: String
    var pendingChanges: [TripChange] = []
    let createdAt: Date = Date()
}

struct SyncResult {
    let success: Bool
    let appliedChanges: [String]
    let conflicts: [SyncConflict]
    let nextSyncToken: String
}

struct SyncConflict {
    let type: String
    let description: String
    let suggestedResolution: String
}

struct ChangeResult {
    let success: Bool
    let conflicts: [SyncConflict]
}

enum TravelPlanningError: Swift.Error {
    case invalidInput
    case invalidActivities
    case sessionNotFound
    case parsingFailed
}


/*
Now Claude Desktop can use these tools:

## Example 1: Natural Language Parsing
User: "Add dinner at 8pm tomorrow"

Claude: I'll parse that for you.
[Calls: travel_parse_input]
{
    "input": "dinner at 8pm tomorrow"
}

Response: Successfully parsed as restaurant activity at 8:00 PM with 85% confidence

## Example 2: Conflict Detection  
User: "Check my itinerary for conflicts"

Claude: Let me check for scheduling and routing conflicts.
[Calls: travel_detect_conflicts]
{
    "activities": [
        {
            "id": "1",
            "name": "Louvre Museum", 
            "startTime": "2024-06-15T14:00:00Z",
            "endTime": "2024-06-15T17:00:00Z",
            "location": {"name": "Louvre", "latitude": 48.8606, "longitude": 2.3376}
        },
        {
            "id": "2", 
            "name": "Dinner at Le Comptoir",
            "startTime": "2024-06-15T19:00:00Z",
            "endTime": "2024-06-15T21:00:00Z", 
            "location": {"name": "Le Comptoir", "latitude": 48.8530, "longitude": 2.3412}
        }
    ],
    "transportMode": "walking"
}

Response: Found 1 conflict - only 30 minutes travel time between activities but you need 20 minutes walking

## Example 3: Route Optimization
Claude: Let me optimize your route to save time.
[Calls: travel_optimize_route]

Response: Reordered activities saves 45 minutes of total travel time

## Example 4: Activity Suggestions
User: "I have 2 hours free in the afternoon near the Eiffel Tower"

Claude: [Calls: travel_suggest_activities]
{
    "location": {"latitude": 48.8584, "longitude": 2.2945, "radius": 1000},
    "timeSlot": {"startTime": "2024-06-15T14:00:00Z", "endTime": "2024-06-15T16:00:00Z"}
}

Response: Found 5 nearby activities including Musée Rodin (15 min walk) and Seine river cruise

## Example 5: Real-time Collaboration
Claude: [Calls: travel_sync_changes]
When partner makes changes, automatically syncs and resolves conflicts

This creates the foundation for the unified travel planning experience!
*/
