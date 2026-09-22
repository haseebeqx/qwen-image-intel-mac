# qwen-image-intel-mac

A small, reproducible CLI for running **Qwen-Image 2.1** on an Intel Mac with a discrete AMD GPU, across 4 GB, 8 GB, 16 GB, and 32 GB VRAM configurations. It uses upstream [`stable-diffusion.cpp`](https://github.com/leejet/stable-diffusion.cpp), GGUF weights, Metal, and segmented weight streaming. There is no GUI and no Python runtime.

Its low-memory design is based on upstream facilities:

- Q2_K diffusion weights (2.56 GB)
- Q4_K_M Qwen3-VL text encoder (5.03 GB)
- text encoding and VAE decode on CPU
- diffusion on the AMD Metal device
- model weights retained in system RAM and streamed within an automatically sized VRAM budget
- Flash Attention and automatic graph segmentation
- Metal concurrency disabled for stability on discrete AMD GPUs

The complete text-to-image download is about **8.3 GB**. Expect generation to be slow; this is an enablement project for constrained hardware, not a claim that a 4 GB 5300M performs like a modern CUDA GPU.

Validated on a 2019 16-inch MacBook Pro (Core i7, 16 GB RAM, Radeon Pro 5300M 4 GB). A cold 256×256 one-step smoke test completed end-to-end in 62.5 seconds, including text encoding, first-time Metal pipeline compilation, denoising, CPU VAE decode, and PNG save. Normal 20-step generations take considerably longer. Intel Macs with 8 GB, 16 GB, or 32 GB of AMD VRAM are also supported; the wrapper detects the card's actual capacity and raises its managed Metal budget while reserving 1 GiB for the display server and workspace.

## Requirements

- Intel Mac, macOS 14 or newer
- AMD GPU with Metal support and 4–32 GB VRAM
- 16 GB system RAM (close other memory-heavy applications)
- about 20 GB free disk space for sources, build products, and model files
- Xcode Command Line Tools, CMake, Git, and curl

The model is governed by the [Qwen Research License Agreement](https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE). Read it before downloading.

## Install

Review the [Qwen Research License Agreement](https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE), then install from the web:

```bash
curl -fsSL https://raw.githubusercontent.com/haseebeqx/qwen-image-intel-mac/main/web-install.sh \
  | bash -s -- --accept-license
```

The web installer clones the project to `~/.local/share/qwen-image-intel-mac`, checks the host, builds the pinned engine, downloads the models, and links `qwen-image` into `~/.local/bin`. Add that directory to `PATH` if the installer asks you to. Downloads resume if interrupted.

If you prefer to inspect scripts before running them, clone the repository and run:

```bash
git clone https://github.com/haseebeqx/qwen-image-intel-mac.git
cd qwen-image-intel-mac
./install.sh --accept-license
```

To choose another command directory, or to install without downloading the models:

```bash
./install.sh --accept-license --bin-dir /usr/local/bin
./install.sh --skip-models
```

The second form is useful when model files are managed separately. Set `QWEN_MODEL_DIR` when running the command, or pass `--model-dir`.

### Manual setup

```bash
./scripts/doctor.sh
./scripts/build.sh
./scripts/download-models.sh --accept-license
```

The default text-to-image set does not include the vision projector needed for image editing.

## Generate

```bash
qwen-image "A studio photograph of a tiny robot holding a sign that says 'HELLO MAC'" \
  --output outputs/robot.png
```

Conservative defaults are 512×512, 20 Euler steps, CFG 6, seed 42, and an automatically sized Metal budget. The wrapper reserves 1 GiB of detected AMD VRAM, producing budgets of 3, 7, 15, and 31 GiB on 4, 8, 16, and 32 GB cards respectively. It calculates this from the reported capacity rather than using a fixed list, and falls back to 3 GiB if detection fails. Width and height must be multiples of 32.

```bash
qwen-image "A watercolor lighthouse in a storm" \
  --width 768 --height 512 --steps 30 --seed 123 \
  --output outputs/lighthouse.png
```

Higher resolutions need substantially more workspace and may be much slower. Start at 512×512.

### Faster previews

The quality-first defaults are intentionally expensive on a 4 GB Radeon. Use the speed-first profile while iterating on prompts:

```bash
qwen-image "A watercolor lighthouse in a storm" --fast \
  --output outputs/preview.png
```

`--fast` uses 256×256 and 12 steps while retaining CFG 6. It does not use EasyCache. The previous 8-step, CFG-1 cached profile skipped too much denoising and could produce unfinished images; the lower resolution still makes this profile substantially faster than the 512×512 default. It trades resolution and detail for speed, but preserves the model's normal guidance path. Any explicit `--width`, `--height`, `--steps`, or `--cfg` value overrides that part of the profile, regardless of option order.

For a higher-resolution draft, for example:

```bash
qwen-image "A watercolor lighthouse in a storm" --fast \
  --width 384 --height 384 --steps 16 --output outputs/draft.png
```

EasyCache remains available as a raw engine option after `--`, but is not recommended at low step counts.

Each invocation reloads roughly 7.4 GB of model parameters, so even a fast generation has a fixed cold-start cost. The first Metal run also compiles GPU pipelines. Keep `QWEN_DISK_PARAMS` unset unless memory pressure requires it: disk-backed parameters are substantially slower.

### Useful options

```text
--width N          output width (default 512)
--height N         output height (default 512)
--steps N          denoising steps (default 20)
--seed N           seed (default 42)
--cfg N            CFG scale (default 6.0)
--vram N           managed Metal budget in GiB (default auto: GPU VRAM minus 1 GiB)
--threads N        CPU worker threads (default physical core count)
--output PATH      PNG output path
--model-dir PATH   model directory (default ./models)
--fast             256px, 12-step, CFG-6 preview profile
--cpu              diagnostic CPU-only mode
--dry-run          validate and print the engine command
--                 pass remaining arguments directly to sd-cli
```

Environment variables with the same purpose are also accepted: `QWEN_MODEL_DIR`, `QWEN_VRAM_GIB`, `QWEN_THREADS`, and `QWEN_METAL_DEVICE` (default `MTL0`). Set `QWEN_VRAM_GIB` or use `--vram` to override automatic sizing.

## Image editing (experimental)

Download the extra 0.75 GB vision projector:

```bash
./scripts/download-models.sh --accept-license --editing
qwen-image "Replace the text on the sign with 'INTEL MAC'" \
  --reference input.png --output outputs/edit.png
```

Repeat `--reference` for up to ten images. Editing requires more RAM and has not been validated as thoroughly as text-to-image generation on this machine.

## Memory profiles

The default keeps source weights in RAM, which avoids rereading the diffusion model every step. If memory pressure kills the process, use disk-backed diffusion parameters at a large speed cost:

```bash
QWEN_DISK_PARAMS=1 qwen-image "prompt" --output outputs/low-ram.png
```

If Metal fails, isolate whether the model files and engine are healthy:

```bash
qwen-image "prompt" --cpu --width 256 --height 256 --steps 1 --output outputs/cpu-test.png
```

## How VRAM scaling works

The weights do **not** all reside in VRAM. `stable-diffusion.cpp` inserts graph cuts between transformer blocks, maintains source parameters in RAM (or on disk), copies only the active segment to Metal, and evicts old segments under the configured budget. The Qwen3-VL encoder and VAE run on CPU so the AMD card is reserved for repeated denoising work. A 4 GB card uses the validated 3 GiB budget; 8–32 GB cards receive proportionally larger budgets and therefore require less aggressive segmentation.

This is distinct from fitting the whole Qwen-Image 2.1 pipeline in 4 GB. The full official BF16 pipeline is far larger, and the system still needs enough RAM and disk for quantized weights and temporary buffers.

## Updating the engine

The tested upstream commit is pinned in `scripts/engine-version.sh`. Change the commit deliberately, then rebuild:

```bash
rm -rf vendor/stable-diffusion.cpp build
./scripts/build.sh
```

Run `make test` for the wrapper's offline checks.

## Troubleshooting

Run `./scripts/doctor.sh` first. If `qwen-image` is not found after installation, add `~/.local/bin` to `PATH` or invoke `./qwen-image` from the checkout. For engine failures, retry a 256×256 one-step run with `--cpu`; this separates model and prompt issues from Metal issues.

Please use [GitHub Issues](../../issues) for reproducible bugs and include macOS version, Mac model, GPU/VRAM, RAM, the command used, and the relevant error output. Do not attach model files.

## Contributing and security

Contributions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Please report security concerns according to [SECURITY.md](SECURITY.md).

The source in this repository is MIT-licensed. Downloaded model weights and the upstream engine have their own licenses; review them before use or redistribution.
