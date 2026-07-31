# Safety and responsible use

Startle intentionally causes a sudden audiovisual interruption. Use it only on your own Mac or with the clear, informed consent of every person who may be affected.

Do not use Startle around anyone with a heart condition, epilepsy, severe anxiety, PTSD, sound sensitivity, or another condition that may be aggravated by a sudden stimulus. Do not use it while driving, operating equipment, carrying hot or sharp objects, presenting, recording, providing care, or in any setting where a startled reaction could cause harm.

## Emergency controls

- Press Escape to close an active scare.
- Press Command–Option–Shift–Escape to close an active scare and disable future scares.
- If the global shortcut cannot be registered, Startle reports the failure and refuses to enable scheduled scares. Resolve the shortcut conflict, then retry registration from Safety.

## Limits of automatic detection

Add presentation, recording, game, and editing apps to the exclusion list in Safety. Startle checks the frontmost app through the public `NSWorkspace` API immediately before presentation and does not require Accessibility permission for this check.

Camera, microphone, full-screen window, Apple screen-capture, display, battery, volume, idle, sleep, and session checks rely on public macOS signals. Those signals can be unavailable or incomplete. Third-party screen sharing may not be detected. macOS does not provide a supported API for reading Focus or Do Not Disturb state.

These checks reduce risk but do not replace consent, supervision, or judgment. Startle is not a medical or safety device.
