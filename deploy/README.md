# Optional fallback

The GB10 Sparks run NixOS. Enable `services.hugginghub` from this flake and import it next to `spark-nixos.nixosModules.default`. That is the deploy path. Host flakes stay in the host repository; nothing here belongs in spark-nixos.

The files in this directory other than that note are an **optional fallback** for a machine that cannot import the NixOS module. They are not how spark-e442 or spark-a0a0 should run the hub.

| File | What it is |
| --- | --- |
| `hugginghub.service` | Upstream system unit. Runs as root, port 80, data in `/var/lib`. |
| `docker-compose.yml`, `Dockerfile`, `up.sh`, `down.sh` | User-level Docker, no sudo if the login user can already run `docker`. Data under `$HOME/.local/share/hugginghub`. |
| `hugginghub.user.service` | `systemd --user` wrapper around compose. Stops at logout unless linger is enabled (`loginctl enable-linger` needs sudo once). |
| `hugginghub-binary.user.service` | `systemd --user` for a binary at `~/.local/bin/hugginghub`. Same linger caveat. |
| `seed-from-upstream.sh` | Copies upstream git history onto a hub that is already running, preserving commit SHAs. Works against the NixOS service or this fallback. |

`deploy/up.sh` publishes `HH_PUBLISH_ADDR`:`HH_PORT` (default `0.0.0.0:8080`) and keeps the container up via Docker's `restart: unless-stopped`, which does not need a user systemd session. Do not put tokens in `~/.config/hugginghub.env`.

Seeding and `HF_ENDPOINT` are documented in the main README. The NixOS module is the same on either Spark; run the hub on spark-e442 and point spark-a0a0 at it.
