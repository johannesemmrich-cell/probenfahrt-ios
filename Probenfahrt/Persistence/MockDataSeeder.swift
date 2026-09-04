import Foundation

/// Ensures the CloudKit-backed group real users join against exists (known
/// join codes, no members yet) — idempotent, safe to call on every launch,
/// since `CloudKitUserRepository.ensureGroupExists` finds-or-creates by a
/// deterministic record ID rather than always inserting a new one.
///
/// In Debug builds only, additionally fills that group with realistic demo
/// data — ~10 test users, several weeks of past survey sign-ins, and group +
/// DM chat messages — for local development and UI tests that rely on those
/// fixtures existing. The fixtures themselves only get created once (checked
/// via the group having no members yet).
///
/// Release builds (TestFlight/App Store) skip the demo fixtures entirely —
/// Debug talks to CloudKit's separate Development environment, Release to
/// Production (see CloudKitConfig/README "CloudKit-Setup"), so this can
/// never leak fake colleagues into what real testers see.
@MainActor
enum MockDataSeeder {
    static let testGroupJoinCode = "LABOR2026"
    static let testGroupPharmacyJoinCode = "PROBEN2026"

    static func ensureCloudTestDataIfNeeded() async {
        let userRepository = CloudKitUserRepository()
        guard let group = try? await userRepository.ensureGroupExists(
            name: "Laborteam Nord",
            joinCode: testGroupJoinCode,
            pharmacyJoinCode: testGroupPharmacyJoinCode
        ) else { return }

        #if DEBUG
        guard let existingUsers = try? await userRepository.allUsers(inGroup: group.id), existingUsers.isEmpty else { return }

        var users: [User] = []
        for seed in seedUsers {
            guard let user = try? await userRepository.createSeedUser(
                name: seed.name, abbreviation: seed.abbreviation, role: seed.role, groupID: group.id
            ) else { return }
            users.append(user)
        }

        await seedSurveyDays(groupID: group.id, users: users)
        await seedChatMessages(groupID: group.id, users: users)
        #endif
    }

    #if DEBUG
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

    /// Seeds the past 3 full weeks plus the current week through today, Mon–Thu
    /// only, each with a deterministic 1–3 person rotation so the demo has
    /// realistic-looking variety without relying on true randomness. Reuses
    /// `surveyDays(from:to:groupID:)`'s lazy-create + `signIn` instead of
    /// building CKRecords by hand, so the fixtures go through the exact same
    /// path a real sign-up would.
    private static func seedSurveyDays(groupID: UUID, users: [User]) async {
        let surveyRepository = CloudKitSurveyRepository()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let rangeStart = calendar.date(byAdding: .day, value: -21, to: today) else { return }
        // Returned days are Mon–Thu only, sorted ascending — so their index
        // already lines up with attendeeIndices' dayOffset semantics.
        guard let days = try? await surveyRepository.surveyDays(from: rangeStart, to: today, groupID: groupID) else { return }

        for (dayOffset, day) in days.enumerated() {
            for index in attendeeIndices(for: dayOffset) {
                try? await surveyRepository.signIn(userID: users[index].id, dayID: day.id)
            }
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

    private static func seedChatMessages(groupID: UUID, users: [User]) async {
        let chatRepository = CloudKitChatRepository()
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
            try? await chatRepository.seedMessage(groupID: groupID, senderID: user.id, recipientID: nil, text: text, createdAt: at(hoursAgo: hoursAgo))
        }

        let dmMessages: [(User, User, String, Double)] = [
            (anna, markus, "Hey, kannst du Freitag für mich tauschen?", 30),
            (markus, anna, "Klar, kein Problem. Trag ich mich ein.", 29),
            (anna, markus, "Danke dir, du rettest mich 🙏", 29),
            (markus, anna, "Passt schon, mach ich gern.", 28),
        ]
        for (sender, recipient, text, hoursAgo) in dmMessages {
            try? await chatRepository.seedMessage(groupID: groupID, senderID: sender.id, recipientID: recipient.id, text: text, createdAt: at(hoursAgo: hoursAgo))
        }
    }
    #endif
}
