#!/bin/bash
set -o errexit
set -o nounset
set -o xtrace

{{ source "default.ikt" }}
{{ source "env.ikt" }}
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

  {{ if not ( eq 0 (len (ref "/certificate/ca/service"))) }}
  # get a certificate
  # prepare the CSR with subject alt names
  cfg=$(mktemp)
  cp /etc/ssl/openssl.cnf $cfg
  sed -i '/^\[ req \]$/ a\
req_extensions = v3_req' $cfg
  sed -i '/^\[ v3_req \]$/ a\
subjectAltName          = @alternate_names' $cfg
  cat >> $cfg << EOF

[ alternate_names ]
DNS.1       = $(hostname -f)
DNS.2       = $(hostname)
IP.1       = 192.168.2.200
EOF
  cacfg=$(mktemp)
  cat >> $cacfg << EOF

basicConstraints=CA:FALSE
subjectAltName          = @alternate_names
subjectKeyIdentifier = hash

[ alternate_names ]
DNS.1       = $(hostname -f)
DNS.2       = $(hostname)
IP.1       = 192.168.2.200
EOF

  openssl genrsa -out {{ ref "/docker/remoteapi/srvkeyfile" }} 2048 || exit 1
  openssl req -subj "/CN=$(hostname)" -sha256 -new -key {{ ref "/docker/remoteapi/srvkeyfile" }} -out {{ ref "/docker/remoteapi/srvcertfile" }}.csr || exit 1
  curl --data "csr=$(sed 's/+/%2B/g' {{ ref "/docker/remoteapi/srvcertfile" }}.csr);ext=$(cat $cacfg)"  {{ ref "/certificate/ca/service" }}/csr > {{ ref "/docker/remoteapi/srvcertfile" }}
  curl {{ ref "/certificate/ca/service" }}/ca > {{ ref "/docker/remoteapi/cafile" }}
  rm -f {{ ref "/docker/remoteapi/srvcertfile" }}.csr $cfg $cacfg
  {{ end }}
  
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
