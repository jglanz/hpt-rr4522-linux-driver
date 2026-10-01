# Contributing

## Ground rules

- `src/hptiop.c` and `src/hptiop.h` are the upstream v6.8 driver plus the
  changes listed in [docs/VENDOR-DELTA.md](docs/VENDOR-DELTA.md). Keep the
  diff against upstream small: no reformatting of upstream code, and every
  functional change gets a row in VENDOR-DELTA.md.
- Kernel version tests belong in `src/hptiop_compat.h` only; the driver
  tests `HPTIOP_HAVE_*` macros.
- Supported kernels are the Ubuntu 24.04 (6.8) and 26.04 (7.0) GA kernels.
  Supporting another kernel means a CI cell in `.github/workflows/ci.yml` and
  a W=1 baseline in `tests/static/w1-baseline/`.
- Name things by what they do. Comments explain the technical reason, not
  who asked for a change.

## Checks

```sh
make check            # jargon, versions, shellcheck, discovery fixtures,
                      # checkpatch, W=1 build for the running kernel
make sparse           # needs the sparse package
scripts/container-build.sh --image ubuntu:24.04 w1 sparse
scripts/container-build.sh --image ubuntu:26.04 w1 sparse
scripts/build-deb.sh
scripts/dkms-container-test.sh --image ubuntu:26.04
```

- **checkpatch** (`--strict`): new code must be clean. Findings that the
  unmodified upstream files already have are tolerated (see
  `scripts/checkpatch.sh`).
- **W=1**: warnings are compared with `tests/static/w1-baseline/<target>.txt`,
  generated from unmodified upstream code by `make w1-baseline`. Any new
  warning fails.
- **sparse**: compared the same way against the unmodified upstream driver.

## Hardware testing

`tests/hw/smoke.sh` runs read-only checks on a host with an RR4520/RR4522.
Include its output and `uname -r` in pull requests that touch the driver.

## Pull requests

- One topic per pull request, with a description of the problem it solves.
- Update `CHANGELOG.md` under *Unreleased*.
- Sign off your commits (`git commit -s`, Developer Certificate of Origin).
