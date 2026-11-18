# Roblox rules for kits, wheels, loot boxes and currency (read 18 Nov 2026)

Research only. Sources were read on 18 Nov 2026. Dates are the page's "last updated" stamp or the post date.

## Sources
| # | Source | Date |
|---|---|---|
| S1 | create.roblox.com/docs/production/monetization/paid-random-items | updated 2026-11-17 |
| S2 | create.roblox.com/docs/production/monetization/randomized-virtual-items-policy | no date shown (2026 copyright); same content as S1 |
| S3 | create.roblox.com/docs/reference/engine/classes/PolicyService | read 2026-11-18 |
| S4 | about.roblox.com/community-standards (Roblox Economy, Gambling, Cheating) | no date shown (2026) |
| S5 | create.roblox.com/docs/production/promotion/content-maturity | updated 2026-11-10 |
| S6 | create.roblox.com/docs/production/promotion/content-ratings | updated 2026-11-17 |
| S7 | DevForum "Clarifying Requirements for Paid Random Items" (/t/4654622), Announcements category (id 36) | 2026-05-26. The author's account has no staff flag in the JSON; the post is in Announcements, so it is very likely official, but that is not proven |
| S8 | DevForum "Update on Paid Random Items Restriction for UK Users Under 18" (/t/3072183), posted by account "Roblox" (staff) | 2024-07-16, effective 2024-08-13 |
| S9 | en.help.roblox.com "New Updates for Our Brazilian Community" (Brazil Digital ECA) | 2026 (Brazil under-18: 17 Mar 2026; unverified 18+: 31 Mar 2026, according to secondary reposts) |
| S10 | create.roblox.com/docs/production/monetization/developer-products | updated 2026-11-17 |
| S11 | create.roblox.com/docs/reference/engine/classes/MarketplaceService (ProcessReceipt, BindReceiptHandler) | read 2026-11-18 |
| S12 | create.roblox.com/docs/production/monetization/roblox-plus | no date shown (Plus launched 2026-04-30) |
| S13 | create.roblox.com/docs/production/monetization/managed-pricing | updated 2026-11-17 |
| S14 | create.roblox.com/docs/production/promotion/rewarded-video-ads and AdService reference | updated 2026-11-17 |
| S15 | DevForum "Alternate Publishing Requirements for Roblox Kids and Select" (/t/4630944), staff | 2026-05-11 (updated 19 May) |

## 1. What counts as a "paid random item" (PRI)
- A PRI is any random outcome bought with Robux, either directly or "indirectly via in-game currencies acquired with Robux" (S4, S1). It covers wheels, eggs, chests and crates (capsule items), random upgrades (enhancement items), combine-for-random items, and probability modifiers such as luck boosts, pity systems and rate-up items.
- **Mixed currency.** If coins can be bought with Robux, a wheel spin or loot box paid for with coins is a PRI, even when this particular player earned those coins by playing. The rule is about the currency, not the individual coins. Roblox has not ruled on this case: it was asked in S7 (13 Jun 2026) and got no staff answer. This reading is the strict one, and we should build to it.
- **Bundles.** A pack that contains any random item makes the whole pack a PRI (S4, S7).
- **Indirect purchases.** Keys, spin tickets and re-roll tokens bought with Robux or with Robux-bought currency count. Odds must be shown before the currency is spent (S1).

## 2. Odds disclosure (exact requirements)
- Every possible outcome and its numerical odds must be shown before purchase. S4 says they "must be accurately and numerically disclosed to the eligible user before the moment of purchase".
- Odds are shown as percentages that sum to 100%. Long decimals may be rounded "to four or more decimal places lower than the first non-zero digit" (S7), with the disclaimer: "Probabilities are rounded; total of displayed individual probabilities may not equal 100%."
- If many items share the same odds, one statement at the top of the list is enough (S1).
- If the full list is too long to show, put it behind a clickable button labelled with a word, such as "Info" or "Details". A bare (i) icon is not enough (S1).
- If an outcome can be won only once per player, the odds shown must update to that player's real chances (S1).
- Odds modifiers (luck, pity) must have their numerical effect explained before purchase, and the odds shown must update while they are active (S1, S4).
- **No-loss rule:** "All possible outcomes for a paid random item must provide some benefit to the user; there cannot be a possible outcome which results in the user simply losing their payment." (S4). The wheel can never land on "nothing".
- Gambling: S4 bans "both simulated and actual gambling activities". No real money, Robux or in-game items of value may be staked on a game of chance.

