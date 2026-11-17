# Votre Air: Breath Hygiene & App Guide

Welcome to your Votre Air guide. This document explains how to use your pendant with the iOS app, what each message on screen means during a test, and how every breath result connects to everyday hygiene.

## 1. Quick Start Guide

### Step 1: Wake & Connect

* Turn on your Votre Air pendant and open the companion app on your iPhone.
* Keep the pendant close by; it pairs automatically over Bluetooth.
* If the pendant has just powered on, it will take a brief moment to check the room air before it lets you start. Keep it resting in open room air during this time.

### Step 2: Begin the Breath Check

* When the app shows that the pendant is ready, tap **Start Breath Test**.
* The app will tell the pendant to prepare for your breath.

### Step 3: Blow into the Intake Port

* When the app prompts you to blow, hold the bottom opening of the pendant about an inch from your lips.
* Exhale a smooth, continuous breath directly into the opening for 3 to 5 seconds.

### Step 4: Step Back for Analysis

* As soon as you finish exhaling, move the pendant away from your breath and let it sit in clean air.
* The pendant immediately checks how quickly your breath naturally clears away.

### Step 5: Review Your Results

* Once analysis finishes, your hygiene result card appears on screen with clear daily tips.

## 2. What the Screen Messages Mean

As you take a test, the app and pendant communicate to guide you through each stage. Here is what you will see on screen and what the system is doing behind the scenes:

| What You See on Screen | App / System State | What It Means & What to Do |
| ----- | ----- | ----- |
| **"Pendant Stabilizing..."** / **"Waking up the pendant and warming it up..."** | `COLD_BOOT_WARMING_UP` (`.coldBootWarmup`) | The sensor is completing its initial warm-up and establishing a clean room baseline. Keep the pendant in fresh room air until it finishes. |
| **"Pendant is Ready."** | `WARMUP_COMPLETE` (`.idle`) | The sensor has locked in clean room air and is ready. Tap the test button when you are ready to exhale. |
| **"Waking up... Please wait..."** | `.warmingUp` | The app is actively preparing the pendant's sensor to capture an exhalation. |
| **"Blow at the bottom of the pendant now..."** | `READY_PLEASE_BLOW` (`.blowNow`) | The test window is open. Exhale a steady, gentle breath directly into the bottom port. |
| **"Good Job! Breath is captured."** | `TESTING_SENSING_BREATH` (`.processing`) | The sensor registered your breath plume. Continue blowing smoothly until you finish. |
| **"Analyzing the sample..."** | `RECOVERING_CALCULATING_T50` (`.processing`) | Exhalation is complete. Step back and hold the pendant in clean room air so it can evaluate how your breath clears. |
| **"Breath Odor Analysis Completed"** | `BREATH_TEST_COMPLETE` (`.completed`) | Calculations are complete. Your hygiene result card is ready on the dashboard. |

## 3. Helpful Prompts & Retest Messages

If a breath sample cannot be evaluated accurately, the app will explain why so you can easily try again:

* **"Please try blow at the bottom of the pendant a little harder. No breath was captured."**  
  *Internal Code:* `EXHALATION_TOO_WEAK`  
  *What it means:* The breath was too gentle, angled away from the opening, or too short. Tap to start again, position the pendant about an inch from your lips, and exhale with a steady, direct stream.

* **"No Breath is detected."**  
  *Internal Code:* `TIMEOUT`  
  *What it means:* The test window was open, but no exhalation reached the pendant before the timer expired. Tap Start again when you are ready to blow right away.

* **"The pendant needs a little time, please try again shortly."**  
  *Internal Code:* `TRY_AGAIN_LATER`  
  *What it means:* The sensor needs a short pause to clear residual moisture or reset its baseline before taking another sample. Give it a few seconds until the screen returns to ready.

* **"Action Cancelled."**  
  *What it means:* The test was manually stopped. The pendant safely returns to its energy-saving resting state.

## 4. Understanding Your Results

Your breath reading is evaluated using two natural factors:

1. **The initial impact:** How much your breath differs from the surrounding room air.
2. **The clearing rate:** How quickly the breath clears away from the sensor. Food, drink, and mints clear away quickly, while everyday oral odor buildup clings around longer.

Here is the complete breakdown of every result title and description shown in the app:

### Fresh & Balanced Breath
* **App Code:** `BALANCED_BREATH` (`.balancedBreath`)
* **Screen Title:** *Fresh & Balanced Breath*
* **Screen Message:**
  > *"Your breath feels clean, fresh, and perfectly balanced! You're good to go."*
