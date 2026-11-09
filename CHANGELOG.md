# Changelog

## Unreleased

### New

- **Your debuffs show on your own frame.** When you're poisoned, diseased, cursed or hit by a magic debuff, your player frame takes on its color, so you can tell at a glance without finding the game's debuff icons. Turn off **Debuff highlight** on the Player page if you don't want it.

### Fixed

- A poisoned party member's frame no longer turns bright green and hard to read. Other debuff colors had the same problem. The background tint is faint again, and choosing only the border or only the background under **Highlight style** works.

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
