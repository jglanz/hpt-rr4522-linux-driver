# Releasing

1. Update the version in all four places, which
   `tests/static/version-consistency_test.sh` checks:
   - `Makefile` (`VERSION :=`)
   - `dkms.conf` (`PACKAGE_VERSION=`)
   - `debian/changelog` (new entry, e.g. `dch -v 2.0.1`)
   - `CHANGELOG.md` (move *Unreleased* items under a new version heading
     with today's date)
2. Run `make check`, `scripts/container-build.sh --image ubuntu:24.04` and
   `--image ubuntu:26.04`, and on hardware `tests/hw/smoke.sh`.
3. Commit, then tag and push the tag:

   ```sh
   git tag -s v2.0.1 -m v2.0.1
   git push origin v2.0.1
   ```

4. `.github/workflows/release.yml` checks that the tag matches the version,
   builds `hptiop-dkms_<version>_all.deb` (with lintian) and
   `hptiop-<version>.tar.gz`, and writes `SHA256SUMS`. It attests build
   provenance and publishes a GitHub release with those files.

Users can verify a download with:

```sh
sha256sum -c SHA256SUMS --ignore-missing
gh attestation verify hptiop-dkms_2.0.1_all.deb --repo jglanz/hpt-rr4522-linux-driver
```

## Launchpad PPA (optional)

The package is a native Debian source package, so a PPA upload is:

```sh
dpkg-buildpackage -S -sa -d        # signed source package
dput ppa:<owner>/<ppa> ../hptiop-dkms_<version>_source.changes
```

Use a distribution name accepted by Launchpad (e.g. `noble`, `resolute`) in
`debian/changelog`. One upload per series may be needed with a `~series1`
version suffix.
