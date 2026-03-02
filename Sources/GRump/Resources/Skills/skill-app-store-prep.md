---
name: App Store Prep
description: Prepare apps for App Store submission with review guidelines compliance and metadata optimization.
tags: [app-store, apple, ios, macos, distribution, review-guidelines]
---

# App Store Prep

You are an expert at preparing apps for App Store submission.

## Pre-Submission Checklist
- Verify all required app icons (1024x1024 for App Store, all device sizes).
- Ensure Info.plist has all required privacy usage descriptions.
- Test on all target devices and OS versions.
- Verify in-app purchases and subscriptions work in sandbox.
- Check that all URLs in the app are valid and accessible.
- Remove all debug/test code, print statements, and test accounts.
- Verify app works without network connectivity (graceful degradation).

## Review Guidelines Compliance
- No private API usage — check with nm and otool.
- All data collection must be disclosed in App Privacy section.
- Login must not be required for core functionality unless essential.
- Provide "Sign in with Apple" if offering third-party login.
- No references to other platforms (Android, Windows) in screenshots or descriptions.
- Ensure IDFA usage is declared if using ATT framework.

## Metadata Optimization
- App name: 30 chars max, include primary keyword.
- Subtitle: 30 chars max, complementary keyword.
- Keywords: 100 chars, comma-separated, no spaces after commas.
- Description: Lead with the strongest value proposition.
- Screenshots: Show actual app UI, not marketing graphics.
- Preview video: 15-30 seconds, show core functionality.

## Privacy Manifest
- Include PrivacyInfo.xcprivacy with all required API declarations.
- Declare all tracking domains and data collection categories.
- Ensure third-party SDKs include their own privacy manifests.

## Anti-Patterns
- Submitting without testing on the oldest supported OS version
- Leaving test/debug endpoints or analytics keys in release builds
- Ignoring App Store Review Guidelines updates between submissions
- Using undocumented APIs that pass review once but get rejected on updates
- Screenshots that don't match the actual app UI

## Verification
- App runs correctly on all target device sizes and OS versions
- All privacy descriptions are present and accurate in Info.plist
- `nm` and `otool` show no private API usage
- Privacy report from Xcode shows no undeclared API usage
- In-app purchases work correctly in sandbox environment
