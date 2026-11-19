// GENERATED from the Valetudo web interface (Apache-2.0, (c) Sören Beye and contributors).
// Source: frontend/src/**/res/*.ts. Do not edit by hand.
// ignore_for_file: lines_longer_than_80_chars

abstract final class HelpTexts {
  static const duststreamingLecture = '''Hey,

Quick pause for a second.

You're about to enable a feature that is really cool, but also fundamentally changes your whole threat model.<br/>
And not just for you but **also(!)** for the people that live with you or might visit you.

Where previously a vacuum robot was just a vacuum robot, it can now act as a hidden spy cam, leaving bystanders with absolutely no way of knowing they might be recorded.

This is bad for third-parties like your partner or visiting friends, because privacy is a fundamental human right. Disregarding it - even just through lack of care - may result in loss of trust, loss of faith and all the downstream consequences that follow.
Additionally, it is simply bad for you too, because it might affect you in the same way, as any network connected device might at one point be controlled by a possibly hostile third-party.

Therefore, anyone visiting your space **needs** to be aware that someone or something may be watching them through the robot.
This is an ethical requirement, and, depending on where you live, it might also be a legal requirement.

Because you are affected in the exact same way, you need to stay aware of this too.
You will, however, eventually, forget that that is the case, and you should plan for that likely inevitable outcome.

It might make sense to play around with this feature for a while, have some fun and then just disable it again instead of letting the capability linger unused, ready to be misused.
While doing so, you will see just how inconspicuous it is, and just how much these bots can see.

In a better world, vendors would build robots with cameras that have hardwired activity LEDs. And, ideally, they would work fully offline.

<br/>

**Note**:

This feature comes with an unauthenticated remote killswitch, enabling weird internet vigilantes to do damage control while doomscrolling accidentally exposed IoT on shodan. That however only somewhat helps and only does so against outside threats, which are the far less likely failure mode here.

It should go without saying that surveillance fundamentally cannot fix a lack of trust, even though security vendors would love to make you believe otherwise.
More cameras do not make your home more secure and they certainly can't fix relationships either.

- Do not unilaterally decide to enable this in secret.
- Do not ask for consent in a way engineered so that saying yes is the only easy option.
- Do not place the burden of refusal on the other party.
- Do not take lack of complaining as consent.

Essentially, resist the defaults.<br/>
Be the antithesis to current market trends: make opting out and saying no entirely frictionless.

We do have to live in this world, but we do not have to be part of it.<br/>
Now go have some ethical™ fun.''';

  static const mapAnnotationsHelp = '''## Map Annotations

Map annotations are the generic concept to house any kind of "there is something on the map the robot needs to be aware of, which might not be reliably auto-determined".
For example, depending on firmware support, that could be a passable threshold, a curtain, a ramp or similar.

These things existing in the map make the firmware behave differently in some way relating to the location they're at.
It might then take a specific path or trust its obstacle avoidance less or really anything like that.

Specifically:

#### Thresholds

Thresholds hint the firmware that the obstacle it is seeing is actually something it can cross if it just tries harder.
Without the annotation, it might not realize that it can.

#### Ramps

Ramps hint the firmware that there is a working dedicated path to take to reach a specific area.
Without the annotation, it might not realize that it exists.

#### Curtains

Curtains hint the firmware that the obstacle it is looking at actually isn't one and that it can just drive into it.
Without the annotation, it doesn't realize that that is the case.''';

  static const robotCoverageMapHelp = '''## Robot Coverage Map

By rendering the path with a much thicker stroke, this live map view allows you to easily spot areas that weren't reached
by the robot.''';

  static const segmentEditHelp = '''## Segment Management

A segment is a partition of the map as decided by the robots' firmware.
Segments enable you to just clean one or more predefined areas. Most firmwares also allow naming them.

You may know them as rooms, however they don't necessarily have to be actual rooms.
There could for example be a segment, which is just the area around your dining table.

On most firmwares, the robot uses the segment data to optimize its navigation and drive the most efficient path.


You can select a segment by clicking on it. Depending on your firmware, you can then split it into two or give it a name.
If you select another segment, you can also join the two to form one bigger segment if the firmware allows that.


Segment colors are determined on-the-fly by the map renderer and don't mean anything. They're simply different so that you
can distinguish them from each other. From time to time segments might also change color because one or more of its pixels changed.

### Common issues/Questions

#### I don't see any segments

You can only edit segments if there are any. If you only see a blue map then you have no segments.

Make sure that you've done a full cleanup task with the robot returning to its dock on its own without any interruption.
This is usually required for the robot to split the map into segments.

Also, some firmwares might need you to manually enable the saving of persistent maps before starting that full cleanup task.

#### I can't split a segment

Sometimes, the cutting line placement needs some wiggling to work.
It is not required to carefully place the cutting line exactly between the wall pixels. In fact, this often prevents
a successful split. Try dragging it over the whole width/height of the segment instead of just parts of it.

In some room layouts, you also might have to split a segment multiple times and then rejoin some of those parts to get 
the desired result.

#### Can I delete a segment?

No.''';

