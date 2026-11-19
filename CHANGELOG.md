# Changelog

## 1.3.1 (2026-11-19)

### Fixed

- The debuff color over your frame is fainter, so your health bar stays easy to read when you're poisoned or diseased. The colored outline is the same as before.
- Exporting and importing profiles now works every time. After another popup with a short text box, like a friend note, the export text was cut short and importing it said it didn't look like a profile. The list of raid names was cut short the same way.
- Pressing Enter in the rename, import and save layout boxes does the same as clicking the button. If a profile name is taken or an import doesn't work, the box stays open so you can fix what you typed.

## 1.3.0 (2026-11-11)

### New

- **Options and Edit Mode, side by side.** Open Edit Mode and the Perl Infinity options open as a slim panel at the side of your screen, so you can move a frame and change how it looks without switching back and forth. Click a frame in Edit Mode to jump to its settings. Leave Edit Mode and the panel closes, or goes back to the full window if you had it open before. Drag the panel anywhere and it opens there next time. Turn off **Open with Edit Mode** on the General page if you'd rather open it yourself.
- **Your frames show samples while you tweak them.** With the options window open, empty frames (no target, no focus, not in a party) show a faded sample in their real spot, so every change shows up where it'll be. A sample steps aside as soon as the real frame appears.

### Fixed

- **Center names** moves names as soon as you turn it on or off. Before, they stayed where they were until you reloaded.
- Switching profiles, resetting your profile or importing one now changes colors, shading and the bar texture right away. Before, the old look stayed on screen until you reloaded.
- **Frame size** on the Raid page resizes raid frames and raid pets right away.
- Choosing **Only in one-group raids** under **In a raid** hides party frames in a bigger raid right away, instead of waiting for someone to join or leave.
- Setting **Group number** to **Hidden** takes the group number out of your name right away.
- The combo point fill on the target frame follows **Bar texture** like every other bar.
- **Number the tanks** and the healer window's **Show their targets** now stay the way you set them after a reload. Rows made when the raid formed used to miss them.
- Sample frames in Edit Mode follow your changes from the Edit Mode popup, and step aside when you target something. Before, they kept the look they had when Edit Mode opened.

## 1.2.2 (2026-11-10)

### Changed

- **Show mine bigger** is gone. Your own buffs and debuffs still come first in line, but at the same size as the rest. Giving them a bigger row of their own made them show up twice, because Forever has no reliable way to leave them out of the other row.

### Fixed

- Your own buffs and debuffs no longer show twice on party, target and focus frames.
- Targeting a player in a battleground no longer causes Lua errors.
- In a battleground, frames that first appear after the match starts, like a raid that forms after the gates open, get their buff and debuff icons when the match ends.
- Party targets and party pets no longer show a health or mana percent hanging outside their frame. They have no room for a percent column, so it stays hidden.

## 1.2.1 (2026-11-10)

### New

- **Center names.** Turn on **Center names** on the Appearance page to center each name in its box.
- **Creature type above the frame.** On the Target and Focus pages, **Creature type position** puts Beast, Humanoid and the rest above the frame instead of under the portrait.
- **Resting without the glow.** **Glow while resting** on the Player page turns off the gold glow around your frame and keeps the Zzz.

### Changed

- Your own buffs on the player frame are now all the same size. **Show mine bigger** made nearly all of them larger there, since you cast most of them. It still works on every other frame. Weapon enchants match your buffs too.
- Target of target, focus target, pet target, party targets and party pets have a taller health bar, which fills the empty space that used to sit under the mana bar. Party targets have no mana bar, so they're a little shorter now.

### Fixed

- Turning off the reputation bar on the player frame now hides it right away. Before, the inside of the bar stayed on screen until you reloaded.
- The creature type box no longer shows up empty when you target a player.
- On elites and bosses, the dragon no longer covers the health and mana percentages, the cast time or the end of a long name. The text now draws in front of it.

## 1.2.0 (2026-11-09)

### New

- **Your debuffs show on your own frame.** When you're poisoned, diseased, cursed or hit by a magic debuff, your player frame takes on its color, so you can tell at a glance without finding the game's debuff icons. Turn off **Debuff highlight** on the Player page if you don't want it.

### Fixed

