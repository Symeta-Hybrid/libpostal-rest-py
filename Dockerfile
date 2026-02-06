# ---------- build stage ----------
FROM python:3.13-slim AS build

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC apt-get -y install \
    tzdata \
    autoconf automake build-essential \
    curl git libtool pkg-config \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/openvenues/libpostal
WORKDIR /libpostal

ARG TARGETARCH

RUN ./bootstrap.sh && \
    if [ "$TARGETARCH" = "arm64" ]; then \
        ./configure --disable-sse2 --datadir=/opt/libpostal/data; \
    else \
        ./configure --datadir=/opt/libpostal/data; \
    fi && \
    make && make install && ldconfig

RUN pip install postal==1.1.11

# ---------- runtime stage ----------
FROM python:3.13-slim

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC apt-get -y install tzdata && \
    rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/local /usr/local
COPY --from=build /opt/libpostal /opt/libpostal

# ensure linker can find libpostal
RUN ldconfig

WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ ./

EXPOSE 80
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "80", "--log-level", "info"]
