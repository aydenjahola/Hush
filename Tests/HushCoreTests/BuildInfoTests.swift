import HushCore
import Testing

struct BuildInfoTests {
    @Test func releaseChannelIsNotLocal() {
        let info = BuildInfo(infoDictionary: [
            "CFBundleShortVersionString": "0.2.0", "HushBuildChannel": "release", "HushBuildCommit": "abc1234",
        ])
        #expect(info == BuildInfo(version: "0.2.0", channel: .release, commit: "abc1234"))
        #expect(!info.isLocal)
    }

    @Test func devChannelIsLocal() {
        let info = BuildInfo(infoDictionary: [
            "CFBundleShortVersionString": "0.2.0", "HushBuildChannel": "dev", "HushBuildCommit": "abc1234-dirty",
        ])
        #expect(info.isLocal)
        #expect(info.commit == "abc1234-dirty")
    }

    @Test func missingKeysMeanALocalBuild() {
        let bare = BuildInfo(infoDictionary: nil)
        #expect(bare == BuildInfo(version: nil, channel: .local, commit: nil))
        let noChannel = BuildInfo(infoDictionary: ["CFBundleShortVersionString": "0.1.0", "HushBuildCommit": ""])
        #expect(noChannel.isLocal)
        #expect(noChannel.commit == nil)
    }
}
