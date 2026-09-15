import Testing
@testable import Probenfahrt

struct WebPasswordEncryptionTests {
    @Test func roundTripsThroughEncryptAndDecrypt() {
        let encrypted = WebPasswordEncryption.encrypt("TestPasswort123")
        #expect(WebPasswordEncryption.decrypt(encrypted) == "TestPasswort123")
    }

    @Test func isDeterministic() {
        #expect(WebPasswordEncryption.encrypt("TestPasswort123") == WebPasswordEncryption.encrypt("TestPasswort123"))
    }

    @Test func differentPasswordsProduceDifferentCiphertext() {
        #expect(WebPasswordEncryption.encrypt("TestPasswort123") != WebPasswordEncryption.encrypt("AnderesPasswort"))
    }

    /// Cross-compatibility check with the Worker's JS implementation
    /// (encryptWebPassword/decryptWebPassword in web/worker-app/src/index.js):
    /// this exact ciphertext was independently produced by a Node script
    /// running the JS side against the same key+password, *not* generated
    /// from this Swift code - if Swift decrypts it correctly, the two
    /// implementations are proven byte-compatible, not just each internally
    /// consistent.
    @Test func decryptsCiphertextProducedByTheJavaScriptImplementation() {
        let jsGeneratedCiphertext = "MTfbIjGS5vyJBPuOWuqpW8acAckZxDjCkw9HGOpT7ijhNBBG2H5CTe29zA=="
        #expect(WebPasswordEncryption.decrypt(jsGeneratedCiphertext) == "TestPasswort123")
    }

    @Test func swiftEncryptedValueMatchesTheJavaScriptTestVector() {
        // Same password+key as the Node test vector above - if this
        // matches, JS would decrypt what Swift produces too.
        #expect(WebPasswordEncryption.encrypt("TestPasswort123") == "MTfbIjGS5vyJBPuOWuqpW8acAckZxDjCkw9HGOpT7ijhNBBG2H5CTe29zA==")
    }
}
