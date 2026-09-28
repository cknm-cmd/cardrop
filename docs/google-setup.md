# Setting up Google Drive for cardrop

cardrop uploads through [rclone](https://rclone.org). rclone's built-in shared Google client is
being retired, and it's heavily rate-limited anyway, so you create your **own** OAuth client. It's
free, takes about 10 minutes, and only has to be done once.

> The Google account that **owns** the OAuth client and the account whose **Drive receives the
> files** can be different. The client only identifies the app.

## 1. Create a Google Cloud project

1. Go to <https://console.cloud.google.com/>.
2. Open the project picker (top left), click **New project**, give it a name (e.g. `cardrop`), and click **Create**.
3. Make sure the new project is selected.

## 2. Enable the Google Drive API

Open <https://console.cloud.google.com/apis/library/drive.googleapis.com> and click **Enable**.

## 3. Configure the consent screen

Go to **Google Auth Platform**: <https://console.cloud.google.com/auth/overview>, then click **Get started**.

- **App name:** anything that doesn't contain or imitate a Google brand. Google rejects names with
  "Google", "Drive", "Gmail" and so on. For example: `My Camera Uploader`.
- **Support email:** your email.
- **Audience:** **External**.
- **Contact email:** your email. Agree to the policy, then click **Create**.

## 4. Create the OAuth client

1. Go to **Clients**, then **Create client**.
2. **Application type:** **Desktop app**. Name it anything, then click **Create**.
3. Click **Download JSON**. Keep this file private, and **don't commit it to git**.

## 5. Avoid weekly sign-outs: publish the app

While the app is in **Testing**, only listed test users can sign in, and Google **expires the
sign-in after 7 days**. That quietly breaks unattended uploads. Publishing fixes both:

1. Google requires a **homepage URL** and a **privacy policy URL** before publishing. For a
   personal app, a free [GitHub Pages](https://pages.github.com/) site with two short pages is
   enough. The privacy policy should say what data the app accesses (your Drive files), that it's
   processed only on your Mac, and that it's not shared.
2. Under **Branding**, fill in both URLs and add the site's domain (e.g. `yourname.github.io`)
   under **Authorised domains**, then click **Save**.
3. Under **Audience**, click **Publish app**, then confirm **In production**.

You don't need to submit for Google's verification for personal use. You'll just see a
"Google hasn't verified this app" warning when you sign in. Click **Continue**.

> **Prefer to skip this step?** Under **Audience → Test users**, add the Google account whose
> Drive will receive the files. You'll need to reconnect every 7 days with
> `cardrop connect gdrive`.

## 6. Connect cardrop

```bash
cardrop connect gdrive ~/Downloads/client_secret_XXXX.json
```

A browser window opens. Pick the Google account whose Drive should receive the files, click
**Continue** on the unverified-app warning, and **Allow**. Then use destinations like
`gdrive:Camera uploads` in `cardrop config`.