* **What it means:**  
  Your breath cleared cleanly with virtually no lingering odor notes. Your current daily hygiene routine is working effectively.

### Delicate Flavor Notes
* **App Code:** `SETTLE_BREATH` (`.settleBreath`)
* **Screen Title:** *Delicate Flavor Notes*
* **Screen Message:**
  > *"There may just be a delicate hint of recent food or drink on your breath—it's very subtle and nothing to worry about at all."*
* **What it means:**  
  A very light, fast-clearing trace was detected from a recent drink, snack, or mint. It is subtle and requires no special action.

### Settling Food Scents
* **App Code:** `SETTLE_BEVERAGE_FOOD_ODOR` (`.settleBeverageFoodOdor`)
* **Screen Title:** *Settling Food Scents*
* **Screen Message:**
  > *"A few gentle notes from recent food or drinks may still be lingering. A soft rinse or quick brush could help clear them away comfortably."*
* **What it means:**  
  Mild flavors from a recent meal or beverage are starting to settle in your mouth. A quick water rinse or light brushing will comfortably clear them away.

### Lingering Food & Drink Scents
* **App Code:** `SOME_BEVERAGE_FOOD_ODOR` (`.someBeverageFoodOdor`)
* **Screen Title:** *Lingering Food & Drink Scents*
* **Screen Message:**
  > *"You may notice some lingering flavors from recent food or drinks. A gentle brush or quick rinse could be a great way to refresh your breath."*
* **What it means:**  
  Noticeable flavors from food, tea, coffee, or snacks are present. Because these clear quickly once rinsed, drinking water or taking a quick brush will freshen your breath right up.

### A Little Hydration Could Help
* **App Code:** `DRY_MOUTH_HYDRATE` (`.dryMouthHydrate`)
* **Screen Title:** *A Little Hydration Could Help*
* **Screen Message:**
  > *"Your mouth may feel a little dry right now. Enjoying a glass of water could be a wonderful way to refresh and hydrate."*
* **What it means:**  
  Your mouth is on the drier side, which is natural after long conversations, working, or exercising. A glass of water is the best way to rebalance your oral moisture.

### A Bit Dry Right Now
* **App Code:** `DRY_MOUTH_VSC_BUILDUP` (`.dryMouthVscBuildup`)
* **Screen Title:** *A Bit Dry Right Now*
* **Screen Message:**
  > *"Dryness can sometimes make breath odors linger a bit longer. Sipping water or taking a quick mouth rinse can help wash away buildup and keep your breath fresh."*
* **What it means:**  
  Lower moisture levels have allowed everyday breath scents to concentrate and hang around longer. Sipping water and swishing with a mouth rinse will wash away buildup and restore freshness.

### Time for a Quick Refresh
* **App Code:** `NOTICEABLE_MALODOR` (`.noticeableMalodor`)
* **Screen Title:** *Time for a Quick Refresh*
* **Screen Message:**
  > *"Your breath could benefit from a quick refresh right now. A gentle brush, floss, or rinse may help bring back your natural balance."*
* **What it means:**  
  Natural breath odors have accumulated and are lingering rather than clearing rapidly. A quick refresh—brushing, flossing, or using an oral rinse—will easily restore balance.

### A Little Extra Care May Help
* **App Code:** `STRONG_MALODOR` (`.strongMalodor`)
* **Screen Title:** *A Little Extra Care May Help*
* **Screen Message:**
  > *"Your breath may need a little extra care today. Cleaning your tongue, along with brushing, flossing, or rinsing, can help bring back a fresh feel. If this continues for a few days despite your usual routine, speaking with a dentist can offer extra guidance."*
* **What it means:**  
  Stronger, slower-clearing odor compounds were detected. Taking time for a complete oral hygiene routine—especially gently sweeping the back of the tongue and cleaning between teeth—will help bring back lasting freshness.

### No Reading Detected
* **App Code:** `INVALID_EXHALATION` / `NONE` (`.invalidExhalation`, `.none`)
* **Screen Title:** *No Reading Detected*
* **Screen Message:**
  > *"We couldn't quite catch a breath sample. Taking a slow, deep breath and blowing steadily may help us get a clear reading."*
* **What it means:**  
  The sample was interrupted or did not deliver an even stream of breath. Wait for the pendant to return to **Ready**, take a steady breath, and blow smoothly into the bottom port.