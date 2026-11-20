# Putting #ARENA 48 under a Roblox community: research (20 Nov 2026)

Experience: "#ARENA 48", place 120572716460286, universe 10775788705, owned by a user account.
Research only. Nothing was changed, uploaded or bought. Roblox Studio was not touched.

Words: Roblox now calls groups "communities". The Creator Hub docs still say "group" for the same thing. A December 2024 staff post described groups as the way to manage collaboration and communities as the way to engage players. They are the same object.

Labels used below:
- [DOC]: stated on an official create.roblox.com page (fetched today; the pages show last_updated 2026-11-20).
- [STAFF]: stated by a Roblox staff account on the DevForum.
- [FORUM]: other developers' reports. Not official.
- [INFERRED]: my reasoning, not stated anywhere official.
- [UNVERIFIED]: I could not confirm it.

---

## Short answer

Yes. Roblox has a free, self-serve, official transfer from a user account to a community (group), in Creator Hub. The universe ID, place ID and URL stay the same. Players, data and stats stay with the game.

What you have to fix by hand:
- Animations owned by the user account. These break and must be re-uploaded under the community.
- Private ModuleScripts, InsertService assets and user-owned packages. These must be re-uploaded or replaced under the community.
- Possibly audio. It is probably fine because it is already shared with the experience.

The game is taken offline during the transfer and has to be released again afterwards. The transfer is one-way: a game cannot go back from a community to a user.

---

## 1. The official transfer

Source: "Game ownership transfer", https://create.roblox.com/docs/en-us/projects/game-ownership-transfer (also at /experience-ownership-transfer), last_updated 2026-11-20. [DOC]

Announced free and self-serve on 9 Dec 2024 by peraldon (Roblox Staff): "Transfer Experiences to Groups & Track Group Activity", https://devforum.roblox.com/t/transfer-experiences-to-groups-track-group-activity/3299360. It replaced a manual service from 2023 that cost 30,000 Robux; that money was refunded. https://devforum.roblox.com/t/limited-availability-transfer-your-experience-to-your-group/2567881

### Requirements
- Both sides must have a verified email address. [DOC]
- The person starting the transfer must be able to publish games to the target community. That means being the owner or holding the "Edit & publish all group experiences" permission. [DOC] [STAFF meguminspire84, 28 Jan and 3 Feb 2025]
- Private ModuleScripts and InsertService assets must be uploaded to the community first. User-owned packages may need to be recreated under the community. [DOC]
- Direction: user account to community only. A community-to-community transfer was "on our internal roadmap" (staff post, 27 May 2025). I did not confirm whether it has shipped. It does not matter here. [STAFF]
- Transfer back to a user account: "it is not possible to transfer back to user." [STAFF meguminspire84, 28 Jan 2025]
- Fee: none. The transfer has been free since Dec 2024. [STAFF]
- Account age, ID verification or 2FA for the transfer itself: none listed in the transfer doc. Separate rules still apply to other things (see section 4, and the 2FA note under "Granting permissions" below). [DOC; no other transfer-specific requirement found]
- Regions: no regional limit mentioned. [UNVERIFIED]
- Time limits: a request expires after 7 days. After a game is received, it cannot be transferred again for 30 days. [DOC]

### Steps
Initiator (the current owner):
1. Creator Hub > Creations > the game > Publish Settings > Game details > Initiate ownership transfer.
2. Read and acknowledge the Transfer Details dialog. Its notices list what will break, so read them.
3. Pick the community.
4. Type the game name to confirm, then click Initiate transfer.
5. To cancel, use Cancel transfer request on the Content Settings page.

Receiver (the community owner, which can be the same person):
1. Open the game page from the notification or a link.
2. Acknowledge the Transfer Details.
3. Type the game name, then click Accept transfer.
4. Afterwards, set up permissions and release the game to the public again.

Warning [DOC]: "Once the group accepts the transfer, Roblox revokes access to your game from the public, and closes all servers." The transfer usually takes a few minutes. Edits made during the transfer are not carried over.

### What carries over and what does not

