# Secure Boot and module signing

With UEFI Secure Boot enabled, the kernel loads only modules signed by a
trusted key. DKMS signs the modules it builds with a Machine Owner Key (MOK)
that you enrol once.

Check whether Secure Boot is on:

```sh
mokutil --sb-state
```

## Ubuntu 24.04 and 26.04

Ubuntu's DKMS signs modules with the key pair in `/var/lib/shim-signed/mok/`
(`MOK.priv`, `MOK.der`). If it does not exist, the first DKMS build creates it
and asks you to enrol it.

1. Install the package (or run `dkms install`). If prompted, choose a
   one-time password.
2. Reboot. The blue *MOK Manager* screen appears: choose *Enroll MOK*,
   *Continue*, and enter the password.
3. Check that the key is enrolled and the module signed:

   ```sh
   mokutil --list-enrolled | grep -i 'subject:'
   modinfo -F signer hptiop
   ```

To enrol an existing key by hand:

```sh
sudo mokutil --import /var/lib/shim-signed/mok/MOK.der
sudo reboot
```

## Custom keys

DKMS reads the key locations from `/etc/dkms/framework.conf`:

```
mok_signing_key=/path/to/MOK.priv
mok_certificate=/path/to/MOK.der
```

Enrol the certificate with `mokutil --import` as above. After changing keys,
rebuild: `sudo dkms remove hptiop/2.0.0 --all && sudo dkms install hptiop/2.0.0`.

## Symptoms of an unsigned module

- `modprobe: ERROR: could not insert 'hptiop': Key was rejected by service`
- `Loading of unsigned module is rejected` in `journalctl -k`

While the unsigned DKMS module is installed, `modprobe` keeps choosing it
over the in-kernel driver and fails. Either enrol the key, or run
`sudo dkms remove hptiop/2.0.0 --all` to return to the in-kernel driver.
