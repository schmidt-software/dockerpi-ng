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
                          wget \
                          xz-utils \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Build stage for qemu
FROM base-builder AS qemu-builder
ARG QEMU_VERSION=8.2.2
ENV QEMU_TARBALL="qemu-${QEMU_VERSION}.tar.xz"
WORKDIR /qemu
RUN wget "https://download.qemu.org/${QEMU_TARBALL}"
RUN tar xvf "${QEMU_TARBALL}"
WORKDIR /qemu/build
RUN "../qemu-${QEMU_VERSION}/configure" --static --disable-gio --target-list=arm-softmmu,aarch64-softmmu
RUN make -j$(nproc)
RUN strip "arm-softmmu/qemu-system-arm" "aarch64-softmmu/qemu-system-aarch64" "qemu-img"

# Build stage for fatcat
FROM base-builder AS fatcat-builder
ARG FATCAT_VERSION=v1.1.0
ENV FATCAT_TARBALL="${FATCAT_VERSION}.tar.gz"
WORKDIR /fatcat
RUN wget "https://github.com/Gregwar/fatcat/archive/${FATCAT_TARBALL}"
RUN tar xvf "${FATCAT_TARBALL}"
RUN cmake fatcat-* -DCMAKE_CXX_FLAGS='-static'
RUN make -j$(nproc)

# Build the dockerpi VM image
FROM busybox:1.36 AS dockerpi-ng-vm
LABEL maintainer="Michael Schmidt <schmidt.software@gmailcom>"
ARG RPI_KERNEL_URL="https://github.com/dhruvvyas90/qemu-rpi-kernel/archive/refs/heads/master.zip"

COPY --from=qemu-builder /qemu/build/arm-softmmu/qemu-system-arm /usr/local/bin/qemu-system-arm
COPY --from=qemu-builder /qemu/build/aarch64-softmmu/qemu-system-aarch64 /usr/local/bin/qemu-system-aarch64
COPY --from=qemu-builder /qemu/build/qemu-img /usr/local/bin/qemu-img
COPY --from=fatcat-builder /fatcat/fatcat /usr/local/bin/fatcat

ADD $RPI_KERNEL_URL /tmp/qemu-rpi-kernel.zip

RUN cd /tmp && \
    unzip qemu-rpi-kernel.zip && \
    mkdir -p /root/qemu-rpi-kernel && \
    cp qemu-rpi-kernel-*/kernel-qemu-5.10.63-bullseye /root/qemu-rpi-kernel/ && \
    cp qemu-rpi-kernel-*/versatile-pb.dtb /root/qemu-rpi-kernel/ && \
    rm -rf /tmp/*

VOLUME /sdcard

ADD ./entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]


# Build the dockerpi image
# It's just the VM image with a compressed Raspbian filesystem added
FROM dockerpi-ng-vm as dockerpi-ng
LABEL maintainer="Michael Schmidt <schmidt.software@gmail.com>"
ARG FILESYSTEM_IMAGE_URL="https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2024-03-15/2024-03-15-raspios-bookworm-armhf-lite.img.xz"
#ARG FILESYSTEM_IMAGE_CHECKSUM="4fa99737265ac338a9ed0643f502246b97b928e5dfffa92939242e26e290638d"

ADD $FILESYSTEM_IMAGE_URL /filesystem.img.xz

#RUN "$FILESYSTEM_IMAGE_CHECKSUM  /filesystem.zip" | sha256sum -c
