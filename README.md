<div align="center">

# 🤗 HuggingHub

**Your own Hugging Face Hub.** Self-hosted, source-available, and wire-compatible with `huggingface_hub`.

Models · Datasets · Spaces — with cards, files, git history, discussions and pull requests.
No billing. No quotas. No account on someone else's machine.

<br>

<img src="docs/twitter-card.png" alt="HuggingHub overview" width="760">

</div>

---

This repository is the [OnixResearch/hugginghub](https://github.com/OnixResearch/hugginghub) fork of [empero-org/hugginghub](https://github.com/empero-org/hugginghub). The [NixOS module](#nixos) runs that server as a local Hub mirror.

HuggingHub is a single Rust binary that reimplements the Hugging Face Hub HTTP API, so everything that talks to `huggingface.co` — `huggingface_hub`, `transformers`, `datasets`, `diffusers`, `accelerate`, the `hf` CLI, `git`/`git-lfs` — can talk to *your* server instead, usually with a two-line change or one environment variable.

```python
import hugginghub
hugginghub.connect("http://my-server:8080", token="hf_...")

from huggingface_hub import HfApi, snapshot_download
api = HfApi()
api.create_repo("me/my-model", exist_ok=True)
api.upload_folder(repo_id="me/my-model", folder_path="./my-model")
snapshot_download("me/my-model")
```

...or with plain environment variables, no shim at all:

```bash
export HF_ENDPOINT=http://my-server:8080
export HF_TOKEN=hf_...
hf download me/my-model
```

## What it does

| Area | Support |
| --- | --- |
| Repos | model / dataset / space, public or private, rename, move, delete, gated flag |
| Files | NDJSON commit API, preupload (regular vs LFS), resolve with Range requests, snapshots, folder uploads |
| Large files | Git LFS: batch API, upload/verify, download, content-addressed dedup store |
| Git | smart HTTP clone/fetch/push (incl. `git-lfs`), branches, tags, `refs/pr/N` |
| Community | discussions, comments, edits/hides, open/close/merge, pull requests with diffs |
| Social | likes, followers, user and organization profiles, org membership |
| **Spaces** | `sdk: static` spaces **run** — the repo's files are served as a web app at `/spaces/ns/name/app/` and embedded on the space page; gradio/streamlit apps can be embedded from an external URL set in Settings |
| Web UI | landing page, listings, model/dataset/Space cards, file browser, blob view, commit history and diffs, discussions, settings, tokens |
| Admin | `/admin` panel: users (create, grant/revoke admin, reset passwords, delete), repositories, organizations, server info |
| Storage | local disk, or any S3-compatible bucket (AWS S3, R2, B2, Wasabi, MinIO, Ceph) with optional presigned redirects |

Deliberately **not** included: inference, a container runtime for gradio/streamlit
Spaces, jobs, papers, collections, billing, hardware.

## Run it

Requirements: Rust 1.75+, `git` (2.30+), and `git-lfs` if you want the CLI to
handle large files.

```bash
cargo build --release
export HH_DATA=/var/lib/hugginghub
./target/release/hugginghub create-user admin 'a-good-password'   # prints an API token
./target/release/hugginghub                                       # serves on 0.0.0.0:8080
```

The first user created is an administrator. Put it behind a reverse proxy (Caddy,
nginx) for TLS — the app derives URLs from the request's `Host` header, so
`X-Forwarded-Host`/`X-Forwarded-Proto` are respected automatically.

systemd unit: [`deploy/hugginghub.service`](deploy/hugginghub.service) (upstream, system-wide).
NixOS hosts, including the GB10 Sparks, use the [NixOS module](#nixos). [`deploy/`](deploy/README.md) is an optional fallback for a machine that cannot import that module.

## NixOS

The flake builds the existing Cargo package and exports one NixOS module as `nixosModules.default` and `nixosModules.hugginghub`. It is the deploy path for the aarch64 GB10 Sparks and for other NixOS hosts (aspen2, aspen3). Import it beside `spark-nixos.nixosModules.default`. The host's own `configuration.nix` stays in the host flake; this repo does not ship that file, and spark-nixos does not either.

Local disk is the default (`/var/lib/hugginghub`). S3 is off unless you set it. The service has its own user and restarts on failure. `openFirewall` defaults to false, so enabling the service does not open a port. `address` defaults to loopback.

The upstream license is [PolyForm Noncommercial 1.0.0](LICENSE). Nix treats that as unfree. If the host does not already allow unfree packages, extend its predicate instead of replacing one that already exists:

```nix
nixpkgs.config.allowUnfreePredicate = pkg: pkg.pname == "hugginghub";
```

### GB10 Sparks

Run the hub on **spark-e442**. It is on the tailnet (`spark-e442`, `100.91.82.77`) and on the LAN at `192.168.1.244`, and it has the ConnectX path to spark-a0a0 (from e442 that peer is `dspark-worker`, `10.44.0.2`). spark-a0a0 is `192.168.1.234` and is reached over SSH via britton-desktop. The same module can be enabled on a0a0 instead; e442 is the better default so tailnet clients and a0a0 can both use one seed.

The pinned model set those hosts otherwise download separately is about 22 GB (`scripts/fetch-models.sh` in OnixResearch/rwkv-clm). Seed it once on e442. a0a0 then uses `HF_ENDPOINT` and does not download that set from huggingface.co again.

In the **host** flake (not in spark-nixos, and not committed here):

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    spark-nixos.url = "github:OnixResearch/spark-nixos";
    spark-nixos.inputs.nixpkgs.follows = "nixpkgs";
    hugginghub.url = "github:OnixResearch/hugginghub";
    hugginghub.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, spark-nixos, hugginghub, ... }: {
    nixosConfigurations.spark-e442 = nixpkgs.lib.nixosSystem {
      modules = [
        spark-nixos.nixosModules.default
        hugginghub.nixosModules.default
        ./configuration.nix # this host's file, outside both flakes
        {
          nixpkgs.hostPlatform = "aarch64-linux";
          services.hugginghub = {
            enable = true;
            # Loopback is the default. 0.0.0.0 covers tailscale, LAN, and ConnectX.
            address = "0.0.0.0";
            port = 8080;
            # NixOS firewall stays closed unless this is set. One TCP port, not a trusted interface.
            openFirewall = true;
          };
        }
      ];
    };
  };
}
```

`nixosModules.hugginghub` is the same module. The package is built with the host's nixpkgs for `aarch64-linux` on the first `nixos-rebuild`; it does not build the NVIDIA kernel. Port 8080 is not one of Kindling's mentat, agent, or example model ports. `openFirewall` adds that port on every interface. It does not mark an interface trusted. A ConnectX port that spark-nixos already trusts can reach the hub without this, but the LAN address and tailscale cannot unless the port is open or those interfaces are trusted too.

`dataDir` defaults to `/var/lib/hugginghub` (hub database, git repos, and LFS objects). Point it at a larger filesystem if the root volume cannot hold the models. `openSignup` defaults to false.

After the switch, create the administrator. The command prints a password and an API token once. Run it as the service user:

```bash
sudo -u hugginghub hugginghub create-user admin
```

The `hugginghub` command on `PATH` is a wrapper that sets `HH_DATA`. `create-token` and `info` work the same way.

To run the hub on spark-a0a0 instead, enable the same options there. Clients then use `http://192.168.1.234:8080`.

