import Foundation
import SwiftData

/// Populates a fresh, empty store with realistic demo data: one test group with
/// a known join code, ~10 test users, several weeks of past survey sign-ins,
/// group + DM chat messages, and a handful of sample locations.
///
/// Only ever runs once (checks for an existing `TeamGroup` first) — the person
/// who then runs onboarding becomes an additional, real `User` on top of this
/// seed data, not one of these ten.
enum MockDataSeeder {
    static let testGroupJoinCode = "LABOR2026"
    static let samplesAccessCode = "PROBEN2026"

    private struct SeedUser {
        let name: String
        let abbreviation: String
        let role: UserRole
    }

    private static let seedUsers: [SeedUser] = [
        SeedUser(name: "Johannes Emmrich", abbreviation: "JE", role: .admin),
        SeedUser(name: "Anna Weber", abbreviation: "AW", role: .member),
        SeedUser(name: "Markus Schulz", abbreviation: "MS", role: .member),
        SeedUser(name: "Laura Fischer", abbreviation: "LF", role: .member),
        SeedUser(name: "Tobias Klein", abbreviation: "TK", role: .member),
        SeedUser(name: "Sarah Hoffmann", abbreviation: "SH", role: .member),
        SeedUser(name: "David Wagner", abbreviation: "DW", role: .member),
        SeedUser(name: "Nina Becker", abbreviation: "NB", role: .member),
        SeedUser(name: "Paul Richter", abbreviation: "PR", role: .member),
        SeedUser(name: "Lea Zimmermann", abbreviation: "LZ", role: .member),
    ]

    static func seedIfNeeded(context: ModelContext) {
        let existingGroupCount = (try? context.fetchCount(FetchDescriptor<TeamGroup>())) ?? 0
        guard existingGroupCount == 0 else { return }

        let group = TeamGroup(name: "Laborteam Nord", joinCode: testGroupJoinCode)
        context.insert(group)

        let users = seedUsers.map { seed in
            User(name: seed.name, abbreviation: seed.abbreviation, role: seed.role, groupID: group.id)
        }
        users.forEach { context.insert($0) }

        seedSurveyDays(groupID: group.id, users: users, context: context)
        seedChatMessages(groupID: group.id, users: users, context: context)
        seedSampleLocations(groupID: group.id, context: context)

        try? context.save()
    }

    /// Seeds the past 3 full weeks plus the current week through today, Mon–Thu
    /// only, each with a deterministic 1–3 person rotation so the demo has
    /// realistic-looking variety without relying on true randomness.
    private static func seedSurveyDays(groupID: UUID, users: [User], context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let rangeStart = calendar.date(byAdding: .day, value: -21, to: today) else { return }

        var dayOffset = 0
        var cursor = rangeStart
        while cursor <= today {
            let weekday = calendar.component(.weekday, from: cursor) // 2...5 = Mon...Thu
            if (2...5).contains(weekday) {
                let day = SurveyDay(date: cursor, groupID: groupID)
                context.insert(day)

                for index in attendeeIndices(for: dayOffset) {
                    let entry = SurveyEntry(surveyDayID: day.id, userID: users[index].id, createdAt: cursor)
                    context.insert(entry)
                }
                dayOffset += 1
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? today.addingTimeInterval(86400 * 999)
        }
    }

    private static func attendeeIndices(for dayOffset: Int) -> [Int] {
        let a = dayOffset % 10
        let b = (dayOffset + 4) % 10
        let c = (dayOffset + 7) % 10
        switch dayOffset % 3 {
        case 0: return [a]
        case 1: return [a, b]
        default: return [a, b, c]
        }
    }

    private static func seedChatMessages(groupID: UUID, users: [User], context: ModelContext) {
        let now = Date.now
        func at(hoursAgo: Double) -> Date { now.addingTimeInterval(-hoursAgo * 3600) }

        let johannes = users[0]
        let anna = users[1]
        let markus = users[2]
        let laura = users[3]
        let tobias = users[4]

        let groupMessages: [(User, String, Double)] = [
            (johannes, "Hallo zusammen! Ab jetzt planen wir die Fahrten hier in der App.", 96),
            (anna, "Super, endlich kein Zettel mehr am schwarzen Brett 🙂", 95),
            (markus, "Ich trage mich für Donnerstag ein, hab da eh Termin in der Nähe.", 70),
            (laura, "Kann jemand morgen früh? Bin sonst erst ab Mittag im Labor.", 48),
            (tobias, "Ich kann morgen früh übernehmen.", 46.5),
            (laura, "Perfekt, danke dir!", 46),
            (johannes, "Denkt dran: neue Umfrage gilt immer für die nächsten zwei Wochen.", 24),
            (anna, "Alles klar, hab mich schon für nächste Woche eingetragen.", 5),
        ]
        for (user, text, hoursAgo) in groupMessages {
            context.insert(ChatMessage(groupID: groupID, senderID: user.id, text: text, createdAt: at(hoursAgo: hoursAgo)))
        }

        let dmMessages: [(User, User, String, Double)] = [
            (anna, markus, "Hey, kannst du Freitag für mich tauschen?", 30),
            (markus, anna, "Klar, kein Problem. Trag ich mich ein.", 29),
            (anna, markus, "Danke dir, du rettest mich 🙏", 29),
            (markus, anna, "Passt schon, mach ich gern.", 28),
        ]
        for (sender, recipient, text, hoursAgo) in dmMessages {
            context.insert(ChatMessage(groupID: groupID, senderID: sender.id, recipientID: recipient.id, text: text, createdAt: at(hoursAgo: hoursAgo)))
        }
    }

    private static func seedSampleLocations(groupID: UUID, context: ModelContext) {
        let locations: [(String, String, Bool, String)] = [
            ("Apotheke Sonnenschein", "Hauptstraße 12", true, "Ja, wir haben Proben"),
            ("Labor Nordstadt", "Industrieweg 4", false, ""),
            ("Apotheke am Markt", "Marktplatz 3", true, "Ja, wir haben Proben"),
            ("Zentrallabor Ost", "Ostring 88", false, ""),
            ("Apotheke Hirsch", "Bahnhofstraße 21", false, ""),
            ("Labor Weststadt", "Westallee 9", true, "Ja, mehrere Proben abholbereit"),
        ]
        for (name, address, hasSamples, note) in locations {
            context.insert(SampleLocation(groupID: groupID, name: name, address: address, hasSamples: hasSamples, statusNote: note))
        }
    }
}
