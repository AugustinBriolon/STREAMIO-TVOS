import Testing
@testable import Loge

struct PlanLimitsTests {
    @Test func freeMatrix() {
        let limits = PlanLimits.forPlan(.free)
        #expect(limits.maxProfiles == 1)
        #expect(limits.maxAddons == 1)
        #expect(limits.maxTVSessions == 1)
        #expect(limits.maxBrowserSessions == 1)
        #expect(limits.cloudSync == false)
        #expect(limits.canRenameDevices == false)
        #expect(limits.canAddProfile(currentCount: 0))
        #expect(!limits.canAddProfile(currentCount: 1))
        #expect(limits.canAddAddon(currentCount: 0))
        #expect(!limits.canAddAddon(currentCount: 1))
    }

    @Test func proMatrix() {
        let limits = PlanLimits.forPlan(.pro)
        #expect(limits.maxProfiles == 3)
        #expect(limits.maxAddons == 5)
        #expect(limits.maxTVSessions == 2)
        #expect(limits.maxBrowserSessions == 1)
        #expect(limits.cloudSync)
        #expect(limits.canRenameDevices)
        #expect(limits.canAddProfile(currentCount: 2))
        #expect(!limits.canAddProfile(currentCount: 3))
        #expect(limits.canAddAddon(currentCount: 4))
        #expect(!limits.canAddAddon(currentCount: 5))
    }

    @Test func ultraMatrix() {
        let limits = PlanLimits.forPlan(.ultra)
        #expect(limits.maxProfiles == 6)
        #expect(limits.maxAddons == 20)
        #expect(limits.maxTVSessions == 4)
        #expect(limits.maxBrowserSessions == 2)
        #expect(limits.cloudSync)
        #expect(limits.canRenameDevices)
    }

    @Test func sessionKickCountsIndependentPools() {
        let free = PlanLimits.forPlan(.free)
        #expect(free.sessionsToRevokeBeforeOpen(activeCount: 0, kind: .tv) == 0)
        #expect(free.sessionsToRevokeBeforeOpen(activeCount: 1, kind: .tv) == 1)
        #expect(free.sessionsToRevokeBeforeOpen(activeCount: 1, kind: .browser) == 1)

        let pro = PlanLimits.forPlan(.pro)
        #expect(pro.sessionsToRevokeBeforeOpen(activeCount: 1, kind: .tv) == 0)
        #expect(pro.sessionsToRevokeBeforeOpen(activeCount: 2, kind: .tv) == 1)
        #expect(pro.sessionsToRevokeBeforeOpen(activeCount: 1, kind: .browser) == 1)

        let ultra = PlanLimits.forPlan(.ultra)
        #expect(ultra.sessionsToRevokeBeforeOpen(activeCount: 3, kind: .tv) == 0)
        #expect(ultra.sessionsToRevokeBeforeOpen(activeCount: 4, kind: .tv) == 1)
        #expect(ultra.sessionsToRevokeBeforeOpen(activeCount: 2, kind: .browser) == 1)
    }
}
