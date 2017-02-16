{{ source "default.ikt" }}
{{ source "env.ikt" }}
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
          "Plugin": "instance-aws",
          "Properties": {
            "RunInstancesInput": {
              "ImageId": "{{ ref "/aws/amiid" }}",
              "InstanceType": "{{ ref "/aws/instancetype" }}",
              "KeyName": "{{ ref "/aws/keyname" }}",
              "SubnetId": "{{ ref "/aws/subnetid" }}",
              "SecurityGroupIds": [ "{{ ref "/aws/securitygroupid" }}" ]
            },
            "Tags": {
              "Name": "{{ ref "/aws/stackname" }}-manager",
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
                  "InitScriptTemplateURL": "file://{{ ref "/infrakit/home" }}/manager-init.sh",
                  "SwarmJoinIP": "{{ ref "/m1/ip" }}",
                  "Docker" : {
                    "Host" : "tcp://{{ ref "/m1/ip" }}:2375"
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
          "Plugin": "instance-aws",
          "Properties": {
            "RunInstancesInput": {
              "ImageId": "{{ ref "/aws/amiid" }}",
              "InstanceType": "{{ ref "/aws/instancetype" }}",
              "KeyName": "{{ ref "/aws/keyname" }}",
              "SubnetId": "{{ ref "/aws/subnetid" }}",
              "SecurityGroupIds": [ "{{ ref "/aws/securitygroupid" }}" ]
            },
            "Tags": {
              "Name": "{{ ref "/aws/stackname" }}-worker",
              "Deployment": "Infrakit",
              "Role" : "worker"
            }
          }
        },
        "Flavor": {
          "Plugin": "flavor-swarm/worker",
          "Properties": {
            "InitScriptTemplateURL": "file://{{ ref "/infrakit/home" }}/worker-init.sh",
            "SwarmJoinIP": "{{ ref "/m1/ip" }}",
            "Docker" : {
              "Host" : "tcp://{{ ref "/m1/ip" }}:2375"
            }
          }
        }
      }
    }
  }
]