## 3. Restricting players by region and age (PolicyService)
API: `PolicyService:GetPolicyInfoForPlayerAsync(player)`. It yields, so wrap it in `pcall`. On the client it works only for the local player. More than 100 calls in flight raises the error "GetPolicyInfoForPlayerAsync is called too many times". The full list of dictionary keys read today (S3):
- `ArePaidRandomItemsRestricted` (bool): when true, the player cannot use paid random item generators, whether paid in Robux or in Robux-bought currency.
- `IsPaidItemTradingAllowed` (bool): when false, the player must not trade paid items. This covers all paid items, not only random ones.
- `AreAdsAllowed` (bool)
- `IsEligibleToPurchaseCommerceProduct` (bool)
- `IsEligibleToPurchaseSubscription` (bool)
- `IsContentSharingAllowed` (bool)
- `IsPhotoToAvatarAllowed` (bool)
- `IsSubjectToChinaPolicies` (bool)
- `IsEndlessContentLoadAllowed` (bool)
- `IsEndlessContentAutoplayAllowed` (bool)
- `AllowedExternalLinkReferences` (array, legacy, always empty)

There is no newer PRI-specific field. `ArePaidRandomItemsRestricted` and `IsPaidItemTradingAllowed` are the only two.

For a player with `ArePaidRandomItemsRestricted == true`, S1 says to use one of these:
- give them a free, earnable path to the item;
- give the outcomes in a fixed, disclosed order;
- sell the specific outcome directly, priced at its expected value;
- remove or hide the item;
- block the purchase with an error message;
- move the player out of the area that sells it.

Known restricted groups (Roblox sets the flag; we never hard-code countries or ages):
- UK users under 18, by account birthday, since 13 Aug 2024 (S8).
- Brazil users under 18 since 17 Mar 2026, and unverified Brazil users 18 and over since 31 Mar 2026 (S9).
- S7 lists the regulated markets as Australia, Belgium, Netherlands, United Kingdom and Brazil, and says to test them in Studio's Player Emulator.

**Penalty for skipping the API.** A game that declares PRIs in the questionnaire but does not use the API "automatically becomes unavailable to UK users under the age of 18" (S8). S9 says the same for Brazil users under 18.

**Under 13, Roblox Kids and Roblox Select.** No official rule today bars PRIs by age outside those regions. The claim that PRIs are "restricted by default for all users 18 and under, with parental approval" comes from a non-staff DevForum post (S7 page 4, 28 May 2026) and is not policy.
- Kids (ages 5–8) and Select (ages 9–15) take Minimal or Mild games (S5, S6). We are rated Mild.
- The Kids and Select publishing requirements (S15) cover a refundable 1,000-Robux fee or engaged-player thresholds. They say nothing about PRIs.
- A newer DevForum post, "Roblox Kids and Select: New Restrictions on Reward-Driven Media Feeds" (/t/4829188, about Aug 2026), bars games that combine a media feed with rewards. This does not apply to us.

## 4. Questionnaire (Maturity & Compliance / Content Ratings)
S5 lists these questions:
- "Does this game contain paid random items?"
- "Does this game respect the ArePaidRandomItemsRestricted policy API?"
- "Does this game contain the ability for users to trade items that they paid for?"
- "Does this game respect the IsPaidItemTradingAllowed policy API?"

S6 says: "If your game sells randomized rewards that meet Roblox's Randomized Virtual Items Policy, answer yes." It also requires an update and resubmission whenever we publish a change that alters an answer. If the answers are inaccurate, moderation will ask for a correction. If the game has no ratings, its playability is restricted.

So, on the release that adds paid wheels or boxes:
- answer **Yes** to PRIs;
- answer **Yes** to respecting the API;
- answer No to trading, unless we add trading;
- resubmit the questionnaire in the same session as the publish.

## 5. Currency earned only by playing, and free spins
- A random outcome that cannot be purchased "directly or indirectly" is not a PRI and is not subject to the policy (S7). S1 adds that randomized rewards earned without spending Robux or in-game currency need no odds disclosure.
- This holds only if the currency can never be bought with Robux, in any pack, bundle, developer product, game pass or ad reward. If one developer product ever sells that currency, every wheel that takes it becomes a PRI (section 1).
- Free daily spins and level-up spins that cost nothing are not PRIs. No odds disclosure is required, but showing the odds anyway is good practice and costs nothing.
- **Watch-ad-for-spin is not allowed.** Rewarded video ad rewards must "Not be a randomized item" and must "Not inflate currency or unbalance the game's economy". The reward must be a developer product that would normally be sold for Robux in the shop (S14).
- S4's ban on simulated gambling still applies to earned currency. Do not let players stake earned coins on a spin that can return less than the stake or nothing. A free spin with only positive outcomes is fine.
- Not found: any Roblox page that names "daily spin" or "daily reward" explicitly. The rule above comes from the definitions.

