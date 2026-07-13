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

import ServiceManagement
import SwiftUI
import os

@main
struct ChaiApp: App {
  @State private var appState = AppState()

  private let didWakePublisher = NSWorkspace.shared.notificationCenter
    .publisher(for: NSWorkspace.didWakeNotification)

  private let powerSourcePublisher = NotificationCenter.default
    .publisher(for: .powerSourceChanged)

  init() {
    PowerSource.startMonitoring()
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarMenu(
        appState: appState,
        activate: activate,
        deactivate: deactivate,
        toggleDisableAfterSuspend: toggleDisableAfterSuspend,
        toggleLidClosedMode: toggleLidClosedMode,
        toggleKeepAwakeOnBattery: toggleKeepAwakeOnBattery,
        toggleLaunchAtLogin: toggleLaunchAtLogin
      )
      .onReceive(didWakePublisher) { _ in
        guard appState.isDisableAfterSuspendEnabled else { return }
        os_log("System wakeup detected, disabling according to config")
        deactivate()
      }
      .onReceive(powerSourcePublisher) { _ in
        os_log("Power source changed, re-applying policy")
        applyPowerPolicy()
      }
    } label: {
      Image(appState.isActive && !appState.isSuspendedForBattery ? "Mug" : "Mug-Empty")
        .renderingMode(.template)
    }
  }

  // MARK: - Actions

  private func activate(spec: ActivationSpec) {
    // If already active with the same spec, toggle off
    if appState.isActive && appState.activeSpec == spec {
      deactivate()
      return
    }

    // Deactivate any existing assertion first
    deactivate()

    if spec.timeInterval > 0 {
      os_log("Scheduling deactivation in %f seconds", spec.timeInterval)
      appState.deactivationTask = Task { @MainActor in
        try? await Task.sleep(for: .seconds(spec.timeInterval))
        guard !Task.isCancelled else { return }
        os_log("Timer fired, deactivating")
        deactivate()
      }

      offerSudoersInstallIfNeeded()
    }

    appState.activate(spec: spec)
    applyPowerPolicy()
    os_log("Activated")
  }

  private func deactivate() {
    appState.deactivationTask?.cancel()
    appState.deactivationTask = nil
    appState.deactivate()
    applyPowerPolicy()
    os_log("Deactivated")
  }

  // Reconciles the power assertion and the lid-closed sleep override with the
  // activation state, preferences, and current power source.
  private func applyPowerPolicy() {
    let shouldHold =
      appState.isActive && (appState.isKeepAwakeOnBatteryEnabled || PowerSource.isOnAC)
    appState.isSuspendedForBattery = appState.isActive && !shouldHold

    guard shouldHold else {
      appState.powerAssertion = nil
      appState.sleepDisabler.disengage()
      return
    }

    if appState.powerAssertion == nil {
      appState.powerAssertion = PowerAssertion(named: "Brewing Tea")
    }

    if appState.isLidClosedModeEnabled {
      if !appState.sleepDisabler.engage() {
        os_log("Could not override lid-closed sleep, disabling the preference")
        appState.setLidClosedMode(false)
      }
    } else {
      appState.sleepDisabler.disengage()
    }
  }

  private func toggleDisableAfterSuspend() {
    appState.setDisableAfterSuspend(!appState.isDisableAfterSuspendEnabled)
  }

  private func toggleLidClosedMode() {
    let turningOff = appState.isLidClosedModeEnabled

    appState.setLidClosedMode(!appState.isLidClosedModeEnabled)
    applyPowerPolicy()

    if turningOff {
      offerSudoersRemovalIfNeeded()
    }
  }

  // A timed session expiring with the lid closed needs a passwordless
  // `pmset disablesleep 0`: the admin-prompt fallback would appear on a screen
  // nobody can see, keeping the Mac awake until the lid opens. Offer to
  // install the sudoers rule once, before the session engages.
  private func offerSudoersInstallIfNeeded() {
    guard appState.isLidClosedModeEnabled,
      !appState.isSudoersPromptSuppressed,
      !appState.didOfferSudoersInstall
    else { return }

    guard SudoersInstaller.validatedUserName() != nil else {
      os_log("User name unsuitable for a sudoers rule, skipping setup offer")
      return
    }

    guard !appState.sudoersInstaller.hasRule() else { return }

    appState.didOfferSudoersInstall = true

    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.messageText = "Allow Chai to Re-Enable Sleep Without a Password?"
    alert.informativeText = """
      When this timer ends with the lid closed, Chai must run \
      "pmset disablesleep 0" as an administrator. Without a passwordless rule, \
      macOS shows a password dialog on a screen nobody can see, and the Mac \
      stays awake until the lid is opened. Installing adds /etc/sudoers.d/chai, \
      scoped to exactly this command, after one administrator prompt.
      """
    alert.addButton(withTitle: "Install")
    alert.addButton(withTitle: "Not Now")
    alert.addButton(withTitle: "Don't Ask Again")

    switch alert.runModal() {
    case .alertFirstButtonReturn:
      switch appState.sudoersInstaller.install() {
      case .success:
        if !appState.sudoersInstaller.hasRule() {
          // e.g. /etc/sudoers is missing "#includedir /etc/sudoers.d"
          showSudoersFailureAlert("The rule was installed but has no effect.")
        }
      case .cancelled:
        break
      case .failed(let message):
        showSudoersFailureAlert(message)
      }
    case .alertThirdButtonReturn:
      appState.setSuppressSudoersPrompt(true)
    default:
      break
    }
  }

  private func offerSudoersRemovalIfNeeded() {
    guard appState.sudoersInstaller.hasRule() else { return }

    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.messageText = "Remove Chai's Passwordless Sudo Rule?"
    alert.informativeText =
      "Lid-closed mode is off, so /etc/sudoers.d/chai is no longer needed."
    alert.addButton(withTitle: "Keep")
    alert.addButton(withTitle: "Remove")

    if alert.runModal() == .alertSecondButtonReturn {
      _ = appState.sudoersInstaller.remove()
    }
  }

  private func showSudoersFailureAlert(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "Could Not Install the Sudoers Rule"
    alert.informativeText =
      "\(message)\n\nYou can set it up manually with the command in Chai's README."
    alert.runModal()
  }

  private func toggleKeepAwakeOnBattery() {
    appState.setKeepAwakeOnBattery(!appState.isKeepAwakeOnBatteryEnabled)
    applyPowerPolicy()
  }

  private func toggleLaunchAtLogin() {
    let newState = !appState.isLoginItemEnabled

    do {
      if newState {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      os_log("Failed to update login item: %{public}@", error.localizedDescription)
      return
    }

    appState.setLoginItemEnabled(newState)
    os_log("Launch at login: %{public}s", newState ? "enabled" : "disabled")
  }
}