### Seed the mirror

Push the upstream git history. Do not re-upload with `hf upload` or a fresh commit: rwkv-clm pins commit SHAs, and a new commit will not match them. The hub's create step writes a throwaway initial commit; `git push --mirror` replaces `main` with the upstream history (the server allows that non-fast-forward). LFS objects are uploaded after the git objects, so the SHAs are present even if the weight upload is resumed later.

Create an organization whose name is the upstream namespace (`/organizations/new` while logged in as admin) before creating `owner/name`. `HH_TOKEN` is the mirror token from `create-user`. It is not sent to huggingface.co. A public upstream repo needs no huggingface.co token. `git` and `git-lfs` have to be on the machine that seeds (`nix shell nixpkgs#git nixpkgs#git-lfs nixpkgs#curl` is enough; that does not change the host configuration):

```bash
HH_TOKEN=hf_... HF_ENDPOINT=http://127.0.0.1:8080 \
  deploy/seed-from-upstream.sh owner/model
```

Repeat for each repo id `scripts/fetch-models.sh` pins. Model git URLs are `http://<host>:8080/owner/name`.

### Clients

`huggingface_hub` and the `hf` CLI follow `HF_ENDPOINT`. This server stores large files as Git LFS, not Xet, so also disable Xet:

```bash
export HF_ENDPOINT=http://192.168.1.244:8080   # spark-a0a0, on the LAN
export HF_TOKEN=hf_...                         # the mirror token
export HF_HUB_DISABLE_XET=1
hf download owner/model
```

From a tailnet machine (for example aspen2 or aspen3, if they are not running their own hub): `http://spark-e442:8080` or `http://100.91.82.77:8080`. Over the ConnectX link, use the address a0a0 already uses to reach e442. e442 reaches a0a0 as `10.44.0.2`; that address is a0a0, not e442.

