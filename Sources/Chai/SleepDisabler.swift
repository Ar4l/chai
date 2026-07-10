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

// Closing the lid forces sleep regardless of any power assertion; the only
// supported override is `pmset disablesleep`, which requires root. We try a
// passwordless `sudo -n` first (for users with a sudoers rule) and fall back
// to an administrator-privileges prompt.
@MainActor
final class SleepDisabler {
  private(set) var isEngaged = false

  init() {
    // `disablesleep` outlives the process, so restore it on normal termination
    NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification, object: nil, queue: .main
    ) { _ in
      MainActor.assumeIsolated {
        self.disengage()
      }
    }
  }

  func engage() -> Bool {
    guard !isEngaged else { return true }

    isEngaged = setSleepDisabled(true)
    return isEngaged
  }

  func disengage() {
    guard isEngaged else { return }

    if setSleepDisabled(false) {
      isEngaged = false
    }
  }

  private func setSleepDisabled(_ disabled: Bool) -> Bool {
    let value = disabled ? "1" : "0"

    if runNonInteractiveSudo(value) {
      return true
    }

    return runWithAdminPrompt(value)
  }

  private func runNonInteractiveSudo(_ value: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    process.arguments = ["-n", "/usr/bin/pmset", "disablesleep", value]
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

  private func runWithAdminPrompt(_ value: String) -> Bool {
    let source = """
      do shell script "/usr/bin/pmset disablesleep \(value)" \
      with administrator privileges \
      with prompt "Chai wants to keep your Mac awake while the lid is closed."
      """

    var error: NSDictionary?
    NSAppleScript(source: source)?.executeAndReturnError(&error)

    if let error {
      os_log("pmset disablesleep %{public}s failed: %{public}@", value, String(describing: error))
      return false
    }

    return true
  }
}
