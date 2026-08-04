# ---------- build stage ----------
FROM python:3.14-alpine AS build

RUN apk add --no-cache \
        build-base \
        autoconf \
        automake \
        libtool \
        pkgconfig \
        git \
        curl \
        tzdata

# Pinned so a rebuild cannot silently change libpostal's label vocabulary — an unexpected
# label makes consumers discard the whole parse. Bump with `make bump-libpostal`.
ARG LIBPOSTAL_REF=25099c506612b34b23b1bfe286ca6321fcf06f35

RUN git clone https://github.com/openvenues/libpostal && \
    git -C libpostal checkout "$LIBPOSTAL_REF"
WORKDIR /libpostal

ARG TARGETARCH

RUN ./bootstrap.sh && \
    if [ "$TARGETARCH" = "arm64" ]; then \
        ./configure --disable-sse2 --datadir=/opt/libpostal/data; \
    else \
        ./configure --datadir=/opt/libpostal/data; \
    fi && \
    make -j$(nproc) && \
    make install

# Version comes from requirements.txt so there is exactly one place to bump. Must be built
# here, against the libpostal compiled above; the runtime stage has no compiler.
COPY requirements.txt /tmp/requirements.txt
RUN grep '^postal==' /tmp/requirements.txt | xargs pip install --no-cache-dir

# ---------- runtime stage ----------
FROM python:3.14-alpine

RUN apk add --no-cache tzdata

RUN addgroup -S appgroup && \
    adduser -S appuser -G appgroup

COPY --from=build /usr/local /usr/local
COPY --from=build /opt/libpostal /opt/libpostal

WORKDIR /app

COPY requirements.txt ./

RUN pip install --no-cache-dir -r requirements.txt

COPY --chown=appuser:appgroup app/ ./

USER appuser

EXPOSE 8080

# Empty query returns 200 [] without touching libpostal, so this only proves the server is up.
# start-period covers the data load into memory, which happens before the first request is served —
# without it a cold start reports unhealthy. No curl in the runtime image, hence stdlib.
HEALTHCHECK --interval=30s --timeout=5s --start-period=180s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/parse').read()"

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080", "--log-level", "info"]
