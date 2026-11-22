//
//  CodeSigningInfo.swift
//  Shared
//

import Foundation
import Security

enum CodeSigningInfo {
    /// A Boolean value that indicates whether the current process is signed
    /// with a non-empty Team Identifier.
    static let hasTeamIdentifier: Bool = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return false
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return false
        }
        var information: CFDictionary?
        guard
            SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
            let info = information as? [String: Any],
            let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String
        else {
            return false
        }
        return !teamID.isEmpty
    }()
}
