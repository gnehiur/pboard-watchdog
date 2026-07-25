# pboard-watchdog

Auto-heals the infamous macOS **Universal Clipboard freeze** — the one where a
"Pasting from iPhone…" dialog appears, never finishes, and your entire Mac
becomes unresponsive for up to ~30 minutes.

## The problem

When you paste on your Mac content that was copied on an iPhone/iPad, macOS
fetches the data over a peer-to-peer Wi-Fi link (AWDL). If that link dies
mid-request, the pasteboard server (`pboard`) blocks on the fetch with an
absurdly long (~30 min) timeout. Because the pasteboard is a single global
service that nearly every app queries synchronously (on window focus, menu
updates, …), every app you click piles up behind the stuck request — the
whole machine *appears* frozen, even though only the pasteboard is.

This bug family has been reported since at least iOS 10 (2016) and still
exists in current macOS. The community fix is `killall pboard` — but you have
to know that, and be able to reach a terminal while your GUI is frozen.

## You are not alone: a decade of reports

The same pasteboard code runs on every Apple platform, so the hang bites in
both directions — Macs freeze fetching from iPhones, iPhones freeze fetching
from Macs:

- [Universal Clipboard / UIPasteboard hangs on iOS 10 (2016)](https://developer.apple.com/forums/thread/61818) —
  Apple Developer Forums, the earliest report of this family we could find.
  A [second thread from the same era](https://developer.apple.com/forums/thread/70661).
- [Universal Clipboard broken in macOS 13.4 beta (2023)](https://developer.apple.com/forums/thread/727894) —
  still broken seven macOS versions later.
- Apple Support Community, the iPhone-side mirror image — a "Pasting from
  MacBook…" dialog that never finishes, ignores Cancel, and even blocks the
  power-off screen: [one](https://discussions.apple.com/thread/254874892),
  [two](https://discussions.apple.com/thread/254457898),
  [three](https://discussions.apple.com/thread/254633143),
  [four (2020)](https://discussions.apple.com/thread/250744006),
  [five](https://discussions.apple.com/thread/254811288).
- The `killall pboard` remedy is folk knowledge repeated by a cottage
  industry of troubleshooting guides:
  [OSXDaily](https://osxdaily.com/2018/02/02/fix-copy-paste-not-working-mac/),
  [iDownloadBlog](https://www.idownloadblog.com/2022/06/30/how-to-fix-universal-clipboard-not-working-on-iphone-ipad-mac/),
  [iBoysoft](https://iboysoft.com/tips/universal-clipboard-not-working-on-mac.html),
  [MacPaw](https://macpaw.com/how-to/copypaste-not-working-mac),
  [macReports](https://macreports.com/copy-and-paste-from-iphone-or-ipad-to-mac-not-working-how-to-fix/),
  [WebNots](https://www.webnots.com/how-to-fix-copy-and-paste-not-working-between-iphone-and-mac/),
  [Beebom](https://beebom.com/fix-universal-clipboard-not-working-iphone-mac/).

Ten years, every Apple platform, no official fix, and the accepted answer is
"know a magic terminal command and run it while your machine is frozen".
That is the gap this project fills: it runs the magic command for you,
automatically, within about a minute.

`pboard-watchdog` automates it: a tiny background daemon that notices the
hang within ~1 minute and restarts `pboard` for you. You get a notification;
everything unfreezes; clipboard works again.

## How it works

- Every 30 s it runs `pbprobe`, a ~20-line Swift helper that queries the
  pasteboard server's `changeCount` (a millisecond-level IPC round-trip).
  It never touches clipboard *content*, so it cannot itself trigger a
  Universal Clipboard transfer.
- One timeout is ignored (could be a genuine slow transfer of a large item).
  **Two consecutive 25 s timeouts** ⇒ hang confirmed.
- Recovery escalates gently: `SIGTERM pboard` → re-probe → `SIGKILL pboard`
  if needed. It then always restarts `useractivityd` (the Handoff/Continuity
  broker) as well: field testing showed its advertising state goes stale
  against the new pboard instance, which silently breaks Mac → iPhone
  clipboard sync while inbound sync keeps working. launchd respawns both
  services instantly.
- Idle cost is effectively zero: the daemon sleeps 99.9 % of the time, uses a
  few MB of RAM, writes to disk only when an incident actually happens.

## Install

Requires Xcode Command Line Tools (`xcode-select --install`) for the one-time
compile. No sudo needed — everything is per-user.

```bash
./install.sh
```

This compiles `pbprobe`, installs to `~/Library/Application Support/pboard-watchdog`,
and registers a LaunchAgent (`com.pboard-watchdog`) that starts at login.

## Verify / observe

```bash
tail -f ~/Library/Logs/pboard-watchdog.log
```

A healthy install logs one `watchdog started` line and then stays silent
until an incident. To see it save you for real, freeze the pasteboard server
yourself and watch it get rescued within ~90 s:

```bash
kill -STOP $(pgrep -x pboard)   # simulate the hang (your clipboard freezes!)
```

## Tuning

Environment variables (set them in the LaunchAgent plist if you care):

| Variable | Default | Meaning |
|---|---|---|
| `PBWD_INTERVAL` | 30 | seconds between probes |
| `PBWD_PROBE_TIMEOUT` | 25 | seconds before a probe counts as hung |
| `PBWD_STRIKES` | 2 | consecutive timeouts before intervening |

## Trade-off to know about

Restarting `pboard` clears the current clipboard contents. The watchdog only
does this when the pasteboard has been dead for a full minute — at which
point your clipboard was unusable anyway. The two-strike rule keeps false
positives (e.g. a genuinely slow multi-MB paste) extremely unlikely.

## Uninstall

```bash
./uninstall.sh
```

## License

MIT
