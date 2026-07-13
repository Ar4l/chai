// SPDX-License-Identifier: GPL-3.0-only
//
// Chai - Don't let your Mac fall asleep, like a sir
// Copyright (C) 2026 Chai authors
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 of the License.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import AppKit
import Foundation
import os

// Installs (and removes) /etc/sudoers.d/chai, the passwordless rule that lets
// SleepDisabler run `pmset disablesleep` non-interactively. Without it, a timed
// session expiring with the lid closed pops a password dialog nobody can see,
// and the Mac stays awake until the lid opens.
@MainActor
final class SudoersInstaller {
  enum InstallResult {
    case success
    case cancelled
    case failed(String)
  }

  private static let sudoersPath = "/etc/sudoers.d/chai"
  private static let userCanceledErr = -128

  // Runs the exact command disengage() needs at timer expiry. `-k` combined
  // with a command makes sudo ignore (not invalidate) cached credentials, and
  // `-n` makes it fail instead of prompting — so this succeeds only via a
  // NOPASSWD rule for the current user. On success it sets disablesleep to 0,
  // so only call while sleep is expected to be enabled (i.e. disengaged).
  func hasRule() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    process.arguments = ["-k", "-n", "/usr/bin/pmset", "disablesleep", "0"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      process.waitUntilExit()
      return process.terminationStatus == 0
    } catch {
      return false
    }
  }

  // The user name is interpolated into a shell command and the sudoers file,
  // so anything outside this conservative charset aborts the offer entirely.
  static func validatedUserName() -> String? {
    let user = NSUserName()
    let allowed = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")

    guard !user.isEmpty,
      !user.hasPrefix("-"),
      user.unicodeScalars.allSatisfy(allowed.contains)
    else { return nil }

    return user
  }

  func install() -> InstallResult {
    guard let user = Self.validatedUserName() else {
      return .failed("unsupported user name")
    }

    let rule =
      "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1"

    // visudo validates before anything touches /etc/sudoers.d; install(1)
    // places the file atomically with the right owner and mode; any failing
    // step aborts the chain and surfaces stderr through the AppleScript error.
    let command =
      "umask 077 && t=$(/usr/bin/mktemp /private/tmp/chai-sudoers.XXXXXX)"
      + " && /usr/bin/printf '%s\\n' '\(rule)' > \"$t\""
      + " && /usr/sbin/visudo -cf \"$t\""
      + " && /bin/mkdir -p /etc/sudoers.d"
      + " && /usr/bin/install -m 0440 -o root -g wheel \"$t\" \(Self.sudoersPath)"
      + " && /bin/rm -f \"$t\""

    let source =
      "do shell script \(Self.appleScriptLiteral(command))"
      + " with administrator privileges"
      + " with prompt \"Chai wants to allow re-enabling sleep without a password.\""

    var error: NSDictionary?
    NSAppleScript(source: source)?.executeAndReturnError(&error)

    if let error {
      if (error[NSAppleScript.errorNumber] as? Int) == Self.userCanceledErr {
        return .cancelled
      }

      os_log("sudoers install failed: %{public}@", String(describing: error))
      return .failed((error[NSAppleScript.errorMessage] as? String) ?? "unknown error")
    }

    return .success
  }

  func remove() -> Bool {
    let source = """
      do shell script "/bin/rm -f \(Self.sudoersPath)" \
      with administrator privileges \
      with prompt "Chai wants to remove its passwordless sudo rule."
      """

    var error: NSDictionary?
    NSAppleScript(source: source)?.executeAndReturnError(&error)

    if let error {
      if (error[NSAppleScript.errorNumber] as? Int) != Self.userCanceledErr {
        os_log("sudoers removal failed: %{public}@", String(describing: error))
      }
      return false
    }

    return true
  }

  private static func appleScriptLiteral(_ string: String) -> String {
    let escaped =
      string
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }
}
