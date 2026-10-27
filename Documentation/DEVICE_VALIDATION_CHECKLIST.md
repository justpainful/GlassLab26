# Device Validation Checklist

Run on a physical iPhone and a physical iPad. The simulator cannot validate rendering or capture.

## Capture

- [ ] Validate Capture: System Screenshot passes (glass signal well above surround noise; pixel scale OK).
- [ ] Validate Capture: ReplayKit passes in portrait on iPhone; note the result in landscape.
- [ ] Validate Capture: View Snapshot result recorded (pass or fail is a finding, not a bug).
- [ ] Acquire "Regular Glass on 18% Gray" three times: surround residual near 0, frames settle.
- [ ] Acquire with an animated background: both frames show the same frozen phase.
- [ ] Decline the ReplayKit prompt once: the app reports the refusal and stores nothing.
- [ ] Deny Photos access: the screenshot method reports the reason.

## Rendering

- [ ] Regular vs Clear vs Identity on Black, White, Checkerboard look as expected by eye in Focus mode.
- [ ] Tint and Interactive change the sample; pressing interactive glass shows the system response.
- [ ] Group / container merging and splitting animate; morph and transitions work.
- [ ] UIKit glass surface and group match their SwiftUI counterparts in placement.
- [ ] Standalone UINavigationBar / UIToolbar / UITabBar render over the background.
- [ ] Every Explore demo opens and closes (navigation, tab bar minimise on scroll, sheets, popovers, menus).
- [ ] Local notification: permission prompt, banner in foreground, log entry.

## Analysis

- [ ] "Glass on Random Dots": blur sigma, displacement vectors and heatmaps appear; rejected share sensible.
- [ ] "Edge Refraction Calibration": ESF/LSF/MTF series appear.
- [ ] Solid backgrounds (Black, White, Gray) then Compare > transfer fit returns coefficients and residual.
- [ ] Repetitions = 5: repeatability shows CI and CV.
- [ ] Reconstruction with 3+ experiments: fit, sensitivity and leave-one-out complete; cancel works.

## Motion

- [ ] Record "Interactive Glass Press Test" with a press: touch-down/up events align with the optical-change rise.
- [ ] Record "Container Spacing Study": state-change markers and a step response appear.
- [ ] Frame viewer steps frame by frame; slow-motion playback works.

## Accessibility & environment

- [ ] Toggle Reduce Transparency, Increase Contrast, Reduce Motion, Bold Text, Larger Text in Settings; the
      Environment screen reflects each change and new experiments record it.
- [ ] Dark/Light via the Lab's appearance control affects SwiftUI and UIKit subjects.

## Sessions & export

- [ ] Export bundle; import it back: all files verified.
- [ ] Export CSV / JSON / PDF and open them on a computer.
- [ ] Kill the app during an acquisition; relaunch: the experiment is marked incomplete.
- [ ] Rotate the device and resize the iPad window: canvas, inspector and sidebar adapt.

## Performance

- [ ] Performance lab with 12, 40 and 80 elements: interval statistics and memory are reported; thermal state
      before/after is recorded.