`git` does not read `HF_ENDPOINT`. Clone `http://192.168.1.244:8080/owner/name` (or the tailnet URL) directly.

Anything that hardcodes `huggingface.co` still talks to the public Hub. That includes rwkv-clm's `scripts/fetch-models.sh` if it does not honor `HF_ENDPOINT`, and `python/scripts/fetch_mimo.py`. Those programs have to learn the mirror on their own.

### Other NixOS hosts

Same module, without spark-nixos:

```nix
{
  inputs.hugginghub.url = "github:OnixResearch/hugginghub";

  outputs = { nixpkgs, hugginghub, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        ./configuration.nix
        hugginghub.nixosModules.default
        { services.hugginghub.enable = true; }
      ];
    };
  };
}
```

Leave `address` on loopback until other machines should connect, and leave `openFirewall` false until you want that port open.

### Module options

| Option | Default | Maps to |
| --- | --- | --- |
| `enable` | `false` | systemd service |
| `package` | this flake, built with the host nixpkgs | the binary |
| `address` | `127.0.0.1` | `HH_BIND` host |
| `port` | `8080` | `HH_BIND` port |
| `openFirewall` | `false` | NixOS firewall |
| `dataDir` | `/var/lib/hugginghub` | `HH_DATA` |
| `user` / `group` | `hugginghub` | service account |
| `publicUrl` | unset | `HH_PUBLIC_URL` |
| `siteName` | `HuggingHub` | `HH_SITE_NAME` |
| `openSignup` | `false` | `HH_OPEN_SIGNUP` |
| `lfsThreshold` | `10485760` | `HH_LFS_THRESHOLD` |
| `gitPackage` | `pkgs.gitMinimal` | `HH_GIT` |
| `logLevel` | `info` | `RUST_LOG` |
| `storage` | `local` | `HH_STORAGE` (`local` or `s3`) |
| `s3.bucket` | unset | `HH_S3_BUCKET` (required when `storage = "s3"`) |
| `s3.endpoint` | unset | `HH_S3_ENDPOINT` |
| `s3.region` | unset | `HH_S3_REGION` |
| `s3.prefix` | unset | `HH_S3_PREFIX` |
| `s3.pathStyle` | `true` | `HH_S3_PATH_STYLE` |
| `s3.redirect` | `false` | `HH_S3_REDIRECT` |
| `environmentFile` | unset | systemd `EnvironmentFile` for S3 credentials |
| `extraEnvironment` | `{ }` | extra variables, applied last; not for secrets |

### S3

Leave `storage` at `local` unless LFS objects should live in a bucket. Git repositories stay on `dataDir` either way. Credentials are not module options and must not be written into the Nix store. Put them in a file on the host and pass its absolute path as a string:

```nix
services.hugginghub = {
  storage = "s3";
  environmentFile = "/run/secrets/hugginghub.env";
  s3 = {
    bucket = "hugginghub";
    endpoint = "https://s3.example.net";
    region = "us-east-1";
  };
};
```

