FROM debian:stable-slim AS base-builder
RUN echo 'Acquire::HTTP::Proxy "http://172.16.81.232:3142";' >> /etc/apt/apt.conf.d/01proxy \
    && echo 'Acquire::HTTPS::Proxy "false";' >> /etc/apt/apt.conf.d/01proxy
RUN apt-get update \
    && apt-get install -y build-essential \
                          cmake \
                          python3 \
                          python3-venv \
                          python3-sphinx \
                          python3-sphinx-rtd-theme \
                          ninja-build \
                          pkg-config \
                          libglib2.0-dev \
                          libfdt-dev \
                          libpixman-1-dev \
                          zlib1g-dev \
                          git \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

FROM base-builder AS qemu-builder
ARG QEMU_VERSION=v8.2.2
RUN git clone -b ${QEMU_VERSION} --depth 1 https://git.qemu.org/qemu.git /qemu
WORKDIR /qemu
RUN ./configure --target-list=arm-softmmu,aarch64-softmmu \
    && make -j$(nproc) \
    && cd build \
    && strip "arm-softmmu/qemu-system-arm" "aarch64-softmmu/qemu-system-aarch64" "qemu-img"

# Build stage for fatcat
FROM base-builder AS fatcat-builder
ARG FATCAT_VERSION=v1.1.0
RUN git clone -b ${FATCAT_VERSION} --depth 1 https://github.com/Gregwar/fatcat.git /fatcat
WORKDIR /fatcat
RUN mkdir build \
    && cd build \
    && cmake .. \
    && make

# Build the dockerpi VM image
FROM busybox:1.36 AS dockerpi-vm
LABEL maintainer="Michael Schmidt <schmidt.software@gmailcom>"
ARG RPI_KERNEL_URL="https://github.com/dhruvvyas90/qemu-rpi-kernel/archive/refs/heads/master.zip"

COPY --from=qemu-builder /qemu/build/arm-softmmu/qemu-system-arm /usr/local/bin/qemu-system-arm
COPY --from=qemu-builder /qemu/build/aarch64-softmmu/qemu-system-aarch64 /usr/local/bin/qemu-system-aarch64
COPY --from=qemu-builder /qemu/build/qemu-img /usr/local/bin/qemu-img
COPY --from=fatcat-builder /fatcat/build/fatcat /usr/local/bin/fatcat

ADD $RPI_KERNEL_URL /tmp/qemu-rpi-kernel.zip

RUN cd /tmp && \
    unzip qemu-rpi-kernel.zip && \
    mkdir -p /root/qemu-rpi-kernel && \
    cp qemu-rpi-kernel-*/kernel-qemu-5.10.63-bullseye /root/qemu-rpi-kernel/ && \
    cp qemu-rpi-kernel-*/versatile-pb.dtb /root/qemu-rpi-kernel/ && \
    rm -rf /tmp/*

VOLUME /sdcard

ADD ./entrypoint.sh /entrypoint.sh
ENTRYPOINT ["./entrypoint.sh"]


# Build the dockerpi image
# It's just the VM image with a compressed Raspbian filesystem added
FROM dockerpi-vm as dockerpi
LABEL maintainer="Michael Schmidt <schmidt.software@gmail.com>"
ARG FILESYSTEM_IMAGE_URL="https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2024-03-15/2024-03-15-raspios-bookworm-armhf-lite.img.xz"
ARG FILESYSTEM_IMAGE_CHECKSUM="4fa99737265ac338a9ed0643f502246b97b928e5dfffa92939242e26e290638d"

ADD $FILESYSTEM_IMAGE_URL /filesystem.zip

RUN echo "$FILESYSTEM_IMAGE_CHECKSUM  /filesystem.zip" | sha256sum -c
