# OAK-D Point Cloud Tuner Handoff

## Goal

This demo exists to make a fast standalone test bed for OAK-D point-cloud quality before pushing anything back into the full Godot/webstack pipeline.

The target workflow is:

1. Run one standalone Python demo.
2. See the default OAK-D point cloud live in real time.
3. Switch freely, while the app is still open, between:
   - Default DepthAI/OAK-D stereo point cloud.
   - Fast-FoundationStereo point cloud.
   - Full NVIDIA FoundationStereo point cloud.
4. Compare those three clouds visually from the same camera pose and same scene.
5. Eventually make the NVIDIA model modes actually live, not one frozen frame every several seconds.

The default OAK-D point cloud is already real-time. The broken part is the NVIDIA model path: right now it is snapshot/subprocess/file based, so it feels like "one frame per several seconds" even on strong hardware.

## Main Files

- `experiments/oakd_head_tracker_demo/oakd_pointcloud_tuner.py`
  - Main standalone tuner. No Godot, no webstack.
  - Captures OAK-D stereo/RGB, renders the live default cloud, and triggers FoundationStereo comparison runs.

- `experiments/oakd_head_tracker_demo/external/Fast-FoundationStereo/`
  - External Fast-FoundationStereo checkout.
  - Used by `f` and `g` in the tuner.

- `experiments/oakd_head_tracker_demo/external/FoundationStereo/`
  - External NVIDIA FoundationStereo checkout.
  - `scripts/run_demo_tensorrt.py` has local patches to support ONNX runtime, OAK-D intrinsics, one-shot runs, and Windows CUDA provider loading.

- `experiments/oakd_head_tracker_demo/deployable_foundationstereo_small_576x960_v2.0.onnx`
  - Full/non-fast FoundationStereo ONNX model currently wired as the default full model.

- `experiments/oakd_head_tracker_demo/foundation_stereo_runs/`
  - Per-run outputs and logs from Fast/FoundationStereo snapshots.
  - If the model path fails, check the newest `run.log` here.

## Current Launch Command

From repo root:

```powershell
python experiments\oakd_head_tracker_demo\oakd_pointcloud_tuner.py --preset smooth
```

Known device-level presets:

```text
smooth
speed_raw
balanced
dense
clean
fast
```

The default preset is `smooth`.

## Current Controls

Inside the tuner window:

- `q` or `Esc`: quit.
- `p`: cycle runtime cleanup presets.
- `a`: capture a comparison snapshot.
- `f`: run one Fast-FoundationStereo snapshot.
- `g`: toggle Fast-FoundationStereo refresh/live-ish mode.
- `Shift+F`: run one full NVIDIA FoundationStereo snapshot using the ONNX model.
- `o`: toggle the last FoundationStereo cloud view.
- `l`: return to live OAK-D view.
- `r`: reset camera/view.

Important: `g` is not true live inference yet. It repeatedly starts snapshot-style Fast-FoundationStereo runs. That is the root of the slow/awkward behavior.

## Verified Environment State

This machine has an RTX 4090 and CUDA PyTorch works:

```text
torch 2.5.1+cu121
CUDA available: true
GPU: NVIDIA GeForce RTX 4090
```

`onnxruntime-gpu==1.21.0` was installed and the full FoundationStereo ONNX model can create a CUDA session:

```text
providers ['CUDAExecutionProvider', 'CPUExecutionProvider']
```

There are many ONNX Runtime `ScatterND` warnings during session creation. They are noisy but did not prevent CUDA provider loading.

Important Windows detail: in `run_demo_tensorrt.py`, `torch` must be imported before `onnxruntime`. That lets ONNX Runtime find CUDA/cuDNN DLLs from the PyTorch wheel. Without that, ORT may fail provider loading or fall back to CPU.

## Current Status

Working:

- OAK-D default live point cloud.
- Runtime cleanup/preset controls in the tuner.
- Fast-FoundationStereo snapshot execution.
- Full FoundationStereo ONNX model path is wired.
- Full FoundationStereo ONNX model loads on CUDA with the RTX 4090.
- FoundationStereo outputs are loaded back into the tuner as point clouds.
- The loaded FoundationStereo cloud is colorized from the latest OAK-D color frame.

Not working well enough:

- Fast/FoundationStereo modes are not truly live.
- `g` only approximates live mode by repeatedly launching separate snapshot runs.
- Full FoundationStereo is still snapshot-only.
- Model output quality/comparison may look similar or confusing if the same stale snapshot is being displayed.
- The current architecture pays a huge overhead for disk I/O, subprocess startup, model reload, image encoding/decoding, and PLY loading.

## Why The NVIDIA Modes Are Slow

The current implementation is a useful proof of plumbing, not the final architecture.

Current NVIDIA path roughly does this:

1. Capture a stereo pair from OAK-D.
2. Write left/right images to disk.
3. Launch an external Python subprocess.
4. That subprocess imports heavy ML libraries.
5. It loads or initializes the model.
6. It runs inference.
7. It writes image/cloud output to disk.
8. The tuner polls/loads that output back from disk.
9. The tuner renders the point cloud.

Even with a 4090, that workflow can be slow because most of the cost is not GPU math. It is process startup, Python import time, model initialization, file I/O, and format conversion.

The default OAK-D point cloud is fast because it is already a persistent stream: frames come directly from DepthAI queues into the viewer.

## What Needs To Change For Real Live FoundationStereo

The next chat should focus on turning FoundationStereo from a command-line snapshot tool into a persistent live inference backend.

Recommended path:

