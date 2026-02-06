FROM python:3.13-slim

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC apt-get -y install tzdata && \
    apt-get install -y --no-install-recommends autoconf automake build-essential curl git libtool pkg-config \
    && apt-get clean \
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

RUN pip install postal

WORKDIR /app
COPY requirements.txt ./
COPY app/ ./

RUN pip install -r requirements.txt

EXPOSE 80

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "80", "--log-level", "info"]
