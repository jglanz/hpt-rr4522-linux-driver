# Security policy

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

Please do not open a public issue for security problems. Report them
privately through GitHub's *Report a vulnerability* button on the repository's
*Security* tab, or by email to the maintainer listed in `debian/control`.

Include the driver version (`cat /sys/class/scsi_host/host*/driver-version`),
the kernel (`uname -r`), the controller model and steps to reproduce.

## Scope

In scope: the kernel module in `src/`, the DKMS configuration and the
packaging/maintenance scripts in this repository.

Out of scope: HighPoint's management software (`hptsvr`, `hptraidconf`) and
controller firmware; report those to HighPoint. Note that `hptsvr` listens on
TCP port 7402 with a default password, so restrict access to it.
