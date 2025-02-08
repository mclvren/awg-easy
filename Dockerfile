# As a workaround we have to build on nodejs 18
# nodejs 20 hangs on build with armv6/armv7
FROM docker.io/library/node:18-alpine AS build_node_modules

# Copy Web UI
COPY src /app
WORKDIR /app
RUN npm ci --omit=dev &&\
    mv node_modules /node_modules
# Download & unpack AmneziaWG Tools
RUN wget -O amneziawg-tools.zip https://github.com/amnezia-vpn/amneziawg-tools/releases/latest/download/alpine-3.19-amneziawg-tools.zip &&\
    unzip -j -d /amneziawg-tools amneziawg-tools.zip

# Copy build result to a new image.
# This saves a lot of disk space.
FROM docker.io/library/node:lts-alpine
# Install Linux packages
RUN apk add --no-cache \
    dpkg \
    dumb-init \
    iptables \
    iptables-legacy \
    bash

# Use iptables-legacy
RUN update-alternatives --install /usr/sbin/iptables iptables /usr/sbin/iptables-legacy 10 --slave /usr/sbin/iptables-restore iptables-restore /usr/sbin/iptables-legacy-restore --slave /usr/sbin/iptables-save iptables-save /usr/sbin/iptables-legacy-save

# Copy AmneziaWG Tools
COPY --from=build_node_modules /amneziawg-tools/awg /usr/bin/awg
COPY --from=build_node_modules /amneziawg-tools/awg-quick /usr/bin/awg-quick
RUN chmod +x /usr/bin/awg
RUN chmod +x /usr/bin/awg-quick
# Fix not existing folder
RUN mkdir -p /etc/amnezia/amneziawg

# Copy the needed wg-password scripts
COPY --from=build_node_modules /app/wgpw.sh /bin/wgpw
RUN chmod +x /bin/wgpw

# Copy App
COPY --from=build_node_modules /app /app

# Move node_modules one directory up, so during development
# we don't have to mount it in a volume.
# This results in much faster reloading!
#
# Also, some node_modules might be native, and
# the architecture & OS of your development machine might differ
# than what runs inside of docker.
COPY --from=build_node_modules /node_modules /node_modules

# Set Environment
ENV DEBUG=Server,WireGuard
HEALTHCHECK CMD /usr/bin/timeout 5s /bin/sh -c "/usr/bin/awg show | /bin/grep -q interface || exit 1" --interval=1m --timeout=5s --retries=3

# Run Web UI
WORKDIR /app
CMD ["/usr/bin/dumb-init", "node", "server.js"]