| Item | Result | Basis |
|---|---|---|
| Universe ID, place ID, URL | Kept | [DOC] |
| Discovery / search | Unaffected if the title stays the same, the new owner is not moderated, and the game is released again. May be affected for up to 24 hours after re-release. | [DOC]; staff said no SEO impact [STAFF 2023] |
| Visits, likes, favourites | Kept. Not listed by name in the doc. | [FORUM, several]; [INFERRED] they belong to the universe, which is unchanged |
| DataStores (player progress) | Kept. Not stated in any official text I found. | [INFERRED, high confidence] data stores are scoped to the universe and the universe ID is unchanged; [FORUM] "it would retain data stores, badges" |
| Badges | Kept | [STAFF peraldon, 10 Dec 2024]: "All of your developer products (ie Game Passes, Badges etc) will fully persist through the transfer." |
| Game passes, developer products | Kept, and become community-owned | [STAFF] same quote; [FORUM] "all gamepasses and dev products also transferred to group ownership" |
| Revenue | Money earned before the transfer stays with the old owner. Money earned after goes to the community. | [STAFF 2023 caveats] |
| Private servers and subscriptions | Existing private-server subscriptions keep running. Their revenue goes to the community and ignores revenue splits. New subscriptions follow the splits. | [DOC] |
| Credit card information on the game | Removed | [DOC] |
| Analytics | Not mentioned in the doc. Probably kept because the universe is unchanged. | [UNVERIFIED]; [FORUM] suggests downloading a CSV export first as a backup |
| Age rating / content questionnaire (Mild, 16+) | Not mentioned. Probably kept because it is a setting on the universe. | [UNVERIFIED]. Check Publish Settings > Manage Audience after the transfer |
| Open Cloud API keys | Usually unaffected when moving to a community you own. A key's power comes from the user who last generated it. If that user's access changes, create new keys. | [DOC] |
| Collaborators | The community's roles replace per-user sharing. Set up roles and permissions after the transfer. | [DOC] step 5; [INFERRED] any user collaborators must be re-added as community members/roles |
| Animations owned by the user | Break. Re-upload them under the community and map old IDs to new IDs. Docs: https://create.roblox.com/docs/projects/transfer-animations (found by search; the en-us .md version returned 404 today). | [STAFF 2023/2024]; [DOC per search snippet] |
| Audio owned by the user | Probably keeps working, because it is already shared with the experience. Check the experience's permissions page. | [STAFF ElusiveWind, 27 May 2025]: assets on the experience permissions page "are also already shared with the experience, so they may not need to be reuploaded"; [FORUM] "Sounds will need to be given access to your game" |
| Meshes and images owned by the user | Should keep working. Images, decals and meshes are Open Use by default unless Asset Privacy was turned on. Any game grants already made are permanent, and the universe is unchanged. | [DOC] "Asset privacy", https://create.roblox.com/docs/en-us/projects/assets/privacy (2026-11-20): "Game grants are permanent." [INFERRED] carries through. For new uploads, upload as the community. |
| Private ModuleScripts, InsertService assets, user-owned packages | Must be re-uploaded to the community or replaced | [DOC] |

Granting permissions: to give a community role sensitive permissions (for example publish or revenue), the person granting them must have two-step verification enabled. [DOC] "Groups (teams)", https://create.roblox.com/docs/en-us/projects/groups

Known risk: in July 2026 a community's publishing broke after a transfer. The cause was a mix-up over who owned the community, after Roblox changed how ownership works. Staff fixed it by hand. https://devforum.roblox.com/t/critical-publishing-fails-for-all-group-games-after-ownership-transfer-%E2%80%93-permissionsownership-issue/4751193 [FORUM + STAFF reply 22 Jul 2026]

Ownership change: since 17 Jun 2026, ownership is a property of the community itself, not the old rank-255 Owner role. Communities created on or after 16 Jun 2026 get no Owner role at all. https://devforum.roblox.com/t/community-ownership-is-now-managed-at-the-community-level/4687884 [STAFF announcement]

---

## 2. Alternative: republish under a community (not recommended)

This is only relevant if the transfer cannot be used.

Republishing means creating a new game under the community from the same place file. The new game gets a new universe ID, place ID and URL. It loses:
- all visits, likes, favourites and ratings;
- discovery history;
- every player's DataStore progress (data stores belong to the old universe);
- badges (they are tied to the old universe);
- existing private servers and their subscriptions;
- analytics history;
- the content questionnaire and age rating. These must be redone, and Kids & Select evaluation starts again.

Passes and products would need re-creating, and players who already bought the old ones would not own the new ones. [INFERRED from how these features are scoped]

Given the official transfer exists, there is no reason to do this.

---

## 3. Creating a community

- Cost: 100 Robux. [DOC] "Groups (teams)": "Creating a group costs 100 Robux."
- Roblox Plus discount: none. Plus discounts do not apply to "Group fees". [DOC] "Roblox Plus", https://create.roblox.com/docs/en-us/production/monetization/roblox-plus
- How: Creator Dashboard > account switcher > plus (+) > logo and name > Purchase. [DOC]
- Join limit: commonly given as 100 communities per account. [UNVERIFIED; third-party guides only, no official page found]
- Limit on how many you can create: not found in official sources. [UNVERIFIED]
- Owner accountability: if a community you own is permanently removed, you cannot own a new one for 90 days. Repeated removals mean losing the right to own communities. [DOC] https://create.roblox.com/docs/en-us/projects/group-guidelines

