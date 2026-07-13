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

import Foundation
import Observation

@Observable
@MainActor
final class AppState {
  private enum DefaultsKey {
    static let disableAfterSuspend = "DisableAfterSuspend"
    static let loginItemEnabled = "LoginItemEnabled"
    static let lidClosedMode = "LidClosedMode"
    static let keepAwakeOnBattery = "KeepAwakeOnBattery"
    static let suppressSudoersPrompt = "SuppressSudoersPrompt"
  }

  var isActive: Bool = false
  var activeSpec: ActivationSpec? = nil
  var isDisableAfterSuspendEnabled: Bool = false
  var isLoginItemEnabled: Bool = false
  var isLidClosedModeEnabled: Bool = false
  var isKeepAwakeOnBatteryEnabled: Bool = true
  var isSuspendedForBattery: Bool = false
  var isSudoersPromptSuppressed: Bool = false
  // In-memory latch: a declined sudoers offer only re-asks on the next launch.
  var didOfferSudoersInstall: Bool = false
  var powerAssertion: PowerAssertion? = nil
  var deactivationTask: Task<Void, Never>? = nil
  let sleepDisabler = SleepDisabler()
  let sudoersInstaller = SudoersInstaller()

  init() {
    isDisableAfterSuspendEnabled = UserDefaults.standard.bool(
      forKey: DefaultsKey.disableAfterSuspend)
    isLoginItemEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.loginItemEnabled)
    isLidClosedModeEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.lidClosedMode)
    isKeepAwakeOnBatteryEnabled =
      UserDefaults.standard.object(forKey: DefaultsKey.keepAwakeOnBattery) as? Bool ?? true
    isSudoersPromptSuppressed = UserDefaults.standard.bool(
      forKey: DefaultsKey.suppressSudoersPrompt)
  }

  func activate(spec: ActivationSpec?) {
    isActive = true
    activeSpec = spec
  }

  func deactivate() {
    isActive = false
    activeSpec = nil
    isSuspendedForBattery = false
  }

  func setDisableAfterSuspend(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: DefaultsKey.disableAfterSuspend)
    isDisableAfterSuspendEnabled = enabled
  }

  func setLoginItemEnabled(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: DefaultsKey.loginItemEnabled)
    isLoginItemEnabled = enabled
  }

  func setLidClosedMode(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: DefaultsKey.lidClosedMode)
    isLidClosedModeEnabled = enabled
  }

  func setKeepAwakeOnBattery(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: DefaultsKey.keepAwakeOnBattery)
    isKeepAwakeOnBatteryEnabled = enabled
  }

  func setSuppressSudoersPrompt(_ suppressed: Bool) {
    UserDefaults.standard.set(suppressed, forKey: DefaultsKey.suppressSudoersPrompt)
    isSudoersPromptSuppressed = suppressed
  }
}
