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

systemd unit: [`deploy/hugginghub.service`](deploy/hugginghub.service).
NixOS hosts should use the [NixOS module](#nixos) instead of that unit.

## NixOS

The flake builds the same Cargo package as `cargo build --release` and exports a NixOS module at `nixosModules.default` and `nixosModules.hugginghub` (the same module). Local disk is the default. S3 is optional and stays off unless you set it.

The upstream license is [PolyForm Noncommercial 1.0.0](LICENSE). Nix treats that as unfree, so the host configuration has to allow this package:

```nix
nixpkgs.config.allowUnfreePredicate = pkg: pkg.pname == "hugginghub";
```

If you already set `allowUnfree` or your own predicate, extend that instead of replacing it.

### Import and enable

Pin the fork in the host flake and import the module into the existing NixOS configuration:

```nix
{
  inputs.hugginghub.url = "github:OnixResearch/hugginghub";

  outputs = { nixpkgs, hugginghub, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        ./configuration.nix
        hugginghub.nixosModules.default
      ];
    };
  };
}
```

```nix
# configuration.nix
{ ... }:
{
  nixpkgs.config.allowUnfreePredicate = pkg: pkg.pname == "hugginghub";

  services.hugginghub = {
    enable = true;
    # Loopback is the default. Bind a LAN address so other machines can connect.
    address = "0.0.0.0"; # or a specific address, such as "10.0.0.5"
    port = 8080;
    # The firewall stays closed unless this is set.
    openFirewall = true;
    # Local disk. Default is /var/lib/hugginghub. S3 is not used.
    openSignup = false;
  };
}
```

`openSignup` defaults to false in the module (the binary defaults to true). `dataDir` defaults to `/var/lib/hugginghub`; point it at a large volume if the models will not fit on the root disk. The service runs as the `hugginghub` user and restarts on failure.

After the system is activated, create the first administrator. The command prints a password and an API token once. Run it as the service user so the database is not owned by root:

```bash
sudo -u hugginghub hugginghub create-user admin
```

The `hugginghub` command on `PATH` is a wrapper that sets `HH_DATA` to the configured directory. `create-token` and `info` work the same way.

### Clients

`huggingface_hub` and the `hf` CLI follow `HF_ENDPOINT`. This server stores large files as Git LFS objects, not Xet, so also disable Xet or downloads can miss the mirror:

```bash
export HF_ENDPOINT=http://hub.lan:8080
export HF_TOKEN=hf_...
export HF_HUB_DISABLE_XET=1
hf download namespace/model
```

`git` and `git-lfs` do not read `HF_ENDPOINT`. Clone the mirror URL directly:

```bash
git clone http://hub.lan:8080/namespace/model
```

Anything that hardcodes `huggingface.co` still talks to the public Hub. That includes fetchers which never consult `HF_ENDPOINT`, for example rwkv-clm's `python/scripts/fetch_mimo.py`. Those programs have to learn the mirror on their own; pointing the shell at `HF_ENDPOINT` does not change them.

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
