# Google Play release kit

Everything to fill in for Valrove's Play Console entry. The images in this folder are
ready to upload.

| File | Use |
| --- | --- |
| `icon-512.png` | App icon (512 × 512) |
| `feature-graphic.png` | Feature graphic (1024 × 500) |
| `screenshots/*.png` | Phone screenshots (1080 × 2160), in this order |

The screenshots and the feature graphic are rendered from the app:
`flutter test test/store --update-goldens --dart-define=STORE_ASSETS=true`. The icon comes
from `node tool/icons/render.mjs`.

## Build and upload

```sh
flutter build appbundle --release --dart-define=STORE=play
# build/app/outputs/bundle/release/app-release.aab
```

The bundle is signed with the upload key from `android/key.properties`. Keep Play App
Signing turned on (the default): Google then signs the app for users, and a lost upload
key can be replaced.

## Store listing

**App name** (30 characters at most)

> Valrove: Robot Vacuum Remote

**Short description** (80 characters at most)

> Map-first, cloud-free remote for robot vacuums running Valetudo.

**Full description**

> Valrove is a fast, good-looking app for robot vacuums that run Valetudo, the open-source
> firmware that frees robots from the cloud.
>
> Your home's live map fills the screen. Tap rooms to clean them, draw zones, or send the
> robot anywhere. Everything else is a swipe away.
>
> EVERYTHING VALETUDO CAN DO
> • Room, zone and go-to cleaning with suction, water and mode presets
> • Schedules, consumables, statistics and achievements
> • Map editing: split and join rooms, virtual walls, no-go and no-mop areas
> • Dock controls, robot options, sound and do-not-disturb
> • Wi-Fi, MQTT, updates, logs and system information
> Valrove reads what your robot supports and shows exactly that.
>
> MORE THAN THE WEB INTERFACE
> • Presets: start your favourite cleanups with one tap, from the app, a home screen
>   widget, a quick settings tile or an app shortcut
> • A live notification while the robot cleans, with Pause and Dock buttons, and alerts
>   when it's done, stuck, or the bin is full
> • Voice commands such as "clean the kitchen and the hallway twice"
> • Time and battery estimates, a cleaning history and a map of when each room was last
>   cleaned
> • Wi-Fi coverage map, lost & found for obstacles, and wear forecasts for brushes and
>   filters
> • Light and OLED-black dark themes
>
> PRIVATE BY DESIGN
> No cloud, no account, no ads, no analytics. Valrove talks only to your robot, directly
> on your own network.
>
> No Valetudo robot yet? Tap "Try the demo" on the first screen to look around.
>
> Valrove needs a robot vacuum running Valetudo (valetudo.cloud) on the same network as
> your phone. It is an independent app and is not affiliated with the Valetudo project.

**Category:** House & Home. **Tags:** smart home, home automation.

**Contact details:** an e-mail address is required and shown publicly. A separate address
for the app keeps your personal one private.

**Privacy policy URL:** the public link to `PRIVACY.md` in the GitHub repository, for
example `https://github.com/<you>/<repo>/blob/main/PRIVACY.md`.

## App content (Policy → App content)

**Privacy policy:** the URL above.

**Ads:** No, the app contains no ads.

**App access:** choose "All or some functionality is restricted" and add these
instructions:

> Valrove controls robot vacuums running Valetudo on the local network, so a robot is
> needed for real use. To review every screen without one, tap "No robot at hand? Try the
> demo" on the first screen. The demo robot runs inside the app and plays along with
> commands (start, pause, dock, presets, settings). No login is needed.

**Content rating:** fill in the questionnaire with category "Utility, Productivity,
Communication, or Other" and answer No to every content question (violence, sexual
content, language, drugs, gambling, user interaction, sharing location, digital purchases).
That gives the lowest rating (Everyone / PEGI 3).

**Target audience:** 18 and over. The app isn't made for children, and leaving out the
younger age groups keeps it out of the Families policy.

**News app:** No. **Government app:** No. **Financial features:** none. **Health:** none.

**Data safety:**

- *Does your app collect or share any of the required user data types?* No.
- Reasoning: Valrove sends nothing to the developer or third parties. It connects only to
  the user's own robot on their network. Its data (robots, history, settings) stays on
  the phone. Voice commands go through the phone's speech recognition service, which
  Valrove doesn't control; the app receives only the text and doesn't send it anywhere.
- With no data collected, the questions about encryption and deletion requests don't
  apply.

**Foreground service** (asked because Valrove targets Android 14+):

- Type: Connected device.
- Description:

  > While the user's robot vacuum cleans, Valrove shows a live notification with the
  > cleanup's progress (rooms, area, time, battery) and Pause and Dock buttons. The
  > foreground service talks to the robot over the local network every five seconds and
  > stops on its own when the robot is back at its dock. Users can turn it off in the app
  > settings.

- Video: Google asks for a link to a short video (an unlisted YouTube video works)
  showing a cleanup starting, the notification and its buttons. Record it with a real
  robot: the demo robot doesn't start the service.

**Permissions** (no forms needed): microphone (voice commands, asked when first used),
notifications (cleanup notification), Wi-Fi multicast (finding robots on the network).

## Testing before production

New personal developer accounts need a closed test first: at least 12 testers opted in
for the last 14 days in a row. Then apply for production access in the Play Console.

1. Testing → Closed testing → create a track, upload the bundle, add a list of tester
   e-mail addresses (or a Google Group) and share the opt-in link.
2. Keep at least 12 testers opted in for 14 days.
3. Apply for production access, then create the production release.

**Release notes for the first release:**

> First release: live map, room and zone cleaning, presets with widget and quick settings
> tile, cleanup notifications, voice commands, map editing and all of Valetudo's settings.