That file holds `HH_S3_ACCESS_KEY` and `HH_S3_SECRET_KEY`. See [S3-compatible storage](#s3-compatible-storage) for the variables the server already understands.

### Not the Spark path

[`deploy/`](deploy/README.md) has an upstream system unit and an optional user-level Docker / `systemd --user` fallback. The Sparks are NixOS; use `services.hugginghub` on them. The fallback does not need sudo when the login user can already run `docker`, and its data directory is `$HOME/.local/share/hugginghub`. A `systemd --user` unit stops at logout unless `loginctl enable-linger` was run once (that needs sudo). `deploy/up.sh` does not need linger, because dockerd keeps a `restart: unless-stopped` container. None of that is required on spark-e442 or spark-a0a0.

## Configuration

All settings are environment variables.

| Variable | Default | Meaning |
| --- | --- | --- |
| `HH_BIND` | `0.0.0.0:8080` | listen address |
| `HH_DATA` | `./data` | data dir (`hub.db`, `repos/`, `tmp/`, `avatars/`) |
| `HH_PUBLIC_URL` | derived from request | force an external base URL |
| `HH_SITE_NAME` | `HuggingHub` | name shown in the UI |
| `HH_OPEN_SIGNUP` | `true` | allow self sign-up |
| `HH_LFS_THRESHOLD` | `10485760` | files at or above this size go to LFS on preupload |
| `HH_STORAGE` | `local` | `local` or `s3` |
| `HH_GIT` | `git` | path to the git binary |

### S3-compatible storage

Large files (LFS objects) can live in a bucket instead of local disk. Git
repositories — pointers, text, history — always stay on local disk, which keeps
clones fast and the bucket simple.

```bash
HH_STORAGE=s3
HH_S3_BUCKET=hugginghub
HH_S3_ENDPOINT=https://s3.eu-central-1.amazonaws.com   # or https://<account>.r2.cloudflarestorage.com
HH_S3_REGION=eu-central-1
HH_S3_ACCESS_KEY=...
HH_S3_SECRET_KEY=...
HH_S3_PREFIX=hugginghub/prod        # optional key prefix
HH_S3_PATH_STYLE=1                  # default 1 (MinIO, Ceph); set 0 for AWS virtual-hosted style
HH_S3_REDIRECT=0                    # 1 = hand clients presigned URLs instead of proxying bytes
```

Objects are stored as `lfs/<aa>/<bb>/<sha256>`, content-addressed, so identical
files across repos are stored once. Uploads use a single PUT up to 256 MB and
multipart above that. With `HH_S3_REDIRECT=1` downloads become `302` redirects to
presigned URLs, like the Hub's CDN redirects — the bucket must then be reachable
by clients.

## The Python shim

`python/` contains a small package ([on PyPI](https://pypi.org/project/hugginghub/)) that points `huggingface_hub` at your server:

```bash
pip install hugginghub
hugginghub connect http://my-server:8080 --token hf_...   # saved to ~/.config/hugginghub
hugginghub install-hook                                   # every Python process picks it up
```

`connect()` is **per process, not per file**: call it once at your program's
entry point and every module in that process uses your hub. For one shell
session use `export HF_ENDPOINT=...`; for the whole machine use
`hugginghub install-hook`. See [`python/README.md`](python/README.md) and the
built-in **How to use** page (`/docs` on your server).

## Testing

```bash
tests/e2e_hub.py    http://host:port hf_token   # 23 checks with the real huggingface_hub client
tests/e2e_git.sh    http://host:port hf_token   # clone/push, git-lfs, anonymous access, PR refs
tests/e2e_web.sh    http://host:port hf_token   # every web page renders, admin panel, app serving
tests/seed_demo.py  http://host:port hf_token   # demo repos + a runnable static space
```

## Architecture

```
src/
  main.rs        router, CLI (create-user, create-token, info)
  routes.rs      request plumbing; repo URLs are parsed from raw path segments
                 because ids contain '/' and revisions arrive percent-encoded
  api/           Hub-compatible HTTP API (repos, files, commit, lfs, community, users)
  githttp.rs     smart HTTP via `git http-backend` (CGI)
  git/           bare-repo plumbing: trees, commits through a throwaway index,
                 refs, merges, LFS pointers
  storage/       LFS object store: local disk or S3 (SigV4, multipart, presigning)
  web/           server-rendered UI (minijinja templates, embedded assets)
  db.rs          SQLite schema; models.rs permissions; auth.rs tokens and sessions
```

Design notes:

- Every repo is a bare git repository; the API builds commits with `read-tree` /
  `update-index` / `write-tree` / `commit-tree` and moves refs with a
  compare-and-swap, so the API and `git push` share one source of truth.
- Large files are stored as real LFS pointer blobs in git and as objects in the
  LFS store, exactly like the Hub.
- `huggingface_hub` uploads LFS content with an unauthenticated PUT, so the
  upload/download hrefs handed out by the batch API carry a short-lived ticket.
- Pull requests are discussions whose commits live on `refs/pr/N`; merging is a
  fast-forward when possible, otherwise a merge commit built with `merge-tree`.
- Static Spaces are served straight out of the repo at `/spaces/ns/name/app/`
  with proper MIME types and trailing-slash semantics; non-static Spaces embed
  an external `app_url`.

## Security notes

- Passwords are hashed with Argon2id; API tokens are `hf_`-prefixed random secrets stored as SHA-256 hashes and shown once.
- `HH_OPEN_SIGNUP=0` closes registration; admins can always create users from `/admin`.
- The default is HTTP on a single box — put TLS in front before sharing it.
- Don't ship real tokens in commits; the values in this repo are placeholders (`hf_...`).

## License

Licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE) — free for personal, research, educational, non-profit, and non-commercial use. For commercial licensing, contact [Empero](https://empero.org).

---

<div align="center">
<sub>Fork of <a href="https://github.com/empero-org/hugginghub">empero-org/hugginghub</a>. Built by <a href="https://empero.org">Empero</a>.</sub>
</div>