## 6. Pay-to-win and stat items
- No Roblox policy bans selling stat-boosting items for Robux. There is no "pay-to-win" rule in the Community Standards (S4).
- The S4 phrase "exclusive features or other in-game enhancements" is in the off-platform sales rule: you may not sell them off-platform for money. It is not a ban on selling them in-game.
- S4 does prohibit misleading monetization: "Deceptive, sensational, duplicative, or otherwise misleading content or metadata", and "removing functionality for buyers without proper notice". If we later nerf a bought epic weapon, we must give notice.
- Constraints that still apply:
  - Any epic item from a wheel or box bought with Robux-bought currency falls under sections 1 to 3.
  - Directly selling a known epic item, with no randomness, is a normal developer product or game pass and is not a PRI.
  - "Stars" or stat tiers on a random reward count as outcomes and must appear in the odds list.
- Not found: any Marketplace rule on gameplay stats for in-experience items. Marketplace rules cover avatar items.

## 7. Developer products for buying currency
**Create.** Creator Hub > Monetization > Developer Products. Use a developer product for repeatable purchases (currency) and a game pass for one-time purchases.
- Price is 1 to 1,000,000,000 Robux (S10).
- The icon is at most 512x512, in .jpg, .png or .bmp.

**Prompt.** Call `MarketplaceService:PromptProductPurchase(player, productId)`. Do not grant on `PromptProductPurchaseFinished`, which the docs say is not for processing purchases (S10, S11).

**Grant.** Set `MarketplaceService.ProcessReceipt = function(receiptInfo) ... end`. Rules (S11):
- Set it once, in one server Script in ServerScriptService. It must handle every product.
- `receiptInfo` keys:
  - `PurchaseId`
  - `PlayerId`
  - `ProductId`
  - `PlaceIdWherePurchased`
  - `CurrencySpent`
  - `CurrencyType` (always Robux)
  - `ProductPurchaseChannel`, which is `Enum.ProductPurchaseChannel.AdReward` for rewarded-ad grants
- Return `Enum.ProductPurchaseDecision.PurchaseGranted` only after the grant is saved. Otherwise return `Enum.ProductPurchaseDecision.NotProcessedYet`.
- There is no timed retry. Roblox calls again when the player buys again or rejoins any server of the experience.
- Unresolved purchases are not refunded when escrow expires.
- Pending receipts arrive in a non-deterministic order.
- The same receipt can run on two servers at once if the player hops between servers.
- `PurchaseGranted` itself can fail to be recorded.
- With no callback set, receipts are auto-acknowledged and lost.

**Newer API.** `MarketplaceService:BindReceiptHandler` binds a handler per receipt type and product. It takes priority over ProcessReceipt, and unmatched receipts fall through to ProcessReceipt. A duplicate binding throws an error. Its receipt also carries `ReceiptType` and `TransferRequestId` (S11).
- I read the description of BindReceiptHandler. The exact signature line was in the part of the page that summarised poorly, so check it in the docs before using it.

**Idempotency, as the docs' own sample does it.** Keep a `PurchaseHistory` DataStore keyed by `PurchaseId`. In one `UpdateAsync` on that key, check whether it is already granted, then grant and record it. Add an in-memory set per server, and session-lock the player's profile for cross-server safety. Return PurchaseGranted only after the save succeeds. Roblox keeps no per-user purchase history for developer products (S10).

**Prices.**
- New items are enrolled in Managed Pricing (price optimization plus regional pricing) by default. Regional prices range from 30% to 100% of the default price (S13).
- Never hard-code a price in UI. Read it with `MarketplaceService:GetProductInfoAsync(id, Enum.InfoType.Product)` or `GetDeveloperProductsAsync`, on the client, so each player sees their own price (S10, S12, S13).
- `GetProductInfo` (without "Async") is deprecated (S11).
- If we ever add gifting or trading, use `MarketplaceService:GetUsersPriceLevelsAsync` (S13).

