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

    /// Dedicated join code for the onboarding "Demo-Modus" button — never
    /// shown to users, only used internally by `ensureDemoGroupExists()`.
    static let demoGroupJoinCode = "apple-review-demo"

    /// Caches the demo group's CloudKit-assigned id locally so RootTabView
    /// can self-heal `SessionStore.isDemoSession` for sessions created by an
    /// older build (before that flag existed) without an extra CloudKit
    /// round-trip on every launch.
    static let demoGroupIDKey = "com.johannesemmrich.probenfahrt.demoGroupID"

    static func ensureCloudTestDataIfNeeded() async {
        let userRepository = CloudKitUserRepository()
        guard let group = try? await userRepository.ensureGroupExists(
            name: "Laborteam Nord",
            joinCode: testGroupJoinCode,
            pharmacyJoinCode: testGroupPharmacyJoinCode
        ) else {
            print("⚠️ MockDataSeeder: TeamGroup konnte nicht angelegt/gefunden werden (CloudKit nicht erreichbar?).")
            return
        }

        #if DEBUG
        guard let existingUsers = try? await userRepository.allUsers(inGroup: group.id), existingUsers.isEmpty else {
            print("MockDataSeeder: Gruppe hat schon Mitglieder (oder Abfrage fehlgeschlagen) — überspringe Demo-Seeding.")
            return
        }

        print("MockDataSeeder: Seede \(seedUsers.count) Test-Nutzer …")
        var users: [User] = []
        for seed in seedUsers {
            guard let user = try? await userRepository.createSeedUser(
                name: seed.name, abbreviation: seed.abbreviation, role: seed.role, groupID: group.id
            ) else {
                print("⚠️ MockDataSeeder: Anlegen von \(seed.name) fehlgeschlagen, breche Seeding ab.")
                return
            }
            users.append(user)
        }

        print("MockDataSeeder: Nutzer fertig, seede Umfrage-Historie …")
        await seedSurveyDays(groupID: group.id, users: users)
        print("MockDataSeeder: Umfrage-Historie fertig, seede Chat-Nachrichten …")
        await seedChatMessages(groupID: group.id, users: users)
        print("✅ MockDataSeeder: Fertig — Testdaten vollständig angelegt.")
        #endif
    }

    /// Dedicated TeamGroup for the Demo-Modus onboarding path (App Review /
    /// first look) — idempotent find-or-create like the real test group
    /// above, but never `#if DEBUG`-gated: it has to exist in Release/
    /// TestFlight builds too, since that's exactly when a reviewer would use
    /// it. Seeded once with a few colleagues, survey sign-ups (incl. a locked
    /// day), chat messages, and a sample location — Apple App Review
    /// (Guideline 2.1(a), 2026-09-22) rejected the first submission because
    /// an empty demo account didn't let them verify the app's features.
    static func ensureDemoGroupExists() async -> TeamGroup? {
        let userRepository = CloudKitUserRepository()
        guard let group = try? await userRepository.ensureGroupExists(
            name: "Demo-Team",
            joinCode: demoGroupJoinCode,
            pharmacyJoinCode: "\(demoGroupJoinCode)-pharmacy"
        ) else {
            print("⚠️ MockDataSeeder: Demo-Gruppe konnte nicht angelegt/gefunden werden (CloudKit nicht erreichbar?).")
            return nil
        }

        UserDefaults.standard.set(group.id.uuidString, forKey: demoGroupIDKey)

        guard let existingUsers = try? await userRepository.allUsers(inGroup: group.id), existingUsers.isEmpty else {
            return group
        }

        var users: [User] = []
        for seed in demoSeedUsers {
            guard let user = try? await userRepository.createSeedUser(
                name: seed.name, abbreviation: seed.abbreviation, role: .member, groupID: group.id
            ) else { continue }
            users.append(user)
        }
        guard users.count == demoSeedUsers.count else { return group }

        await seedDemoSurveyDays(groupID: group.id, users: users)
        await seedDemoChatMessages(groupID: group.id, users: users)
        await seedDemoSampleLocation(groupID: group.id)

        return group
    }

    private struct SeedUser {
        let name: String
        let abbreviation: String
        let role: UserRole
    }

    private static let demoSeedUsers: [SeedUser] = [
        SeedUser(name: "Anna Weber", abbreviation: "AW", role: .member),
        SeedUser(name: "Markus Schulz", abbreviation: "MS", role: .member),
        SeedUser(name: "Laura Fischer", abbreviation: "LF", role: .member),
    ]

    /// Populates upcoming survey days so a reviewer sees every visual state
    /// without creating data themselves — deliberately leaves the very first
    /// day untouched (plain/unlocked-empty) before the colored ones, so a
    /// first glance at the list doesn't look like "everything is colored":
    /// day 0 empty, day 1 one signup (green), day 2 two signups (red "!" +
    /// green row), day 3 one signup then locked (orange row + caption).
    private static func seedDemoSurveyDays(groupID: UUID, users: [User]) async {
        guard users.count >= 3 else { return }
        let surveyRepository = CloudKitSurveyRepository()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let rangeEnd = calendar.date(byAdding: .day, value: 14, to: today) else { return }
        guard let days = try? await surveyRepository.surveyDays(from: today, to: rangeEnd, groupID: groupID), days.count >= 4 else { return }

        try? await surveyRepository.signIn(userID: users[0].id, dayID: days[1].id, bypassLock: false)

        try? await surveyRepository.signIn(userID: users[0].id, dayID: days[2].id, bypassLock: false)
        try? await surveyRepository.signIn(userID: users[1].id, dayID: days[2].id, bypassLock: false)

        try? await surveyRepository.signIn(userID: users[2].id, dayID: days[3].id, bypassLock: false)
        try? await surveyRepository.setLocked(true, reason: "Wird an diesem Tag nicht gefahren", dayID: days[3].id)
    }

    private static func seedDemoChatMessages(groupID: UUID, users: [User]) async {
        guard users.count >= 2 else { return }
        let chatRepository = CloudKitChatRepository()
        let now = Date.now
        func at(hoursAgo: Double) -> Date { now.addingTimeInterval(-hoursAgo * 3600) }

        let groupMessages: [(User, String, Double)] = [
            (users[0], "Willkommen im Demo-Team! Hier tragt ihr euch für Fahrten ein.", 5),
            (users[1], "Danke, sieht gut aus 🙂", 4.5),
            (users[0], "Ich trag mich für morgen ein.", 2),
        ]
        for (user, text, hoursAgo) in groupMessages {
            try? await chatRepository.seedMessage(groupID: groupID, senderID: user.id, recipientID: nil, text: text, createdAt: at(hoursAgo: hoursAgo))
        }

        try? await chatRepository.seedMessage(groupID: groupID, senderID: users[1].id, recipientID: users[0].id, text: "Kannst du morgen für mich übernehmen?", createdAt: at(hoursAgo: 1.5))
        try? await chatRepository.seedMessage(groupID: groupID, senderID: users[0].id, recipientID: users[1].id, text: "Klar, kein Problem!", createdAt: at(hoursAgo: 1))
    }

    private static func seedDemoSampleLocation(groupID: UUID) async {
        let samplesRepository = CloudKitSamplesRepository()
        guard let location = try? await samplesRepository.createLocation(
            groupID: groupID, name: "Muster-Apotheke", address: "Musterstraße 1, 12345 Musterstadt", usesQRCheckIn: false
        ) else { return }
        try? await samplesRepository.setHasSamples(true, locationID: location.id, day: .now)
    }

    #if DEBUG
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
                try? await surveyRepository.signIn(userID: users[index].id, dayID: day.id, bypassLock: false)
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
