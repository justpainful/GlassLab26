# Data Formats

## On-device storage

```
Application Support/GlassLab/
  Sessions/<session-uuid>/
    session.json          ExperimentSession (pretty-printed, sorted keys, ISO-8601 dates, NaN/inf as strings)
    frames/*.png          captured frames: original pixels, embedded color profile
    derived/*.png         heatmaps, vector fields, difference images
    recordings/*.mov      HEVC or ProRes 4444 screen recordings
  Backgrounds/            imported background images and videos
  presets.json            user presets (SceneConfiguration[])
  matrices.json           test matrix plans and case status
```

`session.json` is written atomically after every change.

## Records (abridged)

**ExperimentSession**: id, title, createdAt, modifiedAt, environment (EnvironmentSnapshot), experiments,
notes, tags, crossAnalyses (AnalysisRun[]), schemaVersion.

**Experiment**: id, createdAt, configuration (SceneConfiguration), environment, referenceFrames, resultFrames
(FrameRecord[]), recordings (RecordingRecord[]), events (InteractionEvent[]), analyses (AnalysisRun[]),
canvasSizePoints, subjectFramePoints, elementFramesPoints, repetitionIndex, notes, validity, matrixCaseID.

**FrameRecord**: fileName, role, pixelWidth/Height, pixelsPerPoint, colorSpace, captureMethod, mediaTime,
capturedAt, sha256, cropInSource, pipelineNotes, settleResidual, settleMilliseconds.

**RecordingRecord**: fileName, codec, isLossless (always false today), pixel size, pixelsPerPoint,
nominalFrameRate, frameCount, startMediaTime, duration, frameTimes (host clock, seconds), crop, colorSpace,
pipelineNotes, sha256.

**AnalysisRun**: startedAt, finishedAt, appVersion, algorithmVersions, measurements, derivedFrames, log, validity.

**Measurement**: see MEASUREMENT_VALIDATION.md.

Original frames are never rewritten. Re-analysis appends a new AnalysisRun with the current algorithm
versions, so results from different app versions can be compared.

## Export bundle (`*.glasslab.zip`)

ZIP with STORED entries (no compression; PNG/HEVC are already compressed):

```
manifest.json      format, formatVersion, createdAt, app version/build, session id/title,
                   algorithmVersions, files[] { path, bytes, sha256 }
session.json
measurements.csv   one row per measurement (header below)
series.csv         one row per series point: experiment_id, measurement, series, x, x_unit, y, y_unit
report.pdf         research report
frames/ derived/ recordings/
```

`measurements.csv` columns: session, experiment_id, experiment, analysis_started, measurement, value, unit,
provenance, confidence, confidence_reason, uncertainty, uncertainty_kind, sample_count, validity,
validity_reasons, algorithm, algorithm_version, region_px, device, os, app_version, sources, notes.
Missing values are `N/A`.

Import (Sessions > Import) extracts to a temporary folder, verifies each entry's CRC-32 and every manifest
file's size and SHA-256, and only then adds the session (as a copy if the id already exists).

## Other exports

Measurements CSV, session JSON, PDF report, individual frames as PNG (original file) or HEIC (re-encoded,
lossy, quality 1.0).
