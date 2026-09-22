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
- diffusion graphs split across short Metal command buffers to avoid the Intel-macOS GPU watchdog

The complete text-to-image download is about **8.3 GB**. Expect generation to be slow; this is an enablement project for constrained hardware, not a claim that a 4 GB 5300M performs like a modern CUDA GPU.

Validated on a 2019 16-inch MacBook Pro (Core i7, 16 GB RAM, Radeon Pro 5300M 4 GB). A cold 256×256 one-step smoke test completed end-to-end in 62.5 seconds, including text encoding, first-time Metal pipeline compilation, denoising, CPU VAE decode, and PNG save. Normal 20-step generations take considerably longer. Intel Macs with 8 GB, 16 GB, or 32 GB of AMD VRAM are also supported; the wrapper detects the card's actual capacity and raises its managed Metal budget while reserving 1 GiB for the display server and workspace.

## Requirements

- Intel Mac, macOS 14 or newer
- AMD GPU with Metal support and 4–32 GB VRAM
- 16 GB system RAM (close other memory-heavy applications)
- about 10 GB free disk space for the release and model files
- curl (included with macOS)

Building from source additionally requires about 20 GB free disk space, Xcode Command Line Tools, CMake, and Git.

The model is governed by the [Qwen Research License Agreement](https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE). Read it before downloading.

## Install

Install from the web:

```bash
curl -fsSL https://raw.githubusercontent.com/haseebeqx/qwen-image-intel-mac/main/web-install.sh | bash
```

The web installer downloads the prebuilt, checksum-verified Intel macOS bundle from the latest GitHub release into `~/.local/share/qwen-image-intel-mac`. It checks the host and links `qwen-image` into `~/.local/bin`; it does not download models, install build tools, or compile the engine. Add the command directory to `PATH` if prompted.