  static const virtualRestrictionEditHelp = '''## Virtual Restriction Management

Virtual restrictions are things such as virtual walls, no go areas or no mop areas, that either stop your robot
from driving somewhere all the time or just conditionally (e.g. when there's a specific attachment such as the mop attached to it).

You can use virtual restrictions to protect your fragile furniture from your robot or your fragile robot from your furniture.

Not all firmwares support all of those. Also, usually, there's a firmware-determined limit on how many virtual
restrictions you can have.


Keep in mind that while these work great most of the time, robots may sometimes forget where they are and then start
driving around not knowing anything about any of the previously configured virtual restrictions.
Make sure that they're not the only thing preventing a disaster.


Note that you won't see any map updates while editing unless you press refresh.
Therefore, don't forget to click save before refreshing and/or leaving this page to commit your changes.''';

  static const mapManagementHelp = '''## Map Management

This page allows you to do map-related tasks. What exactly can be done here depends on your model of robot as well
as its firmware.<br/>If you don't see something on this page, it is likely not supported by your robot.

Some robots may require you to manually enable persistent maps before you can do most map-related things.
Others may not even allow disabling of persistent maps because why would you.

There are also some legacy robots, which don't feature persistent maps at all.

Some robots may require a full cleanup task including them returning to the dock on their own for a new map to be saved.
Others may either optionally allow for fast mapping via a mapping pass or even require a mapping pass before they can be used.

### Terminology

Please note that all these concepts need firmware support by your robot.
Not everything might be available on every robot. 

#### Segments

A segment is a partition of the map as decided by the robots' firmware.
Segments enable you to just clean one or more predefined areas. Most firmwares also allow naming them.

You may know them as rooms, however they don't necessarily have to be actual rooms.
There could for example be a segment, which is just the area around your dining table.

On most firmwares, the robot uses the segment data to optimize its navigation and drive the most efficient path.

#### Zones

Zones are just rectangles that you can draw on the map to send the robot there.
Depending on the firmware of your robot, it might accept just one or multiple zones as an input.''';

  static const mapUtilitiesHelp = '''## Map Utilities

In this section, you will find useful things built on top of the map data provided by the robot.''';

  static const doNotDisturbHelp = '''## Do not disturb

Some firmwares allow you to define a do not disturb period where certain features of the robot are disabled.
What exactly changes may differ based on robot vendor, model and firmware version.

For example, the robot might not continue a partially finished task which has been interrupted due to the
robot having to charge.
As charging back up to 100% battery may take a few hours, it could happen that the robot attempts to continue cleaning
at 3am, which is often considered undesirable.

Another thing that can be affected by the DND setting is the auto empty dock as those are usually pretty loud.


**Please note that DND times are evaluated and stored as UTC. They are only displayed in your current browser timezone
for your convenience.**''';

  static const quirksHelp = '''## Quirks

Valetudo aims to be a generic abstraction. That means that it tries to unify vendor-specific commands and concepts
into generic ones so that you don't have to worry about which brand of robot you buy as Valetudo will work
the same on all of them.

Sometimes however there might be things that only one Vendor or even only one model of robot does.
Adding that to the core infrastructure of Valetudo wouldn't make sense as the generic interface would soon become an 
interface specific to one particular robot which would go against the core goal of being vendor-agnostic.

Still, limiting features to the least common denominator may at times also not be ideal.
This is where quirks come in.

**A quirk is a vendor, robot or firmware-specific tunable that doesn't fit into Valetudo (yet?).**

The availability of a quirk may change at any time depending on various factors.
If there are similar quirks across multiple vendors, these will likely at one point become a real capability with
real REST endpoints etc.

Think of quirks as some kind of convenience playground testing section.
Usually, they will be tunables that you change once and then likely never touch again.

Please don't try to automate changing quirks as there are no guarantees whatsoever in regards to both stability
as well as availability. They just exist for this UI.''';

  static const voicepackHelp = '''## Voice packs

Custom voice packs are a bit more complicated as the exact format differs depending on your choice of robot.

As I personally don't really care about them, this feature is a bit rough around the edges.
For me, these things are first and foremost tools that should simply work and do so reliably.
Thus, I'm fine with it just talking english as that's perfectly serviceable for a tool.

If you want to install a custom one anyways, you will need a voicepack in the correct format as required by your
robot hosted on some http server. Note that the official CDN is often blocked in the robots firmware meaning that just
using the official URL likely won't work.

Depending on the model of robot, you will also need a hash of that voice pack file.
The type of hash differs depending on the firmware.

Furthermore, you'll also need to specify a language code. That value largely doesn't matter much unless you use a reserved code.
"EN", "CN" etc are often codes reserved for the inbuilt voice packs of the firmware.

Usually it's possible to revert to the initially installed voice pack by specifying one of those inbuilt voicepack codes during the install.''';