1. Keep `oakd_pointcloud_tuner.py` as the UI/test harness.
2. Create a persistent FoundationStereo worker object/process.
3. Load the model exactly once at startup or first use.
4. Keep the model resident on the GPU.
5. Feed rectified OAK-D left/right frames directly from memory.
6. Return disparity/depth directly in memory.
7. Build the point cloud in memory.
8. Render that cloud in the same viewer without writing PNG/PLY files per frame.

The biggest win is eliminating:

- Per-frame subprocess launch.
- Per-frame model reload.
- Per-frame image writes.
- Per-frame PLY writes and reads.

## Suggested Implementation Plan

### Phase 1: Persistent Fast-FoundationStereo Worker

Start with Fast-FoundationStereo because it is intended to be faster.

Make a `FastFoundationLiveWorker` that:

- Starts once.
- Loads the Fast-FoundationStereo model once.
- Accepts the latest rectified left/right frames through a queue.
- Drops stale frames when inference is behind.
- Emits the newest disparity/cloud result.

Use a bounded queue of size 1 or 2. For live preview, low latency matters more than processing every frame.

Expected behavior:

- Default OAK-D keeps rendering continuously.
- Press `g` to switch to the latest Fast-FoundationStereo result stream.
- If inference runs at 5 FPS, the UI still stays interactive and always shows the newest completed result.

### Phase 2: Persistent Full FoundationStereo ONNX Worker

For the ONNX model:

- Keep one `onnxruntime.InferenceSession` alive.
- Use `CUDAExecutionProvider`.
- Import `torch` before `onnxruntime` on Windows.
- Feed tensors directly from NumPy arrays.
- Avoid writing images to disk.
- Avoid reading PLY output.

Better later:

- Use ONNX Runtime I/O binding to keep inputs/outputs GPU-side where possible.
- Consider TensorRT engine build only after ONNX live mode works.

The full ONNX model currently expects:

```text
left_image  [1, 3, 576, 960]
right_image [1, 3, 576, 960]
disparity   [1, 1, 576, 960]
```

### Phase 3: Shared Cloud Renderer For All Three Modes

Make all three modes produce the same internal representation:

```python
points_xyz: float32 array, shape [N, 3]
colors_bgr_or_rgb: uint8 or float32 array, shape [N, 3]
label: string
timestamp: float
```

Then the renderer does not care whether the cloud came from:

- DepthAI default stereo.
- Fast-FoundationStereo.
- Full FoundationStereo.

This will make toggling/comparison much cleaner.

### Phase 4: True Three-Way Compare

Add an explicit mode enum:

```text
oakd_default
fast_foundation
full_foundation
```

Then bind keys:

- `1`: live OAK-D default.
- `2`: live Fast-FoundationStereo.
- `3`: live full FoundationStereo.
- `Tab`: cycle active cloud.
- `Space`: freeze/unfreeze the current comparison frame.

The goal is to switch views instantly without restarting capture or rerunning setup.

## DepthAI/OAK-D Notes

The OAK-D default point cloud quality depends heavily on the scene. Plain white walls can produce poor stereo matches because passive stereo needs visual texture. RealSense looks better in many indoor cases because the D455 has an IR projector/active stereo aid.

Useful OAK-D settings already explored:

- Speckle filtering can improve noisy floaters.
- RGB-depth alignment matters. Misalignment can make colors look pasted onto the wrong depth.
- Some DepthAI settings require pipeline restart. Trying to change unsupported settings live can crash the DepthAI process.

Avoid rebuilding/restarting the OAK-D pipeline for simple runtime cleanup sliders. For device-level changes, restart deliberately.

## Known Crash/Risk Areas

DepthAI has crashed during pipeline shutdown/restart after changing settings mid-run. The stack involved `depthai`, `PipelineImpl::stop`, `DeviceBase::close`, and point cloud RGB data. Treat device-level setting changes as restart-only until proven safe.

Do not switch `StereoDepth.setDepthAlign` at runtime while aligning to a specific camera. DepthAI printed:

```text
Switching depthAlign mode at runtime is not supported while aligning to a specific camera is enabled
```

## Important Quality Notes

If FoundationStereo appears black and white, that is likely because the stereo inputs are mono left/right images. The rendered comparison cloud can still be colorized using the OAK-D RGB frame, but this needs correct calibration/projection. Do not assume FoundationStereo itself outputs color.

If the FoundationStereo output looks identical to the default cloud, verify:

- The mode label at the bottom of the tuner.
- The latest `foundation_stereo_runs/*/run.log`.
- Whether the display is showing a stale cached Foundation cloud.
- Whether `o` is toggling the Foundation view or the live OAK-D view.

## Useful Verification Commands

Compile check:

```powershell
python -m py_compile experiments\oakd_head_tracker_demo\oakd_pointcloud_tuner.py experiments\oakd_head_tracker_demo\external\FoundationStereo\scripts\run_demo_tensorrt.py
```

Check CUDA/ONNX Runtime provider:

```powershell
python -c "import torch; import onnxruntime as ort; p=r'experiments\oakd_head_tracker_demo\deployable_foundationstereo_small_576x960_v2.0.onnx'; s=ort.InferenceSession(p, providers=['CUDAExecutionProvider','CPUExecutionProvider']); print('providers', s.get_providers()); print('device', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'no cuda')"
```

Expected:

```text
providers ['CUDAExecutionProvider', 'CPUExecutionProvider']
device NVIDIA GeForce RTX 4090
```

## Suggested First Task For New Chat

Start by replacing the snapshot/subprocess FoundationStereo path with a persistent in-process or persistent-worker Fast-FoundationStereo live path.

Do not begin by tuning visual filters. The fundamental blocker is architecture: the model path must stop launching subprocesses and writing/reading files per frame.

Once Fast-FoundationStereo is truly live, repeat the same pattern for the full ONNX model using a persistent `onnxruntime.InferenceSession` on `CUDAExecutionProvider`.

