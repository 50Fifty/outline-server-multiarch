# outline-server-multiarch

Multi-arch Docker builds for [Jigsaw's Outline Server](https://github.com/Jigsaw-Code/outline-server).

This repository builds the upstream Shadowbox server image for the architectures supported by the current upstream build system.

| Image tag | Update interval                                         | Upstream target        | Supported OS/Arch        |
|-----------|---------------------------------------------------------|------------------------|--------------------------|
| master    | on push and daily at 00:00 UTC                          | upstream `master`      | linux/amd64, linux/arm64 |
| latest    | checked on push and daily at 00:00 UTC; rebuilt on new upstream releases | latest upstream release | linux/amd64, linux/arm64 |

The `latest` build follows the latest non-prerelease upstream Outline Server release. At the time this repository was updated, the latest upstream release was `server-v1.12.3`.

## Usage

To install Outline Server with an image built from this repository, set `SB_IMAGE` before running the official installer.

```bash
export SB_IMAGE="ghcr.io/50fifty/shadowbox:latest"

sudo env SB_IMAGE="${SB_IMAGE}" bash -s -- \
  --hostname=<ip-address> \
  --keys-port=<access-key-port> \
  --api-port=<api-port> < <(
    curl -sL "https://raw.githubusercontent.com/Jigsaw-Code/outline-server/master/src/server_manager/install_scripts/install_server.sh" \
      | sed '/local MACHINE_TYPE/,/fi/{d}'
)
```

The `sed` command removes the official installer's x86_64 host check so the installer can run on ARM hosts. The image itself still needs to support the host architecture.

## Development

Use `make help` to list patching helpers.

```bash
make clone-upstream
make apply-patches
make apply-patches PATCH_SET=master
```

The build script clones the upstream Outline Server repository, checks out the requested branch or tag, applies patches from `patches/release/` or `patches/master/`, installs upstream dependencies, and builds the Shadowbox Docker image through upstream's Taskfile.

### Local Build

Requirements:

- `git`
- `curl`
- `jq`
- Node.js 18 or 24 with `npm`
- Go version required by the selected upstream checkout; current upstream `master` requires Go 1.26.3 or newer
- Docker with Buildx and BuildKit support
- QEMU/binfmt support for cross-architecture Docker builds

Build and load one local image:

```bash
BUILD_OUTPUT=load bash ./build.sh \
  "linux/amd64" \
  "shadowbox-local:server-v1.12.3" \
  "server-v1.12.3"
```

Build and push a multi-arch image:

```bash
bash ./build.sh \
  "linux/amd64,linux/arm64" \
  "ghcr.io/<repo-owner>/shadowbox:latest" \
  "latest"
```

Replace `<repo-owner>` with the lowercase GHCR namespace you can push to. For this repository's published package, that namespace is `50fifty`.

`BUILD_OUTPUT=push` is the default. It builds per-architecture temporary tags and then creates the final multi-arch manifest tag.

### Supported Platforms

Only `linux/amd64` and `linux/arm64` are supported by this update.

Older versions of this repository advertised `linux/arm/v7` and `linux/arm/v6`, but upstream Outline Server now builds Shadowbox through a Taskfile/Go/Docker path that only has first-class settings for x86_64 and arm64. Restoring 32-bit ARM support would require additional upstream patches for Node base images, Prometheus artifacts, Go `GOARM` handling, and CI coverage.

### Troubleshooting

#### `Unsupported machine type: ${MACHINE_TYPE}. Please run this script on a x86_64 machine.`

Pipe the official installer through the documented `sed` command:

```bash
export SB_IMAGE="ghcr.io/50fifty/shadowbox:latest"

sudo env SB_IMAGE="${SB_IMAGE}" bash -s -- < <(
  curl -sL "https://raw.githubusercontent.com/Jigsaw-Code/outline-server/master/src/server_manager/install_scripts/install_server.sh" \
    | sed '/local MACHINE_TYPE/,/fi/{d}'
)
```

## Attribution and License

This repository contains and modifies work by the Outline Server authors.

The patches in `patches/` modify upstream `src/shadowbox/Taskfile.yml` so this repository can pass Docker Buildx flags into the upstream Docker build task.

This project was originally created in [seia-soto/outline-server-multiarch](https://github.com/seia-soto/outline-server-multiarch) by [seia-soto](https://github.com/seia-soto), as a multi-architecture distribution of Outline Server for ARM servers; those original project files are licensed under the [MIT License](./LICENSE).