  static const consumablesHelp = '''## Consumables

Consumables are components of the robot that need periodic cleaning, replacement or other maintenance work.

They come in two flavours, which are basically the same
- operating hours left
- percent left

At some point, they will become depleted, requiring you to do maintenance and reset them in the Valetudo UI.
This will restore them to either their manufacturer-dependent design operating hours or 100%.

Not maintaining your consumables may lead to performance degradation.<br/>
Still, Valetudo recommends manual inspection of the part in question. You _may_ be able to use it longer than the manufacturer recommends.


### Types of consumables

There are various types of consumables that require different treatment.

#### Brushes

Brushes come in different types such as main or side.
At some point, they are worn out and have to be replaced.

They often also require removal of tangled hair or similar for optimal performance, so you should keep an eye on them.

#### Filters

Vacuum-robots usually have some kind of filter, which needs periodic cleaning and replacing when it is worn out.

#### Sensors

Your robot has a few sensors such as cliff- or wall-distance-sensors, which are used for navigation and might get obstructed by dirt, debris, cobwebs or similar.
Cleaning them can usually be done with a soft cloth. Make sure to not scratch the sensors as they are vital to the robot's operation.

#### Wheels

Similarly to the sensors, it also makes sense to check the wheels from time to time and remove any dirt and debris.

#### Mops

While replacing mop pads might not always be necessary, it is strongly recommended to properly wash them from time to time.''';

  static const aboutText =
      '''Valetudo is made, managed, maintained and more by me,
<a href="https://hypfer.de" rel="noopener" target="_blank">Sören Beye</a>, with occasional contributions by
<a href="https://github.com/Hypfer/Valetudo/graphs/contributors" rel="noopener" target="_blank">these awesome people</a>.
It would not exist without the foundational work of <a href="https://dontvacuum.me/" rel="noopener" target="_blank">Dennis Giese</a>,
whose ideas, work and expertise created the environmental conditions for Valetudo to form.

Initially, the idea was to have a list of all open-source libraries and tools used in the making of Valetudo here,
however, it was quickly discovered that that would not be viable, as an exhaustive list including all transitive
dependencies contains thousands of projects.

We're all standing on the shoulders of giants. (<a href="https://xkcd.com/2347/" rel="noopener" target="_blank">XKCD 2347</a>)''';

  static const helpText = '''Please note that this is just the general help section for answers that didn't fit elsewhere.
Look out for question mark buttons for more context-specific help.

### What are those triangles on the map?

Those are segment labels.
If a segment is considered active by the robot - meaning that it is part of the robots current task - the triangle will
point down. Otherwise, it will point up.

If you zoom in on a segment label, it will display the segment ID and its size in m².


### How do I open the controls of the home page on mobile?

Just tap on the bar at the bottom of the screen.

### How do I get the coordinates/parameters of segments/zones/go-to locations to trigger them via MQTT/REST?

Simply configure/select the segments/zones/go-to locations like you'd normally do and then long-press the button that would start the action.
This will bring up a dialog providing you with everything you'll need.

### What's up with the AI Assistant?

The "AI Assistant" feature is a joke about the joke that is our industry, featuring a JavaScript implementation of ELIZA.
Created in 1966 by Joseph Weizenbaum, ELIZA was one of the very first chatbots and is famous for being one of the earliest programs to fool people into thinking that it passed the Turing test.

Fittingly, Weizenbaum himself also had some opinions about this industry.<br/>
Quoting Wikipedia:<br/>
> His belief was that the computer, at its most base level, is a fundamentally conservative force and that despite being a technological innovation, it would end up hindering social progress.
> Weizenbaum used his experience working with Bank of America as justification for his reasoning, saying that the computer allowed banks to deal with an ever-expanding number of checks in play that otherwise would have forced drastic changes to banking organization such as decentralization.
> As such, although the computer allowed the industry to become more efficient, it prevented a fundamental re-haul of the system.
>
> Weizenbaum also worried about the negative effects computers would have with regards to the military, calling the computer "a child of the military."

You can read more about ELIZA here: <a href="https://en.wikipedia.org/wiki/ELIZA" rel="noopener" target="_blank">https://en.wikipedia.org/wiki/ELIZA</a>''';

  static const updaterHelp = '''## Updater

The Valetudo updater is a convenience feature aiming to make life with Valetudo a bit easier.

As it is built with privacy in mind, you will have to manually click a button to make it search for newer versions of Valetudo.
No daily update check means no daily pings to some external server.

By default, it's polling the GitHub API, meaning that I am not able to collect any data about you.

**Note: The updater will always try to update you to the next chronological release. If you're multiple releases behind,
you will have to update multiple times in a row.**

As the updater is just a convenience feature, there might be situations in which it doesn't work. In those situations,
you will have to do a manual update, which usually involves SSH access to the robot.

Sometimes, a configuration change might enable you to use the updater. In other instances, your model of robot might not
be able to use the updater at all as there's not enough storage built in. This is not a bug. That's just how it is.

It is also worth noting that the updater won't update the robots firmware. It only updates the Valetudo binary.''';

  static const timersHelp = '''## Timers

Timers allow you to execute a task at a specified time (UTC).<br/>
If the system time isn't plausible (e.g. like when it has never been synced), no timers will be executed.

Please note that timers are evaluated and stored as UTC. They are only displayed in your current browser timezone.<br/>
This means that they will not follow any DST rules and thus will have to be updated manually if so required.''';
}
