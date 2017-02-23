#!/bin/sh
set -o errexit
set -o nounset
set -o xtrace

{{ source "default.ikt" }}
{{ source "file:///infrakit/env.ikt" }}
{{ include "install-docker.sh" }}

wget -qO- https://get.docker.com/ | sh
usermod -G docker ubuntu
systemctl enable docker.service
systemctl start docker.service

mkdir -p /etc/docker
cat << EOF > /etc/docker/daemon.json
{
  "labels": {{ INFRAKIT_LABELS | to_json }}
}
EOF

{{ if not ( eq 0 (len (ref "/certificate/ca/service"))) }}{{ include "request-certificate.sh" }}{{ end }}

# Tell engine to reload labels
kill -s HUP $(cat /var/run/docker.pid)

sleep 5

docker swarm join --token {{  SWARM_JOIN_TOKENS.Worker }} {{ SWARM_MANAGER_ADDR }}
