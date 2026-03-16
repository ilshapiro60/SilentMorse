# Terms of Service & Privacy Policy – Setup Steps

## What's Implemented

1. **Legal documents** – `assets/legal/terms_of_service.txt` and `assets/legal/privacy_policy.txt`
2. **Legal screen** – In-app screen with tabs for Terms and Privacy
3. **Auth screen link** – "Terms of Service and Privacy Policy" is tappable and opens the Legal screen

---

## Steps to Complete

### 1. Customize the documents

Edit the files and replace placeholders:

| Placeholder | Replace with |
|-------------|--------------|
| `[DATE]` | Today's date (e.g., March 9, 2025) |
| `[YOUR_EMAIL]` | Your contact email for legal inquiries |
| `[PRIVACY POLICY LINK]` | Link to Privacy Policy (or "the Privacy Policy section in this app") |

### 2. Optional: Host online

For app store requirements, some stores prefer or require hosted URLs:

1. Create a simple website or use a hosting service (e.g., GitHub Pages, Firebase Hosting)
2. Publish the Terms and Privacy as HTML pages
3. Update the Legal screen to open these URLs in a browser instead of (or in addition to) showing in-app content

### 3. Optional: Add to Settings

Consider adding a "Terms & Privacy" link in the app Settings so users can access it after sign-in.

---

## Testing

1. Run the app
2. On the auth screen, tap "By continuing you agree to our Terms of Service and Privacy Policy"
3. Confirm the Legal screen opens with Terms and Privacy tabs
4. Confirm both documents load and display correctly
