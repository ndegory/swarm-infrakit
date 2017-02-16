#!/bin/bash
set -o errexit
set -o nounset
set -o xtrace

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

{{/* Reload the engine labels */}}
kill -s HUP $(cat /var/run/docker.pid)
sleep 5

{{ if and ( eq INSTANCE_LOGICAL_ID SPEC.SwarmJoinIP ) (not SWARM_INITIALIZED) }}

  # Tell Docker to listen on port 2375 for remote API access. This is optional.
  mkdir -p /etc/systemd/system/docker.service.d
  cat > /etc/systemd/system/docker.service.d/docker.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H fd:// -H 0.0.0.0:2375 -H unix:///var/run/docker.sock
EOF

  # Restart Docker to let port listening take effect.
  systemctl daemon-reload
  systemctl restart docker.service

  {{/* The first node of the special allocations will initialize the swarm. */}}
  docker swarm init --advertise-addr {{ INSTANCE_LOGICAL_ID }}

{{ else }}

  {{/* The rest of the nodes will join as followers in the manager group. */}}
  docker swarm join --token {{ SWARM_JOIN_TOKENS.Manager }} {{ SWARM_MANAGER_ADDR }}

{{ end }}
