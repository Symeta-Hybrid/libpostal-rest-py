# libpostal-rest-py

A minimal HTTP wrapper around [libpostal](https://github.com/openvenues/libpostal), the statistical
address parser, exposing it as two read-only JSON endpoints.

[![Docker Hub](https://img.shields.io/docker/v/symetahybrid/libpostal-rest-py?label=docker%20hub&sort=semver)](https://hub.docker.com/r/symetahybrid/libpostal-rest-py)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

```console
$ curl -s --get --data-urlencode 'query=781 Franklin Ave Crown Hts Brooklyn NY' localhost:8080/parse
[{"label":"house_number","value":"781"},{"label":"road","value":"franklin ave"},
 {"label":"suburb","value":"crown hts"},{"label":"city_district","value":"brooklyn"},
 {"label":"state","value":"ny"}]
```

## Why this exists

libpostal is a C library with roughly 2 GB of trained data, and its Python bindings
([`postal`](https://github.com/openvenues/pypostal)) must be compiled against a local build of that
library. That makes it impractical to install directly into application servers — especially ones
that aren't Python, or where the data files are larger than the application itself.

Running it once as a sidecar over HTTP solves that: a single image, one long-lived container, and any
number of applications in any language calling it over localhost or a private network.

The service is a deliberately thin transport. It adds no cleanup, normalisation, validation, or
correction on top of libpostal — all of that belongs in the caller, which knows its own address
conventions. See [Output contract](#output-contract).

## Quick start

```bash
docker run --rm -p 8080:8080 symetahybrid/libpostal-rest-py
```

First start takes a while: libpostal loads its trained data into memory before the server accepts
requests. Wait for uvicorn's `Application startup complete.` line.

Docker Compose:

```yaml
services:
  address-parser:
    image: symetahybrid/libpostal-rest-py:1.0.5
    restart: unless-stopped
    ports:
      - "127.0.0.1:8080:8080"
```

Pin a tag rather than `latest` — see [Versioning](#versioning-and-releases) for why that matters more
here than usual.

The image ships a `HEALTHCHECK`, so `docker ps` reports `health: starting` while the data loads and
`healthy` once requests are being served. Its `--start-period` is 180s; override it in Compose
(`healthcheck: start_period: 300s`) if your host is slower. Note that Docker's `restart` policy reacts
to process exit, not to health status — an unhealthy container is reported, not recycled. Use Swarm,
`depends_on: condition: service_healthy`, or an autoheal sidecar if you need that.

## API

Two `GET` endpoints. No authentication, no rate limiting, no state.

### `GET /parse`

Splits a free-text address into labelled components.

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| `query` | string | No | The address to parse. Omitted or empty → `200 []`. |

```bash
curl -s --get --data-urlencode 'query=781 Franklin Ave Crown Hts Brooklyn NY' localhost:8080/parse
```

```json
[
  {"label": "house_number", "value": "781"},
  {"label": "road",         "value": "franklin ave"},
  {"label": "suburb",       "value": "crown hts"},
  {"label": "city_district","value": "brooklyn"},
  {"label": "state",        "value": "ny"}
]
```

A flat list of `{"label", "value"}` objects in the order libpostal emitted them. Labels come straight
from libpostal — the set above is illustrative, not exhaustive; see
[libpostal's documented labels](https://github.com/openvenues/libpostal#parser-labels) for the full
vocabulary.

### `GET /expand`

Returns normalised variants of an address string — abbreviations expanded, casing and punctuation
regularised. Useful for deduplication and as a comparison key.

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| `query` | string | No | The address to expand. Omitted or empty → `200 []`. |

```bash
curl -s --get --data-urlencode 'query=One-Hundred and Twenty E 96th St' localhost:8080/expand
```

```json
["120 east 96th street", "120 east 96th saint"]
```

A bare array of strings.

### Empty query returns `200 []`

Both endpoints answer `200` with an empty array when `query` is absent, rather than the `422` a
validation error would normally produce. This is intentional: it lets a plain `GET` against either
endpoint double as a liveness probe without a dedicated health route, and without a query string that
a monitoring tool would have to know how to build.

Treat it as part of the contract. If you need to distinguish "no input" from "nothing found", check
before you call.

## Output contract

Callers depend on the response being raw libpostal output. Specifically:

- **Values are lowercase and otherwise untouched.** No trimming, title-casing, or spelling
  correction. Apply your own presentation layer.
- **Order is libpostal's token order,** not a canonical field order.
- **Duplicates are preserved.** A single address can legitimately produce two `road` entries — a unit
  or building name mis-labelled as a second street, for instance. Recovering that is the caller's
  job, and it can't be done if the service has already deduplicated.
- **Labels are whatever libpostal emits.** They are not filtered against an allow-list. If your logic
  only handles a subset, decide explicitly what to do with the rest.

The response is a list rather than an object for the duplicate case above. Reshaping it into
`{"road": ..., "city": ...}` loses information.

## Requirements

| | |
| --- | --- |
| Memory | ~2 GB resident, essentially all of it libpostal's data. Not tunable. |
| Image size | ~0.85 GB compressed, several GB on disk. Dominated by the trained data. |
| Startup | Slow — data is loaded into memory before the first request is served. |
| CPU | Parsing is single-threaded and holds Python's GIL, so one container parses one address at a time. |

Two consequences worth designing around:

- **Run one long-lived container.** Per-request or per-job container lifecycles pay the full data-load
  cost every time.
- **Scale with replicas, not workers.** Extra uvicorn workers each load their own copy of the data, so
  memory multiplies. If one container can't keep up, run several behind a load balancer — or cache
  results in the caller, which is usually cheaper, since real address workloads repeat heavily.

## Building from source

```bash
# Compiles libpostal and downloads ~2 GB of trained data; expect 10+ minutes
docker build -t libpostal-rest-py .

docker run --rm -p 8080:8080 libpostal-rest-py
```

### Multi-architecture

Published for `linux/amd64` and `linux/arm64`, so it runs natively on Apple Silicon and ARM servers
as well as x86 — no emulation, which matters for a CPU-bound C library.

```bash
docker buildx build --platform linux/arm64 -t libpostal-rest-py:arm64 .
```

libpostal's `configure` assumes SSE2 is available, so the Dockerfile branches on `TARGETARCH` and
passes `--disable-sse2` on arm64. Keep that branch if you fork the build.

### The libpostal version is pinned

libpostal is built from a pinned commit (`ARG LIBPOSTAL_REF` in the Dockerfile) rather than tracking
`master`. Upstream releases infrequently but commits regularly, and its label vocabulary and parse
results can shift between commits — so an unpinned build makes images unreproducible and can change
your parse output without any change on your side.

To move to the current upstream `master`:

```bash
make bump-libpostal   # rewrites ARG LIBPOSTAL_REF, prints a compare URL
```

Review the compare link, rebuild, and re-check the outputs your application relies on before
releasing. Note that the newest git tag is often *older* than `master`.

`postal` (the Python bindings) is pinned in `requirements.txt`, which is the single source of truth —
the Dockerfile reads the version from there when compiling the bindings against libpostal.

### Local development

Iterating on `app/main.py` alone doesn't need a Docker rebuild, but `pip install postal` requires
libpostal's C library and data present on the host first (`brew install libpostal`,
`sudo port install libpostal`, `apt install libpostal-dev`, or a source build):

```bash
pip install -r requirements.txt
uvicorn main:app --app-dir app --reload --port 8080
```

Be aware that a distribution-packaged libpostal is usually a tagged release, and therefore may differ
from the commit the image pins — parses can differ from the container's.

### Verifying a change

There is no test suite. Verification is curl against a running container:

```bash
curl -s --get --data-urlencode 'query=Vaartkom 31, 3000 Leuven, Belgium' localhost:8080/parse
curl -s --get --data-urlencode 'query=Vaartkom 31' localhost:8080/expand
curl -si 'localhost:8080/parse'  | head -1   # 200, body []
curl -si 'localhost:8080/expand' | head -1   # 200, body []
```

## Versioning and releases

Images are built and pushed by GitHub Actions when a GitHub release is **published** — merging to
`main` publishes nothing. The git tag becomes the image tag verbatim, so tags are bare semver with no
`v` prefix (`1.0.5`), pushed alongside `latest`.

Image tags track *this wrapper*, not libpostal. Two releases of this image can contain different
libpostal builds, which is exactly why pinning an image tag is worth doing: `latest` can change parse
behaviour underneath you.

## License

[MIT](LICENSE). libpostal and its trained data are distributed under their own license — see
[openvenues/libpostal](https://github.com/openvenues/libpostal).