Models are downloaded to `~/.qwen-image` by default. To install a specific release, set `QWEN_INSTALL_VERSION` to one of the tags listed on the [Releases page](https://github.com/haseebeqx/qwen-image-intel-mac/releases). Running the installer again cleanly replaces the application bundle with the selected release, removing obsolete bundle files without affecting downloaded models.

If you prefer to inspect the source or build the engine locally, clone the repository and run:

```bash
git clone https://github.com/haseebeqx/qwen-image-intel-mac.git
cd qwen-image-intel-mac
./install.sh
```

To choose another command directory:

```bash
./install.sh --bin-dir /usr/local/bin
```

Installation does not download model files. Set `QWEN_MODEL_DIR` when running the command, or pass `--model-dir`, to use a location other than `~/.qwen-image`.

### Manual setup

```bash
./scripts/doctor.sh
./scripts/build.sh
./scripts/download-models.sh --accept-license
```

The default text-to-image set does not include the vision projector needed for image editing.

On the first generation, `qwen-image` downloads any missing model files (about 8.3 GB) after displaying the model license URL. Downloads resume if interrupted. `qwen-image --help` never downloads models. Review the [Qwen Research License Agreement](https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE) before the first run.

## Uninstall

Choose the commands that match how you installed the project.

For the default web installation, remove the command link, managed release directory, and downloaded models:

```bash
rm -f "$HOME/.local/bin/qwen-image"
rm -rf "$HOME/.local/share/qwen-image-intel-mac"
rm -rf "$HOME/.qwen-image"
```

For an installation from a repository you cloned yourself, remove the command link and then remove the checkout if you no longer need it:

```bash
rm -f "$HOME/.local/bin/qwen-image"
rm -rf /path/to/qwen-image-intel-mac
```

If you used `--bin-dir`, remove the link from that directory instead (use `sudo` only if the directory requires it):

```bash
sudo rm -f /usr/local/bin/qwen-image
```

A manual setup does not install a command link. Remove the checkout and `~/.qwen-image` separately if you also want to delete the default model files. Models stored elsewhere through `QWEN_MODEL_DIR` or `--model-dir` must likewise be deleted separately. Before removing a checkout, save any generated files under its `outputs/` directory that you want to keep.

## Generate

```bash
qwen-image "A studio photograph of a tiny robot holding a sign that says 'HELLO MAC'" \
  --output outputs/robot.png
```

Conservative defaults are 512×512, 20 Euler steps, CFG 6, seed 42, and an automatically sized Metal budget. The wrapper reserves 1 GiB of detected AMD VRAM, producing budgets of 3, 7, 15, and 31 GiB on 4, 8, 16, and 32 GB cards respectively. It calculates this from the reported capacity rather than using a fixed list, and falls back to 3 GiB if detection fails. Width and height must be at least 256 and multiples of 32.

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

Each invocation reads about 8.3 GB (7.7 GiB) of model files, so even a fast generation has a fixed cold-start cost. The first Metal run also compiles GPU pipelines. Keep `QWEN_DISK_PARAMS` unset unless memory pressure requires it: disk-backed parameters are substantially slower.

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
--model-dir PATH   model directory (default ~/.qwen-image)
--reference PATH   reference image; repeat for multi-image editing
--fast             256px, 12-step, CFG-6 preview profile
--cpu              diagnostic CPU-only mode
--verbose          show the engine command and full engine output
--dry-run          validate and print the engine command
-V, --version      show the qwen-image version
--                 pass remaining arguments directly to sd-cli
```

Normal runs show compact stage labels plus the engine's live progress bars, including completed/total denoising steps, model loading, and decoding. Use `--verbose` to bypass this display and stream the complete engine diagnostics. If a compact run fails, its captured engine output is printed automatically.

Environment variables with the same purpose are also accepted: `QWEN_MODEL_DIR`, `QWEN_VRAM_GIB`, `QWEN_THREADS`, and `QWEN_METAL_DEVICE` (default `MTL0`). Set `QWEN_VRAM_GIB` or use `--vram` to override automatic sizing. The wrapper also defaults `GGML_METAL_N_CB` to `8`, using the project's small ggml patch to divide slow GPU work into watchdog-safe command buffers; advanced users can override it with a value from 1 through 8.

## Image editing (experimental)

The extra 0.75 GB vision projector is downloaded automatically the first time a reference image is used:

```bash
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

Graph cuts manage memory, but they do not necessarily make a compute submission short enough for the macOS GPU watchdog. The build therefore carries a narrow ggml patch that exposes command-buffer count through `GGML_METAL_N_CB`; the wrapper uses eight secondary buffers by default. This changes scheduling only, not model calculations or weights.

This is distinct from fitting the whole Qwen-Image 2.1 pipeline in 4 GB. The full official BF16 pipeline is far larger, and the system still needs enough RAM and disk for quantized weights and temporary buffers.

## Update

For a web installation, rerun the installer to replace the application bundle with the latest release. Downloaded models are preserved:

```bash
curl -fsSL https://raw.githubusercontent.com/haseebeqx/qwen-image-intel-mac/main/web-install.sh | bash
```

For an installation from a cloned repository, pull the latest source and rebuild the pinned engine:

```bash
git pull --ff-only
./install.sh
```

### Updating the upstream engine pin

The tested `stable-diffusion.cpp` commit is pinned in `scripts/engine-version.sh`. Maintainers changing that pin should rebuild from a clean engine checkout:

```bash
rm -rf vendor/stable-diffusion.cpp build
./scripts/build.sh
make test
```

## Troubleshooting

Run `./scripts/doctor.sh` first. If `qwen-image` is not found after installation, add `~/.local/bin` to `PATH` or invoke `./qwen-image` from the checkout. For engine failures, retry a 256×256 one-step run with `--cpu`; this separates model and prompt issues from Metal issues.

Please use [GitHub Issues](../../issues) for reproducible bugs and include macOS version, Mac model, GPU/VRAM, RAM, the command used, and the relevant error output. Do not attach model files.

## Contributing and security

Contributions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Please report security concerns according to [SECURITY.md](SECURITY.md).

The source in this repository is MIT-licensed. Downloaded model weights and the upstream engine have their own licenses; review them before use or redistribution.
