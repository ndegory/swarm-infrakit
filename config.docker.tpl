{{ source "default.ikt" }}
{{ source "file:///infrakit/env.ikt" }}
{{ $workerSize := ref "/swarm/size/worker" }}
[
  {
    "Plugin": "group",
    "Properties": {
      "ID": "amp-manager",
      "Properties": {
        "Allocation": {
          "LogicalIds": [
            "m1",
            "m2",
            "m3"
          ]
        },
        "Instance": {
          "Plugin": "instance-docker",
          "Properties": {
            "Config": {
              "Image": "docker:dind"
            },
            "HostConfig": {
              "Privileged": true
            },
            "NetworkAttachments": [
              {
                "Name": "hostnet"
              }
            ],
            "Tags": {
              "Name": "manager",
              "Deployment": "Infrakit",
              "Role" : "manager"
            }
          }
        },
        "Flavor": {
          "Plugin": "flavor-combo",
          "Properties": {
            "Flavors": [
              {
                "Plugin": "flavor-swarm/manager",
                "Properties": {
                  "InitScriptTemplateURL": "{{ ref "/script/baseurl" }}/manager-init.tpl",
                  "SwarmJoinIP": "m1",
                  "Docker" : {
                    {{ if ref "/certificate/ca/service" }}"Host" : "tcp://m1:{{ ref "/docker/remoteapi/tlsport" }}",
                    "TLS" : {
                      "CAFile": "{{ ref "/docker/remoteapi/cafile" }}",
                      "CertFile": "{{ ref "/docker/remoteapi/certfile" }}",
                      "KeyFile": "{{ ref "/docker/remoteapi/keyfile" }}",
                      "InsecureSkipVerify": false
                    }
                    {{ else }}"Host" : "tcp://m1:{{ ref "/docker/remoteapi/port" }}"{{ end }}
                  }
                }
              }, {
                "Plugin": "flavor-vanilla",
                "Properties": {
                  "Init": [
                    "set -o errexit",
                    "docker network inspect {{ ref "/amp/network" }} 2>&1 | grep -q 'No such network' && \\",
                    "  docker network create -d overlay --attachable {{ ref "/amp/network" }}",
                    "docker service ls {{ ref "/amp/network" }} 2>&1 | grep -q 'No such network' && \\",
                    "docker service create --name amplifier --network {{ ref "/amp/network" }} {{ ref "/amp/amplifier/image" }}:{{ ref "/amp/amplifier/version" }} || true"
                  ]
                }
              }
            ]
          }
        }
      }
    }
  },
  {
    "Plugin": "group",
    "Properties": {
      "ID": "amp-worker",
      "Properties": {
        "Allocation": {
          "Size": {{ $workerSize }}
        },
        "Instance": {
          "Plugin": "instance-docker",
          "Properties": {
            "Config": {
              "Image": "docker:dind"
            },
            "HostConfig": {
              "Privileged": true
            },
            "NetworkAttachments": [
              {
                "Name": "hostnet"
              }
            ],
            "Tags": {
              "Name": "worker",
              "Deployment": "Infrakit",
              "Role" : "worker"
            }
          }
        },
        "Flavor": {
          "Plugin": "flavor-combo",
          "Properties": {
            "Flavors": [
              {
                "Plugin": "flavor-swarm/worker",
                "Properties": {
                  "InitScriptTemplateURL": "{{ ref "/script/baseurl" }}/worker-init.tpl",
                  "SwarmJoinIP": "m1",
                  "Docker" : {
                    {{ if ref "/certificate/ca/service" }}"Host" : "tcp://m1:{{ ref "/docker/remoteapi/tlsport" }}",
                    "TLS" : {
                      "CAFile": "{{ ref "/docker/remoteapi/cafile" }}",
                      "CertFile": "{{ ref "/docker/remoteapi/certfile" }}",
                      "KeyFile": "{{ ref "/docker/remoteapi/keyfile" }}",
                      "InsecureSkipVerify": false
                    }
                    {{ else }}"Host" : "tcp://m1:{{ ref "/docker/remoteapi/port" }}"{{ end }}
                  }
                }
              }
            ]
          }
        }
      }
    }
  }
]
