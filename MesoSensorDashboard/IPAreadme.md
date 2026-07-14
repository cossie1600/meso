# MesoSensorDashboard Beta Testing Guide

Welcome to the beta test for MesoSensorDashboard! Because this is an early-stage app distributed outside the official Apple App Store, Apple's iOS security require you to manually sign the app package onto your device hardware via a computer using a process called **sideloading**. 

Follow these steps to install the app on your iPhone.

---

## Prerequisites (For the Tester)
1. An iPhone and a lightning/USB-C cable.
2. A Mac or Windows PC.
3. Your personal Apple ID credentials (used strictly to generate a local security certificate for your own hardware).

---

## Step 1: Download the Sideloading Tool
1. On your computer, download the free tool **Sideloadly** from the official site: `https://sideloadly.io/`
2. Install and launch the application.
   * *Mac Users Note:* If macOS displays a message saying it cannot verify the developer, go to your Mac's **System Settings > Privacy & Security**, scroll down to the **Security** header, and click **Open Anyway**.

## Step 2: Install the App
1. Connect your iPhone to your computer using the USB cable.
2. If your phone asks to **Trust This Computer**, tap **Trust** and enter your passcode.
3. Open Sideloadly. You should see your iPhone listed under the **Device** selector at the top.
4. Drag the `MesoSensorDashboard.ipa` file sent to you directly into the large **IPA icon square** inside Sideloadly.
5. In the **Apple Account** input box, type in your regular Apple ID email address.
6. Click **Start**. If prompted, enter your Apple ID password to confirm the security signature framework.
7. Wait until the progress log bar at the bottom reads **Success!**. The app icon will now appear on your iPhone's home screen.

## Step 3: Enable Developer Settings (Crucial)
iOS will prevent you from tapping the app open until you explicitly trust your own signature profile:

1. On your iPhone, open **Settings > Privacy & Security**.
2. Scroll all the way to the bottom and select **Developer Mode**.
3. Toggle Developer Mode **ON** and allow the iPhone to restart.
4. After the phone reboots and you unlock it, tap **Turn On** on the system confirmation popup.
5. Finally, open iPhone **Settings > General > VPN & Device Management**.
6. Tap on your Apple ID email address under Developer App and choose **Trust**.

🎉 **You're all set!** Open MesoSensorDashboard from your home screen and begin testing.

---

### ⏳ The 7-Day Limit Note
Because this app is compiled through a free development framework, Apple automatically expires the local security license after **7 days**. After a week, the app will instantly crash when opened. 

To fix this, simply plug your iPhone back into your computer, open Sideloadly, and click **Start** again. Your app layout, configuration, and data will remain intact, and it will give you another 7 days of runtime.
