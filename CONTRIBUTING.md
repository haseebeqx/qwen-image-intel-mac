# Contributing

Thank you for helping improve qwen-image-intel-mac.

## Before opening an issue

- Run `./scripts/doctor.sh` and search existing issues.
- Reproduce with the pinned engine revision.
- For Metal failures, compare with a small `--cpu --width 256 --height 256 --steps 1` run.
- Do not upload model weights, tokens, private prompts, or generated images you cannot redistribute.

Include your macOS version, Mac model, GPU and VRAM, system RAM, exact command, and relevant logs. Use fenced code blocks and remove personal paths or secrets.

## Development

This project intentionally uses Bash and the upstream C++ engine without a Python environment.

```bash
make test
./scripts/doctor.sh
```

Tests must not require model downloads or network access. Keep the engine commit pinned in `scripts/engine-version.sh`; engine upgrades should be isolated changes and describe the hardware and command used for validation.

## Pull requests

1. Create a focused branch and make one logical change per pull request.
2. Update documentation and offline tests when behavior changes.
3. Run `make test`.
4. Explain what was tested, including hardware for runtime or Metal changes.

By contributing, you agree that your contribution is licensed under the repository's MIT License. Do not commit generated images, build products, model files, or third-party source trees.
