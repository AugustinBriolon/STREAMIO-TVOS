import Foundation
import Testing
@testable import Loge

struct DeviceIdentityTests {
    @Test func namesKnownAppleTVModels() {
        #expect(DeviceIdentity.modelName(forIdentifier: "AppleTV5,3") == "Apple TV HD")
        #expect(DeviceIdentity.modelName(forIdentifier: "AppleTV14,1") == "Apple TV 4K (3e génération)")
        #expect(DeviceIdentity.modelName(forIdentifier: "AppleTV99,9") == "Apple TV")
    }

    @Test func decodesTheAccountDeviceList() throws {
        let json = Data(#"{"devices":[{"id":"s1","name":"Séjour","model":"Apple TV 4K (3e génération)","createdAtMs":1,"lastSeenAtMs":1700000000000,"isCurrent":true},{"id":"s2","name":"Navigateur web","model":null,"createdAtMs":1,"lastSeenAtMs":null,"isCurrent":false}]}"#.utf8)
        struct Payload: Decodable { let devices: [DeviceSession] }
        let devices = try JSONDecoder().decode(Payload.self, from: json).devices
        #expect(devices.map(\.name) == ["Séjour", "Navigateur web"])
        #expect(devices[0].isCurrent && devices[0].lastSeen == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(devices[1].model == nil && devices[1].lastSeen == nil)
    }
}
