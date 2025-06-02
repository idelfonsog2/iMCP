Parse the following activity, I want to get to each one using public transit:Trip Name: Paris Weekend
Activities:
1. Louvre Museum
   * Time: 10:00 AM - 1:00 PM (3 hours)
   * Location: Musée du Louvre (48.8606°N, 2.3376°E)
   * Category: Museum
   * Duration: 3 hours
2. Lunch at Café de Flore
   * Time: 2:00 PM - 3:00 PM (1 hour)
   * Location: Café de Flore (48.8542°N, 2.3325°E)
   * Category: Restaurant
   * Duration: 1 hour
3. Eiffel Tower
   * Time: 2:30 PM - 6:00 PM (2 hours)
   * Location: Tour Eiffel (48.8584°N, 2.2945°E)
   * Category: Landmark
   * Duration: 2 hoursEditI'll parse these activities and check for conflicts, then provide public transit routing between them. First, let me detect any scheduling conflicts:Ttravel_detect_conflictsRequest{
  `activities`: [
    {
      `id`: `1`,
      `name`: `Louvre Museum`,
      `endTime`: `2025-06-01T13:00:00`,
      `location`: {
        `name`: `Musée du Louvre`,
        `latitude`: 48.8606,
        `longitude`: 2.3376
      },
      `startTime`: `2025-06-01T10:00:00`
    },
    {
      `id`: `2`,
      `name`: `Lunch at Café de Flore`,
      `endTime`: `2025-06-01T15:00:00`,
      `location`: {
        `name`: `Café de Flore`,
        `latitude`: 48.8542,
        `longitude`: 2.3325
      },
      `startTime`: `2025-06-01T14:00:00`
    },
    {
      `id`: `3`,
      `name`: `Eiffel Tower`,
      `endTime`: `2025-06-01T18:00:00`,
      `location`: {
        `name`: `Tour Eiffel`,
        `latitude`: 48.8584,
        `longitude`: 2.2945
      },
      `startTime`: `2025-06-01T14:30:00`
    }
  ],
  `transportMode`: `transit`
}Response{"hasConflicts":false,"recommendations":[],"spatialConflicts":[],"temporalConflicts":[]}⚠️ SCHEDULING CONFLICT DETECTED!
There's an overlap between your lunch and Eiffel Tower activities:

Lunch at Café de Flore: 2:00 PM - 3:00 PM
Eiffel Tower: 2:30 PM - 6:00 PM

Your lunch and Eiffel Tower visit overlap by 30 minutes (2:30-3:00 PM).
Now let me get public transit directions between each location:Mmaps_directionsRequest{
  `transportType`: `transit`,
  `originCoordinates`: {
    `latitude`: 48.8606,
    `longitude`: 2.3376
  },
  `destinationCoordinates`: {
    `latitude`: 48.8542,
    `longitude`: 2.3325
  }
}ResponseError: Error Domain=MKErrorDomain Code=5 "(null)"Mmaps_directionsRequest{
  `originAddress`: `Musée du Louvre, Paris, France`,
  `transportType`: `transit`,
  `destinationAddress`: `Café de Flore, Paris, France`
}ResponseError: Error Domain=MKErrorDomain Code=5 "(null)"Let me try getting ETAs for public transit:Mmaps_etaRequest{
  `transportType`: `transit`,
  `originLatitude`: 48.8606,
  `originLongitude`: 2.3376,
  `destinationLatitude`: 48.8542,
  `destinationLongitude`: 2.3325
}Response{"@context":"https://schema.org","@type":"Trip","arrivalTime":"2025-06-01T17:13:22.000-04:00","departureTime":"2025-06-01T17:00:40.000-04:00","itinerary":[{"@type":"Place","address":{"@type":"PostalAddress"},"geo":{"@type":"GeoCoordinates","elevation":0,"latitude":48.8542,"longitude":2.3325}}],"tripOrigin":{"@type":"Place","address":{"@type":"PostalAddress"},"geo":{"@type":"GeoCoordinates","elevation":0,"latitude":48.8606,"longitude":2.3376}}}Mmaps_etaRequest{
  `transportType`: `transit`,
  `originLatitude`: 48.8542,
  `originLongitude`: 2.3325,
  `destinationLatitude`: 48.8584,
  `destinationLongitude`: 2.2945
}Response{"@context":"https://schema.org","@type":"Trip","arrivalTime":"2025-06-01T17:27:11.000-04:00","departureTime":"2025-06-01T16:57:11.000-04:00","itinerary":[{"@type":"Place","address":{"@type":"PostalAddress"},"geo":{"@type":"GeoCoordinates","elevation":0,"latitude":48.8584,"longitude":2.2945}}],"tripOrigin":{"@type":"Place","address":{"@type":"PostalAddress"},"geo":{"@type":"GeoCoordinates","elevation":0,"latitude":48.8542,"longitude":2.3325}}}

Paris Weekend Itinerary - Public Transit Analysis
⚠️ CRITICAL SCHEDULING ISSUE:
Your Lunch at Café de Flore (2:00-3:00 PM) overlaps with your Eiffel Tower visit (2:30-6:00 PM) by 30 minutes.
Recommended Fix:
Option 1: Shorten lunch to 2:00-2:15 PM, then travel to Eiffel Tower
Option 2: Move Eiffel Tower to 3:15 PM start time

Public Transit Times:
Louvre → Café de Flore: ~13 minutes by transit
Depart: 1:00 PM → Arrive: 1:13 PM (perfect for 2:00 PM lunch)
Café de Flore → Eiffel Tower: ~30 minutes by transit

You'd need to leave lunch by 2:45 PM to reach Eiffel Tower by 3:15 PM
Revised Schedule Suggestion:

Louvre Museum: 10:00 AM - 1:00 PM ✅
Travel: 1:00-1:15 PM (transit to café)
Lunch at Café de Flore: 2:00 PM - 2:45 PM (shortened)
Travel: 2:45-3:15 PM (transit to Eiffel Tower)
Eiffel Tower: 3:15 PM - 6:00 PM

This gives you a more realistic timeline using Paris public transit while avoiding the scheduling conflict!