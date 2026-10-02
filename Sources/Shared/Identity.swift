import Foundation

/// Names and code signing identities shared by Sirocco.app and its helper.
///
/// The helper runs as root, so it only talks to a client whose signature matches
/// `appRequirement`, and the app only trusts a helper matching `helperRequirement`. A fork
/// signed by a different team changes `teamID` here and the bundle identifiers in project.yml.
enum Identity {
    static let teamID = "CJZMYQN8V6"
    static let appBundleID = "com.joymadhu.Sirocco"

    /// launchd label, Mach service name and the helper's code signing identifier, all one string.
    static let helperLabel = "com.joymadhu.sirocco.helper"
    /// File name inside Sirocco.app/Contents/Library/LaunchDaemons, as SMAppService expects.
    static let helperPlistName = "\(helperLabel).plist"

    static var appRequirement: String { requirement(for: appBundleID) }
    static var helperRequirement: String { requirement(for: helperLabel) }

    private static func requirement(for identifier: String) -> String {
        "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(teamID)\""
    }
}

/// The helper's XPC interface. Payloads are JSON so the app and helper share one Codable model
/// instead of a parallel set of @objc classes.
@objc(SiroccoHelperProtocol)
protocol SiroccoHelperProtocol {
    /// JSON encoded `FanStatus`.
    func fetchStatus(withReply reply: @escaping (Data?) -> Void)
    /// JSON encoded `FanConfig`. Replies false if it could not be decoded.
    func applyConfig(_ config: Data, withReply reply: @escaping (Bool) -> Void)
}
