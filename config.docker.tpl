{{ source "default.ikt" }}
{{ source "file:///infrakit/env.ikt" }}
[
  {
    "Plugin": "group",
    "Properties": {
      "ID": "amp-manager",
      "Properties": {
        "Allocation": {
          "LogicalIds": [
            "{{ ref "/m1/ip" }}",
            "{{ ref "/m2/ip" }}",
            "{{ ref "/m3/ip" }}"
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
                  "InitScriptTemplateURL": "{{ ref "/script/baseurl" }}/manager-init.sh",
                  "SwarmJoinIP": "{{ ref "/m1/ip" }}",
                  "Docker" : {
                    {{ if ref "/certificate/ca/service" }}"Host" : "tcp://{{ ref "/m1/ip" }}:{{ ref "/docker/remoteapi/tlsport" }}",
                    "TLS" : {
                      "CAFile": "{{ ref "/docker/remoteapi/cafile" }}",
                      "CertFile": "{{ ref "/docker/remoteapi/certfile" }}",
                      "KeyFile": "{{ ref "/docker/remoteapi/keyfile" }}",
                      "InsecureSkipVerify": false
                    }
                    {{ else }}"Host" : "tcp://{{ ref "/m1/ip" }}:{{ ref "/docker/remoteapi/port" }}"{{ end }}
                  }
                }
              }, {
                "Plugin": "flavor-vanilla",
                "Properties": {
                  "Init": [
                    "set -o errexit",
                    "docker network inspect {{ ref "/amp/network" }} 2>&1 | grep -q 'No such network'",
                    "docker network create -d overlay --attachable {{ ref "/amp/network" }}",
                    "docker service create --name amplifier --network {{ ref "/amp/network" }} {{ ref "/amp/amplifier/image" }}:{{ ref "/amp/amplifier/version" }}"
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
          "Size": 2
        },
        "Instance": {
          "Plugin": "instance-docker",
          "Properties": {
            "Config": {
              "Image": "docker:dind"
            },
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
                  "InitScriptTemplateURL": "{{ ref "/script/baseurl" }}/worker-init.sh",
                  "SwarmJoinIP": "{{ ref "/m1/ip" }}",
                  "Docker" : {
                    {{ if ref "/certificate/ca/service" }}"Host" : "tcp://{{ ref "/m1/ip" }}:{{ ref "/docker/remoteapi/tlsport" }}",
                    "TLS" : {
                      "CAFile": "{{ ref "/docker/remoteapi/cafile" }}",
                      "CertFile": "{{ ref "/docker/remoteapi/certfile" }}",
                      "KeyFile": "{{ ref "/docker/remoteapi/keyfile" }}",
                      "InsecureSkipVerify": false
                    }
                    {{ else }}"Host" : "tcp://{{ ref "/m1/ip" }}:{{ ref "/docker/remoteapi/port" }}"{{ end }}
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
