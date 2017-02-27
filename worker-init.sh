#!/bin/sh
set -o errexit
set -o nounset
set -o xtrace

{{ source "default.ikt" }}
{{ source "file:///infrakit/env.ikt" }}
{{ include "install-docker.sh" }}
{{ source "attach-ebs-volume.sh" }}

# Use an EBS volume for the devicemapper
systemctl stop docker.service
rm -rf /var/lib/docker
_attach_ebs_volume /dev/sdn /var/lib/docker "Docker AUFS" {{ ref "/docker/aufs/size" }}

mkdir -p /etc/docker
cat << EOF > /etc/docker/daemon.json
{
  "labels": {{ INFRAKIT_LABELS | to_json }}
}
EOF

{{ if not ( eq 0 (len (ref "/certificate/ca/service"))) }}{{ include "request-certificate.sh" }}{{ end }}

systemctl start docker.service
sleep 2

docker swarm join --token {{  SWARM_JOIN_TOKENS.Worker }} {{ SWARM_MANAGER_ADDR }}
