# IPA Installation

## Which artifact you have

| Artifact | Installable on a normal iPhone/iPad? |
|---|---|
| `GlassLab-ipa-development` / `GlassLab-ipa-ad-hoc` | Yes, on devices whose UDIDs are in the provisioning profile |
| `GlassLab-ipa-app-store-connect` | Through TestFlight / App Store Connect only |
| `GlassLab-UNSIGNED-ipa` | **No.** It must be signed first (see below) |

Download from the run page (Actions > Build iOS > run > Artifacts) or:

```bash
gh run download -R justpainful/GlassLab26 -n GlassLab-ipa-development
```

## Install a signed development / ad-hoc IPA

Any one of:

- **Xcode**: Window > Devices and Simulators > select the device > "+" under Installed Apps > choose the IPA.
- **Apple Configurator** (Mac): drag the IPA onto the device.
- **Command line** (Xcode 15+):

```bash
xcrun devicectl device install app --device <device-udid> GlassLab.ipa
```

On first launch of a development build, trust the developer in Settings > General > VPN & Device
Management, and enable Developer Mode (Settings > Privacy & Security) if iOS asks.

## Unsigned IPA

An unsigned IPA cannot be installed on a stock device. Either add the signing secrets
(BUILD_AND_SIGNING.md) and re-run the workflow, or build from source in Xcode with your own team:

```bash
xcodegen generate && open GlassLab.xcodeproj
```

## First run on the device

1. Experiment Lab > Validate Capture > run each method once (ReplayKit asks for screen recording consent;
   System Screenshot asks for Photos access).
2. Environment > fill the operator-entered fields that matter (True Tone, Night Shift, Liquid Glass setting).
3. Follow DEVICE_VALIDATION_CHECKLIST.md.
