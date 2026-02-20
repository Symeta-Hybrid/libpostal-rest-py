# ---------- build stage ----------
FROM python:3.13-alpine AS build

RUN apk add --no-cache \
        build-base \
        autoconf \
        automake \
        libtool \
        pkgconfig \
        git \
        curl \
        tzdata

RUN git clone https://github.com/openvenues/libpostal
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

RUN pip install --no-cache-dir postal==1.1.11

# ---------- runtime stage ----------
FROM python:3.13-alpine

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

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080", "--log-level", "info"]