---

## 4. Effect on Roblox Plus perks and on Kids & Select eligibility

### Roblox Plus
Roblox Plus launched 30 Apr 2026 and replaced Premium.
- The owner's subscriber perks (discounts, free paid private servers and so on) belong to the user account. Nothing in the docs says a transfer affects them. [INFERRED]
- Creator earnings tied to the game will go to the community once it owns the game. These include Plus sign-up bonuses, paid private-server time and Robux-transfer shares. This follows from the rule that revenue after the transfer goes to the community. [INFERRED from the DOC/STAFF revenue rules]
- Source: https://create.roblox.com/docs/en-us/production/monetization/roblox-plus

### Kids & Select
Source: "Roblox Kids and Select", https://create.roblox.com/docs/en-us/production/publishing/kids-and-select (2026-11-20). [DOC]

For a community-owned game, the requirements fall on the community owner: "creators of individual-owned games or group owners of group-owned games must meet the following requirements".

To reach under-16 players (Kids & Select), the owner needs:
- an account in good standing;
- verification: government ID if 18 or older, facial age estimation if under 18;
- 2FA on the account;
- a completed content questionnaire with a Minimal, Mild or Moderate rating;
- one of:
  - an active Roblox Plus or Premium subscription held for 2 consecutive months, or
  - a one-time refundable fee;
- an evaluation pass: 100 unique plays by highly engaged, age-checked players within 60 days.

Optional expedited review: a refundable fee of 50,000 Robux per game. (A forum post from July 2026 mentions paying 100,000, so the amount has changed during 2026.)

To reach players aged 16 and over, the owner needs an account at least 2 days old in good standing, plus an age check.

What this means here [INFERRED]: if the same person who owns the game also owns the community, the owner-based checks should still pass. That covers verification, 2FA and the 2-month Plus subscription. Whether the evaluation progress or eligibility already earned (plays counted, current audience) survives the transfer is not documented. [UNVERIFIED] Check Publish Settings > Manage Audience straight after re-releasing. If the community were owned by someone else, that person would need to meet every requirement.

---

## Suggested order (if the owner chooses to do it)

1. Create the community (100 Robux), owned by the same account, with 2FA on.
2. List the animations, private modules and packages the place uses. Re-upload the animations under the community and add old-to-new ID mapping in code.
3. Export analytics to CSV as a backup.
4. Pick a quiet time. Start the transfer and accept it.
5. Re-check:
   - audio, meshes and images;
   - the rating and Manage Audience;
   - passes;
   - private servers;
   - Open Cloud keys.
6. Release the game again on the same day.
7. Wait 30 days before any further transfer.

## Sources
- https://create.roblox.com/docs/en-us/projects/game-ownership-transfer (last_updated 2026-11-20)
- https://create.roblox.com/docs/en-us/projects/groups (2026-11-20)
- https://create.roblox.com/docs/en-us/projects/assets/privacy (2026-11-20)
- https://create.roblox.com/docs/en-us/production/publishing/kids-and-select (2026-11-20)
- https://create.roblox.com/docs/en-us/production/monetization/roblox-plus (fetched 2026-11-20)
- https://create.roblox.com/docs/en-us/projects/group-guidelines (fetched 2026-11-20)
- https://create.roblox.com/docs/projects/transfer-animations (search result only; not loaded)
- https://devforum.roblox.com/t/transfer-experiences-to-groups-track-group-activity/3299360 (staff, 9 Dec 2024; staff replies through 27 May 2025)
- https://devforum.roblox.com/t/limited-availability-transfer-your-experience-to-your-group/2567881 (staff, 28 Aug 2023)
- https://devforum.roblox.com/t/community-ownership-is-now-managed-at-the-community-level/4687884 (staff, 17 Jun 2026)
- https://devforum.roblox.com/t/critical-publishing-fails-for-all-group-games-after-ownership-transfer-%E2%80%93-permissionsownership-issue/4751193 (22 Jul 2026)
- https://devforum.roblox.com/t/does-experience-ownership-transfer-transfer-other-things/3858493 and https://devforum.roblox.com/t/when-you-transfer-a-game-to-a-group-what-assets-does-it-transfer-over/3334767 (developer reports, 2025)