**Roblox Plus (replaced Premium for new players on 30 Apr 2026).**
- Subscribers get 10% off for their first two months, then 20% off. The discount covers developer products, game passes, developer subscriptions, paid-access games and avatar items. Items over 1,000,000 Robux are excluded.
- Roblox pays the discount, so creator earnings are unchanged. In S12's example, a 100-Robux item still pays the creator 70 Robux.
- No code is needed, but hard-coded prices will show Plus players the wrong price.
- Related APIs:
  - `Player.HasRobloxSubscription`
  - `MarketplaceService:PromptRobloxSubscriptionPurchase` (`PromptPremiumPurchase` is deprecated)
  - `MarketplaceService.PromptRobloxSubscriptionPurchaseFinished`
  - `MarketplaceService:GetRobloxSubscriptionDetailsAsync`

**Rewarded ads, if we use them.**
- `AdService:GetAdAvailabilityNowAsync`, whose result is an `Enum.AdAvailabilityResult` value: IsAvailable, PlayerIneligible, DeviceIneligible, PublisherIneligible or ExperienceIneligible.
- `AdService:CreateAdRewardFromDevProductId(devProductId)`
- `AdService:ShowRewardedVideoAdAsync(player, reward, placementId?)`
- The grant arrives through ProcessReceipt.
- Eligibility: the publisher must be 13 or over, ID-verified and using 2-step verification, and the game must be public with at least 2,000 unique visitors a month (S14).

## CHECKLIST FOR BUILDERS
1. Decide once: **can coins be bought with Robux?** If yes, every coin-paid wheel or box is a PRI and items 2 to 8 apply. If no, keep a hard rule that no developer product, pack or ad reward ever grants coins or spins, and enforce it in code review.
2. Show every outcome, tier and star level with its % odds before the buy button. The odds must sum to 100%. Use the rounding disclaimer when values are rounded. Put a long list behind a worded "Odds" or "Details" control, never an (i) alone. In Quiet UI, this can be a thin text line on the picture.
3. No "nothing" or loss outcome on any paid spin or box. Every slot gives a real item or currency.
4. Show luck or pity effects as numbers before purchase, and update the shown odds live while the effect is active. Odds must be per player when an outcome is once-only (for example, a weapon the player already owns).
5. On join, call `GetPolicyInfoForPlayerAsync` on the server inside `pcall`, and cache the result per player for the session. If `ArePaidRandomItemsRestricted` is true, hide the paid wheel and box purchase. Offer the free path, direct purchase of the specific item at its expected value, or a blocked button with a plain message. Enforce this on the server, not only in the UI. If the call fails, treat the player as restricted.
6. Trading: none planned. If we ever add it, gate it on `IsPaidItemTradingAllowed` for all paid items.
7. Questionnaire: on the release that adds paid spins, answer Yes to PRIs and Yes to respecting the API, then resubmit in the same session as the publish. Otherwise the game drops out for UK and Brazil minors.
8. Test in Studio Player Emulator with the policy flags set for the UK, Brazil, Belgium, Netherlands and Australia.
9. Free daily or earned spins are fine without disclosure, as long as they use earned-only tokens and have no losing slot. Show the odds anyway, for consistency.
10. Never offer a rewarded ad for a spin or a random item. An ad reward must be a fixed developer product.
11. Currency developer products:
    - one ProcessReceipt or BindReceiptHandler setup, in one server script;
    - grant once per `PurchaseId` via `UpdateAsync`, and save before returning `PurchaseGranted`;
    - return `NotProcessedYet` if the player has left or the save failed;
    - never grant on `PromptProductPurchaseFinished`.
12. Never hard-code Robux prices in UI. Read them with `GetProductInfoAsync` or `GetDeveloperProductsAsync` on the client, because Managed Pricing and the Plus discount change them per player.
13. Epic items may have better stats. That is allowed, but the item description must be accurate. If a bought item is weakened later, announce it in patch notes on the train board.
14. Stay Mild: wheel, box and reward art must have no gambling-style casino imagery. S6 says games with unplayable gambling content are available only to players 13 and over. Keep the wheel a plain prize wheel, with no slot machines, cards or chips.

## Could not verify
- The exact current text of the questionnaire, in Creator Hub's in-app form. I have only the question wording as quoted by S5 and S6.
- Whether S7's author is Roblox staff. The account has no staff flag, but the post is in Announcements.
- The exact Brazil dates in an official DevForum post. They come from S9 and secondary reposts.
- Any official word on: free or daily spins by name; mixed earned-or-bought currency; whether Plus or Premium perks that raise odds count as PRIs (asked in 2023 on the DevForum, no answer found).
- The exact signature line of `BindReceiptHandler`.
- Whether `AreAdsAllowed` gates rewarded video for viewers. The S14 page does not mention it.
- That no newer PolicyService PRI field will appear. S3 was read today; recheck it at build time.
