# Roadmap

Planned ideas for Must Salah. Nothing here is scheduled yet.

## Planned

### Full-screen pause at adhan time

Cover every screen when a prayer starts, so it's hard to keep working through it.

- Off by default, turned on by the user, and set per prayer.
- Always has a visible way out, such as a Dismiss button or a short timer.
- Shows the prayer name and time, and plays the adhan if it's enabled.
- A sandboxed app can't truly lock the Mac or stop other apps, so this is a window above everything else, not a real block. Keep it easy to leave, for App Review and for people presenting or in a call.

### Built-in adhan audio

Offer ready-made adhan recordings to choose from, while keeping the option to use your own file.

- Only ship recordings with written rights to redistribute them, or record our own.
- Bundling audio increases the app's size, so start with one or two recordings.

### Verse or hadith before each prayer

Show a Quran verse or hadith about the adhan or prayer in the 10-minutes-before alert, with a toggle in Settings.

- Bundle the content so it works offline and no data leaves the Mac.
- Provide the text in en, id and ar. Check the license of every translation used.
- Have someone qualified check each text and its source before shipping.
- Notifications have limited space, so keep the text short or show the full text in the panel.

## Ideas

### Prayer times

- **More calculation methods** for users outside Indonesia, such as Muslim World League and Umm al-Qura, plus a Hanafi Asr option.
- **Separate adhan for Subuh**, since its wording differs from the other prayers.
- **Choose the alert timing** instead of a fixed 10 minutes before.

### Ramadan and Fridays

- **Ramadan mode** with an Imsak and Maghrib countdown in the menu bar.
- **Jumat reminder** earlier on Friday, with its own timing.

### Panel and desktop

- **Qibla direction** in the panel, using the Qibla support in adhan-swift.
- **Monthly schedule** view.
- **Menu bar styles**: icon only, name only, or full countdown.
- **Desktop and Notification Center widgets.**
- **Adhan volume control**, separate from the system volume.

### Quality

- **Automated tests** comparing calculated times against official Kemenag tables.
- **Investigate a one-minute difference**: Dzuhur in Bandung showed as both 11:36 and 11:37 on 9 Nov 2026 in different captures. Check whether small location changes move a time across a minute boundary, and whether the app should round or stabilize its coordinates.
