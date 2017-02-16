#!/bin/bash
# @(#) starts infrakit and deploys the configuration
# @(#) if no argument is provided, the configuration is expected to be $PWD


InfraKitConfigurationBaseURL=$1
INFRAKIT_HOME=/infrakit
INFRAKIT_IMAGE=infrakit/devbundle:dev
INFRAKIT_AWS_IMAGE=infrakit/aws:dev

docker pull $INFRAKIT_IMAGE
docker pull $INFRAKIT_AWS_IMAGE

if [ -n "$InfraKitConfigurationBaseURL" ]; then
  LOCAL_CONFIG=$INFRAKIT_HOME
  mkdir  -p $INFRAKIT_HOME
  # fetch the sources
  for f in default.ikt config.tpl manager-init.sh worker-init.sh plugins.json; do
    echo -n "fetching $f... "
    curl -Ls ${InfraKitConfigurationBaseURL}/$f -o $LOCAL_CONFIG/$f && echo "done" || echo "failed"
  done
else
  LOCAL_CONFIG=$PWD
fi
mkdir -p $LOCAL_CONFIG/logs $LOCAL_CONFIG/plugins $LOCAL_CONFIG/configs

INFRAKIT_OPTIONS="-e INFRAKIT_HOME=$INFRAKIT_HOME -v $LOCAL_CONFIG:$INFRAKIT_HOME"
INFRAKIT_PLUGINS_OPTIONS="-v /var/run/docker.sock:/var/run/docker.sock -e INFRAKIT_PLUGINS_DIR=$INFRAKIT_HOME/plugins"

echo "start InfraKit..."
echo "group" > $LOCAL_CONFIG/leader
docker run -d --restart always --name infrakit \
           $INFRAKIT_OPTIONS $INFRAKIT_PLUGINS_OPTIONS $INFRAKIT_IMAGE \
           infrakit plugin start --wait --config-url file://$INFRAKIT_HOME/plugins.json --exec os --log 5 \
           manager group-stateless flavor-swarm flavor-vanilla flavor-combo

echo "start InfraKit AWS plugin..."
docker run -d --restart always --name instance-plugin \
           -v $LOCAL_CONFIG:/root/.infrakit $INFRAKIT_AWS_IMAGE \
           infrakit-instance-aws --log 5

echo "wait for plugins to be ready..."
sleep 10

echo "prepare the InfraKit configuration file..."
docker run --rm $INFRAKIT_OPTIONS $INFRAKIT_IMAGE \
           infrakit template --url file://$INFRAKIT_HOME/config.tpl > $LOCAL_CONFIG/config.json

echo "deploy the configuration..."
docker run --rm $INFRAKIT_OPTIONS $INFRAKIT_PLUGINS_OPTIONS $INFRAKIT_IMAGE \
           infrakit manager commit file://$INFRAKIT_HOME/config.json
echo done
