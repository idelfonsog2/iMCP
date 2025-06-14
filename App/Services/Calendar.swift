import Foundation
import EventKit
import FoundationModels
import OSLog

private let log = Logger.service("calendar")

@available(macOS 26.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
class CalendarService: Service {
    let name = "Calendar"
    let description = "Access and manage calendar events"
    var isEnabled = false
    
    private let eventStore = EKEventStore()
    
    static let shared = CalendarService()
    
    var tools: [any Tool] {
        [
            ListCalendarsTool(),
            CreateEventTool(),
            FetchEventsTool()
        ]
    }
    
    func activate() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        
        switch status {
        case .notDetermined:
            let granted = try await eventStore.requestFullAccessToEvents()
            isEnabled = granted
        case .authorized, .fullAccess:
            isEnabled = true
        case .denied, .restricted, .writeOnly:
            isEnabled = false
            throw CalendarError.accessDenied
        @unknown default:
            isEnabled = false
            throw CalendarError.unknown
        }
    }
}

@available(macOS 26.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
struct ListCalendarsTool: Tool {
    let name = "list_calendars"
    let description = "List available calendars"
    
    @Generable
    struct Arguments {
        @Guide(description: "Optional filter for calendar type")
        let type: String?
        
        @Guide(description: "Include only modifiable calendars")
        let modifiableOnly: Bool
        
        init(type: String? = nil, modifiableOnly: Bool = false) {
            self.type = type
            self.modifiableOnly = modifiableOnly
        }
    }
    
    func call(arguments: Arguments) async throws -> ToolOutput {
        let eventStore = EKEventStore()
        let calendars = eventStore.calendars(for: .event)
        
        var filteredCalendars = calendars
        
        // Filter by type if specified
        if let typeFilter = arguments.type {
            filteredCalendars = filteredCalendars.filter { 
                $0.type.description.lowercased() == typeFilter.lowercased() 
            }
        }
        
        // Filter by modifiable if requested
        if arguments.modifiableOnly {
            filteredCalendars = filteredCalendars.filter { $0.allowsContentModifications }
        }
        
        let calendarInfos = filteredCalendars.map { calendar in
            CalendarInfo(
                identifier: calendar.calendarIdentifier,
                title: calendar.title,
                type: calendar.type.description,
                allowsContentModifications: calendar.allowsContentModifications
            )
        }
        
        let jsonData = try JSONEncoder().encode(calendarInfos)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
        
        return ToolOutput(jsonString)
    }
}

@available(macOS 26.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
private struct CreateEventTool: Tool {
    let name = "create_event"
    let description = "Create a new calendar event with specified properties"
    
    @Generable
    struct Arguments {
        @Guide(description: "Event title")
        let title: String
        
        @Guide(description: "Start date and time")
        let start: Date
        
        @Guide(description: "End date and time")
        let end: Date
        
        @Guide(description: "Calendar name to create event in")
        let calendar: String?
        
        @Guide(description: "Event location")
        let location: String?
        
        @Guide(description: "Event notes or description")
        let notes: String?
        
        @Guide(description: "Event URL")
        let url: String?
        
        @Guide(description: "Whether this is an all-day event")
        let isAllDay: Bool?
        
        @Guide(description: "Alarm offsets in minutes before event")
        let alarms: [Int]?
        
        @Guide(description: "Event availability status")
        let availability: String?
        
        @Guide(description: "Whether event should have alarms")
        let hasAlarms: Bool?
        
        @Guide(description: "Whether event is recurring")
        let isRecurring: Bool?
    }
    
    func call(arguments: Arguments) async throws -> ToolOutput {
        let eventStore = EKEventStore()
        let event = EKEvent(eventStore: eventStore)
        
        event.title = arguments.title
        event.startDate = arguments.start
        event.endDate = arguments.end
        event.isAllDay = arguments.isAllDay ?? false
        
        if let location = arguments.location {
            event.location = location
        }
        
        if let notes = arguments.notes {
            event.notes = notes
        }
        
        if let urlString = arguments.url, let url = URL(string: urlString) {
            event.url = url
        }
        
        // Set calendar
        if let calendarName = arguments.calendar {
            let calendars = eventStore.calendars(for: .event)
            event.calendar = calendars.first { $0.title == calendarName } ?? eventStore.defaultCalendarForNewEvents
        } else {
            event.calendar = eventStore.defaultCalendarForNewEvents
        }
        
        // Add alarms
        if let alarmMinutes = arguments.alarms, arguments.hasAlarms == true {
            event.alarms = alarmMinutes.map { EKAlarm(relativeOffset: TimeInterval(-$0 * 60)) }
        }
        
        // Set availability
        if let availabilityString = arguments.availability {
            switch availabilityString.lowercased() {
            case "busy":
                event.availability = .busy
            case "free":
                event.availability = .free
            case "tentative":
                event.availability = .tentative
            case "unavailable":
                event.availability = .unavailable
            default:
                event.availability = .busy
            }
        }
        
        try eventStore.save(event, span: .thisEvent)
        
        log.info("Created calendar event: \(event.title ?? "Untitled")")
        
        let result = EventResult(
            identifier: event.eventIdentifier,
            title: event.title ?? "",
            startDate: event.startDate,
            endDate: event.endDate,
            calendar: event.calendar?.title ?? "",
            created: true
        )
        
        let jsonData = try JSONEncoder().encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        return ToolOutput(jsonString)
    }
}

@available(macOS 26.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
private struct FetchEventsTool: Tool {
    let name = "fetch_events"
    let description = "Get events from the calendar with flexible filtering options"
    
    @Generable
    struct Arguments {
        @Guide(description: "Start date for event search")
        let start: Date?
        
        @Guide(description: "End date for event search") 
        let end: Date?
        
        @Guide(description: "Calendar names to search in")
        let calendars: [String]?
        
        @Guide(description: "Search query for event titles/locations")
        let query: String?
        
        @Guide(description: "Include all-day events")
        let includeAllDay: Bool?
        
        @Guide(description: "Filter by availability status")
        let availability: String?
        
        @Guide(description: "Filter by event status")
        let status: String?
        
        @Guide(description: "Filter by whether events have alarms")
        let hasAlarms: Bool?
        
        @Guide(description: "Filter by whether events are recurring")
        let isRecurring: Bool?
    }
    
    func call(arguments: Arguments) async throws -> ToolOutput {
        let eventStore = EKEventStore()
        
        let startDate = arguments.start ?? Date()
        let endDate = arguments.end ?? Calendar.current.date(byAdding: .weekOfYear, value: 1, to: startDate) ?? Date()
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        var filteredEvents = events
        
        // Filter by calendars
        if let calendarNames = arguments.calendars, !calendarNames.isEmpty {
            filteredEvents = filteredEvents.filter { event in
                calendarNames.contains(event.calendar.title)
            }
        }
        
        // Filter by query
        if let query = arguments.query {
            filteredEvents = filteredEvents.filter { event in
                event.title?.localizedCaseInsensitiveContains(query) == true ||
                event.location?.localizedCaseInsensitiveContains(query) == true
            }
        }
        
        // Filter by all-day
        if let includeAllDay = arguments.includeAllDay, !includeAllDay {
            filteredEvents = filteredEvents.filter { !$0.isAllDay }
        }
        
        // Filter by availability
        if let availabilityString = arguments.availability {
            let targetAvailability: EKEventAvailability
            switch availabilityString.lowercased() {
            case "busy": targetAvailability = .busy
            case "free": targetAvailability = .free
            case "tentative": targetAvailability = .tentative
            case "unavailable": targetAvailability = .unavailable
            default: targetAvailability = .busy
            }
            
            filteredEvents = filteredEvents.filter { $0.availability == targetAvailability }
        }
        
        // Filter by alarms
        if let hasAlarms = arguments.hasAlarms {
            filteredEvents = filteredEvents.filter { event in
                let eventHasAlarms = event.alarms?.isEmpty == false
                return eventHasAlarms == hasAlarms
            }
        }
        
        // Filter by recurring
        if let isRecurring = arguments.isRecurring {
            filteredEvents = filteredEvents.filter { event in
                let eventIsRecurring = event.hasRecurrenceRules
                return eventIsRecurring == isRecurring
            }
        }
        
        let eventInfos = filteredEvents.map { event in
            EventInfo(
                identifier: event.eventIdentifier,
                title: event.title ?? "",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                location: event.location,
                notes: event.notes,
                url: event.url?.absoluteString,
                calendar: event.calendar.title,
                availability: event.availability.description,
                hasAlarms: event.alarms?.isEmpty == false,
                isRecurring: event.hasRecurrenceRules,
                status: event.status.description
            )
        }
        
        let jsonData = try JSONEncoder().encode(eventInfos)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
        
        return ToolOutput(jsonString)
    }
}

// MARK: - Supporting Types

struct CalendarInfo: Codable {
    let identifier: String
    let title: String
    let type: String
    let allowsContentModifications: Bool
}

struct EventResult: Codable {
    let identifier: String
    let title: String
    let startDate: Date
    let endDate: Date
    let calendar: String
    let created: Bool
}

struct EventInfo: Codable {
    let identifier: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let url: String?
    let calendar: String
    let availability: String
    let hasAlarms: Bool
    let isRecurring: Bool
    let status: String
}

enum CalendarError: Error {
    case accessDenied
    case unknown
}

// MARK: - Extensions

extension EKCalendarType {
    var description: String {
        switch self {
        case .local: return "local"
        case .calDAV: return "caldav"
        case .exchange: return "exchange"
        case .subscription: return "subscription"
        case .birthday: return "birthday"
        @unknown default: return "unknown"
        }
    }
}

extension EKEventAvailability {
    var description: String {
        switch self {
        case .notSupported: return "none"
        case .busy: return "busy"
        case .free: return "free"
        case .tentative: return "tentative"
        case .unavailable: return "unavailable"
        @unknown default: return "unknown"
        }
    }
}

extension EKEventStatus {
    var description: String {
        switch self {
        case .none: return "none"
        case .confirmed: return "confirmed"
        case .tentative: return "tentative"
        case .canceled: return "canceled"
        @unknown default: return "unknown"
        }
    }
}
