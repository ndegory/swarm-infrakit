#!/bin/bash
set -o errexit
set -o nounset
set -o xtrace

{{ source "default.ikt" }}
{{ source "file:///infrakit/env.ikt" }}
{{ include "install-docker.sh" }}
{{ source "attach-ebs-volume.sh" }}
{{ source "provider.sh" }}

# Use an EBS volume for the devicemapper
systemctl stop docker.service
if [ "x$provider" = "xaws" ]; then
  rm -rf /var/lib/docker
  _attach_ebs_volume /dev/sdn /var/lib/docker "Docker AUFS" {{ ref "/docker/aufs/size" }}
fi

mkdir -p /etc/docker
cat << EOF > /etc/docker/daemon.json
{
  "labels": {{ INFRAKIT_LABELS | to_json }}
}
EOF

systemctl start docker.service
sleep 2

{{ if not ( eq 0 (len (ref "/certificate/ca/service"))) }}{{ include "request-certificate.sh" }}{{ end }}

{{ if and ( eq INSTANCE_LOGICAL_ID SPEC.SwarmJoinIP ) (not SWARM_INITIALIZED) }}
  mkdir -p /etc/systemd/system/docker.service.d
  cat > /etc/systemd/system/docker.service.d/docker.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H fd:// -H 0.0.0.0:{{ if not (eq 0 (len (ref "/certificate/ca/service"))) }}{{ ref "/docker/remoteapi/tlsport" }} --tlsverify --tlscacert={{ ref "/docker/remoteapi/cafile" }} --tlscert={{ ref "/docker/remoteapi/srvcertfile" }} --tlskey={{ ref "/docker/remoteapi/srvkeyfile" }}{{else }}{{ ref "/docker/remoteapi/port" }}{{ end }} -H unix:///var/run/docker.sock
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