// MARK: - Menu View

struct MenuBarMenu: View {
  let appState: AppState
  let activate: (ActivationSpec) -> Void
  let deactivate: () -> Void
  let toggleDisableAfterSuspend: () -> Void
  let toggleLidClosedMode: () -> Void
  let toggleKeepAwakeOnBattery: () -> Void
  let toggleLaunchAtLogin: () -> Void

  var body: some View {
    Text("Keep This Mac Awake")
      .font(.headline)

    if appState.isSuspendedForBattery {
      Text("Paused While on Battery")
    }

    Divider()

    ForEach(ActivationSpecs.allCases, id: \.self) { specCase in
      let spec = specCase.spec
      Button {
        activate(spec)
      } label: {
        HStack {
          Text(spec.title)
          if appState.activeSpec == spec {
            Spacer()
            Image(systemName: "checkmark")
          }
        }
      }
      .if(!spec.label.isEmpty) { view in
        view.keyboardShortcut(KeyEquivalent(Character(spec.label)), modifiers: [])
      }
    }

    Divider()

    Menu("Preferences") {
      Toggle(
        "Disable After Suspend",
        isOn: Binding(
          get: { appState.isDisableAfterSuspendEnabled },
          set: { _ in toggleDisableAfterSuspend() }
        ))

      Toggle(
        "Keep Awake When Lid Is Closed",
        isOn: Binding(
          get: { appState.isLidClosedModeEnabled },
          set: { _ in toggleLidClosedMode() }
        ))

      Toggle(
        "Keep Awake on Battery",
        isOn: Binding(
          get: { appState.isKeepAwakeOnBatteryEnabled },
          set: { _ in toggleKeepAwakeOnBattery() }
        ))
    }

    Divider()

    Toggle(
      "Launch at Login",
      isOn: Binding(
        get: { appState.isLoginItemEnabled },
        set: { _ in toggleLaunchAtLogin() }
      ))

    Button("Quit Chai") {
      appState.sleepDisabler.disengage()
      NSApplication.shared.terminate(nil)
    }
    .keyboardShortcut("q")
  }
}

// MARK: - Conditional View Modifier

extension View {
  @ViewBuilder
  func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
    if condition {
      transform(self)
    } else {
      self
    }
  }
}
