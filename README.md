# Deploy a Docker Swarm cluster with InfraKit

## Bootstrap

First, the cluster should be bootstrapped to get InfraKit running and ready to deploy the Swarm cluster.

Available bootstraps:

#### AWS

The Cloudformation template ```bootstrap.yml``` creates a VPC, subnet, internet gateway and the minimum required to build EC2 instances.
Select the instance type and the name of the EC2 Key pair name.
One EC2 instance will be created and will run InfraKit, it's public IP is revealed in the Cloudformation outputs.

#### DigitalOcean

Coming soon

#### Docker in Docker

Coming soon

## Deploy

The InfraKit instance will render the ```config.tpl``` template, and watch the resulting file (config.json).
The result will be the full Swarm cluster.

## Security

To be implemented
