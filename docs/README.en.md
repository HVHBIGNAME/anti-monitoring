# Anti-Monitoring

**Linux guest-agent control. One script, configured with flags.**

[Русский](../README.md) · [Compatibility](COMPATIBILITY.md) · [MIT](../LICENSE)

## Run

Open the menu without installing:

```sh
curl -fsSL https://raw.githubusercontent.com/HVHBIGNAME/anti-monitoring/main/antimon.sh | sudo sh -s -- --menu
```

Install the `antimon` command:

```sh
curl -fsSL https://raw.githubusercontent.com/HVHBIGNAME/anti-monitoring/main/antimon.sh | sudo sh -s -- --install
```

Already root? Omit `sudo`. Replace the final flag with any action below.

## Flags

| Flag | Purpose |
| :-- | :-- |
| `--help` / `-h` | Full help and examples |
| `--scan` / `--list` | Inspect agents / list agent IDs |
| `--disable` / `--remove` | Disable services / also remove their packages |
| `--restore` | Restore recorded service states |
| `--agents qemu,aws-ssm` / `--all` | Select agent groups |
| `--dry-run` / `--yes` | Preview / confirm without a prompt |
| `--install` / `--uninstall` | Install / uninstall the command |
| `--autostart` / `--no-autostart` | Register / remove execution at Linux boot |
| `--run` | Open the menu immediately after `--install` |
| `--prefix DIR` | Custom installation prefix |
| `--lang en` / `--lang ru` | Interface language |

```sh
antimon --scan
antimon --disable --agents qemu --dry-run
sudo antimon --disable --agents qemu --yes
sudo antimon --autostart --agents qemu --yes
sudo antimon --no-autostart
sudo antimon --restore
sudo antimon --uninstall
```

Autostart is **off by default** and runs `--disable` for the selected agents at boot.
Combine `--install --autostart --agents qemu --yes` to install and register it at once.
Guest-agent changes may affect VM integration; they cannot block hypervisor access.

[Advanced options and local reports](USAGE.md) · [Validation](COMPATIBILITY.md)
