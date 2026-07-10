# Chai

<img align="right" alt="logo" src="Sources/Chai/Assets.xcassets/AppIcon.appiconset/128x128@2x.png" width="128" height="128">

_Don't let your Mac fall asleep, like a sir_

[![License](https://img.shields.io/badge/license-GPLv3-blue.svg?style=flat)](https://choosealicense.com/licenses/gpl-3.0/)

--------------------------------------------------------------------------------

This is a fork of [lvillani/chai](https://github.com/lvillani/chai) that adds two preferences:
keeping the Mac awake with the lid closed, and pausing on battery power.

## Install

```bash
brew install ar4l/tap/chai
```

The cask removes the quarantine attribute on install, so Gatekeeper won't complain about the
app not being notarized. To build from source instead, see [Installation](#installation) below.

## What's Different in This Fork

### Keep Awake When Lid Is Closed

Closing the lid normally forces sleep no matter what power assertions are held. The only
supported override is `pmset disablesleep`, which requires administrator privileges. With this
preference enabled, Chai runs `pmset disablesleep 1` whenever a keep-awake session is active and
`pmset disablesleep 0` when the session ends (deactivation, timer expiry, or quitting Chai).

Timed sessions work as usual: if you pick "1 Hour" and close the lid, sleep is re-enabled when
the hour is up and the Mac suspends immediately.

To gain privileges, Chai first tries a passwordless `sudo -n` and falls back to a macOS
administrator password prompt.

> [!IMPORTANT]
> If you use timed sessions with the lid closed, set up the passwordless sudoers rule below.
> Without it, re-enabling sleep when the timer fires pops a password dialog — which nobody can
> answer while the lid is shut, so the Mac stays awake until you open it and dismiss the prompt.

```bash
echo "$USER ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1" \
  | sudo tee /etc/sudoers.d/chai
```

> [!WARNING]
> A closed laptop has reduced airflow — do not put it in a bag or on soft surfaces while this
> mode is engaged. If Chai crashes (rather than quitting normally), the override stays on until
> you reboot or run `sudo pmset disablesleep 0` yourself. Check the current state at any time
> with `pmset -g | grep SleepDisabled`.

### Keep Awake on Battery

Enabled by default, matching upstream behavior. When you turn it **off**, Chai automatically
pauses its keep-awake session while the Mac runs on battery power and resumes it when AC power
is reconnected — so a "Forever" session can't silently drain the battery. While paused, the menu
bar icon shows the empty mug and the menu reads "Paused While on Battery".

### Preferences at a Glance

| Preference | Effect |
| --- | --- |
| Disable After Suspend | (Upstream) If the Mac does sleep and wakes back up, Chai deactivates itself instead of resuming the session. |
| Keep Awake When Lid Is Closed | Keeps the Mac running in clamshell mode via `pmset disablesleep` while a session is active. |
| Keep Awake on Battery | On by default. Turn off to pause sessions on battery power and resume on AC. |

> [!NOTE]
> Upstream Chai runs in the App Sandbox. This fork does not — sandboxed processes cannot run
> `pmset` with administrator privileges, which lid-closed mode requires.

## Installation

The easiest way is Homebrew (see [Install](#install) above):

```bash
brew install ar4l/tap/chai
```

Or build from source (requires the Xcode command line tools):

```bash
./script/build
cp -r .build/release/Chai.app /Applications/
```

The app is ad-hoc signed; since you build it yourself there is no Gatekeeper quarantine to deal
with.

## How Does It Look?

<img src="screenshot.png" width="640" height="400">

## Don't We Have Caffeine Already?

Chai is better than [Caffeine](http://lightheadsw.com/caffeine/) in a number of ways:

* It is open source, so we have nothing to hide.
* It uses [power assertions][IOPMLib] to keep your Mac awake.
* Upstream Chai runs in the [sandbox][sandbox] to keep your Mac secure (this fork trades that
  for lid-closed support — see above).

## Icons

Icons are licensed from [Glyphish](http://glyphish.com) and cannot be used outside this project.

[IOPMLib]:
https://developer.apple.com/library/mac/documentation/IOKit/Reference/IOPMLib_header_reference/

[sandbox]:
https://developer.apple.com/library/mac/documentation/Security/Conceptual/AppSandboxDesignGuide/AboutAppSandbox/AboutAppSandbox.html
