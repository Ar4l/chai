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
import IOKit.ps

extension Notification.Name {
  static let powerSourceChanged = Notification.Name("ChaiPowerSourceChanged")
}

enum PowerSource {
  static var isOnAC: Bool {
    guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue()
    else {
      return true
    }

    return (type as String) == kIOPMACPowerKey
  }

  static func startMonitoring() {
    let callback: IOPowerSourceCallbackType = { _ in
      NotificationCenter.default.post(name: .powerSourceChanged, object: nil)
    }

    guard let source = IOPSNotificationCreateRunLoopSource(callback, nil)?.takeRetainedValue()
    else {
      return
    }

    CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
  }
}