- A poisoned party member's frame no longer turns bright green and hard to read. Other debuff colors had the same problem. The background tint is faint again, and choosing only the border or only the background under **Highlight style** works.
- Ready checks show again. The check mark, X and question mark never appeared on your frame, party or raid.
- Turning a frame on or off now works right away, from the options window or a key binding. Before, it waited for a `/reload`. Turning on the focus frame hid the game's focus frame and showed nothing in its place, and the raid frames key binding did nothing.
- Changing which way the party or raid grows, how the raid is sorted, or which way the tank window grows no longer leaves frames in a staircase until you reload.
- Sorting the raid by role with a class unticked no longer hides every raid frame.
- With names turned off, a party member's or pet's name no longer comes back after they cast a spell.
- **Frame opacity**, **Hide in battlegrounds**, the tank window's **Show who the enemy targets**, and the buff helper's **Sort names by** and **Only groups I can see** now work. Changing them used to do nothing.
- **Highlight style** can be changed even with the party debuff highlight off, since it also sets the look for your own frame, target and focus.
- The **Height** sliders for the tank and healer windows now resize the rows. The healer window's target column follows the healer window's settings instead of the tank window's.
- Buff and debuff icons on target and focus draw in front of the creature type and the elite dragon again, and the debuff outline shows on the portrait side too.
- With the portrait turned off, the creature type sits under the bars instead of covering the end of the health bar.
- Icons you turn on in the middle of a fight now appear when the fight ends, instead of waiting for a reload.
- The low health warning works with Perl Infinity's player frame turned off.
- Your own raid frame always counts as in range, so it never fades.

## 1.1.0 (2026-11-07)

### New

- **Elites and rares are easy to spot.** The gold X-Perl dragon now wraps an elite's portrait by default, and the frame's edges turn gold. Rares get a silver dragon, a "Rare" tag and a pulsing blue glow, so you don't walk past one. Bosses get a "Boss" tag and red edges. Choose Dragon, Label or None under **Elite style** on the Target and Focus pages.
- **Resting animation.** While you rest in an inn or a city, sleepy Zzz float above your portrait and your frame glows gold. You can turn it off on the Player page to get the still rest icon back.
- **Party targets and party pets move on their own.** Each has its own box in Edit Mode, so you can put them anywhere. They stay beside the party until you drag them, and **Reset position** in the box's popup puts them back.
- **Your buffs and debuffs on your player frame.** New Player page settings let you show your buffs and debuffs next to your frame, and hide the game's own buff or debuff display. Each setting is separate, so you can have both, either or neither. Right-click a buff to cancel it. Your icons start off, since the game already shows them. If you hide the game's display and later want it back, turn the setting on again and type `/reload`.
- **Weapon enchants**, like poisons and sharpening stones, can show on your player frame too. This starts off. Right-click one to cancel it.
- **Party members make room for their icons**, so one member's buffs and debuffs don't cover the next. Turn off **Make room for icons** to use your own spacing exactly. Party icons now default to one row so the party fits on screen. Raise **Rows** if you want more.
- **Full names.** Players show their first name and surname on every frame and in the raid buff check.

### Fixed

- Buff and debuff icons now show on target, focus, party and raid frames. In 1.0.1 they had no size, so they never appeared. The optional HoT timer bars on raid frames had the same problem.
- Each buff now shows once, in the right group for whoever cast it, and other players' buffs no longer go missing.
- Raid markers, leader crowns, role icons and PvP badges now sit in front of the frame instead of behind it. The ready check, resurrection and summon icons, the mind control warning and the out-of-range hand were hidden the same way, and now show.
- The game's made-up sample buffs no longer appear on Perl Infinity frames in Edit Mode.
- The screen edge no longer glows blue while you're on a flight path.
- Changing the party's size now applies right away instead of after a reload.

## 1.0.1 (2026-11-04)

- Perl Infinity now has its own icon in the addon list.

## 1.0.0 (2026-11-04)

First public release.

- Unit frames for your player, pet, pet's target, target, target of target, focus and focus target.
- Party frames with each member's target and pet, and raid frames with raid pets.
- Raid tools: tank targets, a healer mana window, class buff checks, aggro warnings and saved raid layouts.
- Move your frames in the game's Edit Mode, and change settings in a window with a live preview.
- Profiles you can share between characters or export as text.
