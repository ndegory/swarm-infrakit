#!/bin/bash
# @(#) starts infrakit and deploys the configuration
# @(#) if no argument is provided, the configuration is expected to be in $PWD

# Location of InfraKit templates
InfraKitConfigurationBaseURL=$1
# 
INFRAKIT_HOME=/infrakit
INFRAKIT_IMAGE=infrakit/devbundle:dev
INFRAKIT_AWS_IMAGE=infrakit/aws:dev
SSL_KEY_LENGTH=2048
CERTIFICATE_SERVER_IMAGE=ndegory/certauth:latest

docker pull $INFRAKIT_IMAGE || exit 1
docker pull $INFRAKIT_AWS_IMAGE || exit 1

# if a remote location is provided, the configuration will be searched there
if [ -n "$InfraKitConfigurationBaseURL" ]; then
  LOCAL_CONFIG=$INFRAKIT_HOME
  CONFIG_TPL=$InfraKitConfigurationBaseURL/config.tpl
  PLUGINS_CFG=$InfraKitConfigurationBaseURL/plugins.json
else
# or just use the local directory as the source
  LOCAL_CONFIG=$PWD
  CONFIG_TPL=file://$INFRAKIT_HOME/config.tpl
  PLUGINS_CFG=file://$INFRAKIT_HOME/plugins.json
fi
mkdir -p $LOCAL_CONFIG/logs $LOCAL_CONFIG/plugins $LOCAL_CONFIG/configs || exit 1

INFRAKIT_OPTIONS="-e INFRAKIT_HOME=$INFRAKIT_HOME -v $LOCAL_CONFIG:$INFRAKIT_HOME"
INFRAKIT_PLUGINS_OPTIONS="-v /var/run/docker.sock:/var/run/docker.sock -e INFRAKIT_PLUGINS_DIR=$INFRAKIT_HOME/plugins"

# get the local private IP, first with the AWS metadata service, and then a more standard way
IP=$(curl -m 3 169.254.169.254/latest/meta-data/local-ipv4) || IP=$(ip a show dev eth0 | grep inet | grep eth0 | tail -1 | sed -e 's/^.*inet.//g' -e 's/\/.*$//g')
if [ -z "$IP" ];then
	echo "Unable to guess the private IP"
	exit 1
fi

if [ ! -d ~/certificate.authority ]; then
	echo "Build a certificate management service..."
	pushd ~/
	git clone https://github.com/ndegory/certificate.authority.git
	pushd certificate.authority 2>/dev/null
	docker build -t $CERTIFICATE_SERVER_IMAGE . || exit 1
	popd -1 2>/dev/null && popd 2>/dev/null
fi

echo "Run the certificate management service..."
docker container ls | grep -qw certauth
if [ $? -ne 0 ]; then
  docker run -d --restart always -p 80 --name certauth $CERTIFICATE_SERVER_IMAGE || exit 1
fi
CERTIFICATE_SERVER_PORT=$(docker inspect certauth --format='{{(index (index .NetworkSettings.Ports "80/tcp") 0).HostPort}}')
echo "certificate server listening on port $CERTIFICATE_SERVER_PORT"
echo "{{ global \"/certificate/ca/service\" \"$IP:$CERTIFICATE_SERVER_PORT\" }}" >> $LOCAL_CONFIG/env.ikt

if [ ! -f /etc/docker/ca.pem ]; then
        echo "Generate a self-signed CA..."
        # (used by the Swarm flavor plugin)
	curl localhost:$CERTIFICATE_SERVER_PORT/ca > /etc/docker/ca.pem
        echo "Generate a certificate for the Docker client..."
	openssl genrsa -out /etc/docker/client-key.pem $SSL_KEY_LENGTH
	openssl req -subj '/CN=client' -new -key /etc/docker/client-key.pem -out /etc/docker/client.csr
	curl --data "csr=$(cat /etc/docker/client.csr | sed 's/+/%2B/g');ext=extendedKeyUsage=clientAuth" localhost:$CERTIFICATE_SERVER_PORT/csr > /etc/docker/client.pem
	ls -l /etc/docker/client.pem
	rm -f /etc/docker/client.csr
fi

echo "group" > $LOCAL_CONFIG/leader
docker container ls | grep -qw infrakit
if [ $? -ne 0 ]; then
    # cleanup
    rm -f $LOCAL_CONFIG/plugins/flavor-* $LOCAL_CONFIG/plugins/group*
    echo "start InfraKit..."
    docker run -d --restart always --name infrakit \
           -v /etc/docker:/etc/docker \
           $INFRAKIT_OPTIONS $INFRAKIT_PLUGINS_OPTIONS $INFRAKIT_IMAGE \
           infrakit plugin start --wait --config-url $PLUGINS_CFG --exec os --log 5 \
           manager group-stateless flavor-swarm flavor-vanilla flavor-combo
           sleep 3
fi

docker container ls | grep -qw instance-plugin
if [ $? -ne 0 ]; then
    # cleanup
    rm -f $LOCAL_CONFIG/plugins/instance-aws*
    echo "start InfraKit AWS plugin..."
    docker run -d --restart always --name instance-plugin \
           -v $LOCAL_CONFIG:/root/.infrakit $INFRAKIT_AWS_IMAGE \
           infrakit-instance-aws --log 5
    echo "wait for plugins to be ready..."
    sleep 5
fi

echo "prepare the InfraKit configuration file..."
docker run --rm $INFRAKIT_OPTIONS $INFRAKIT_IMAGE \
           infrakit template --url $CONFIG_TPL > $LOCAL_CONFIG/config.json
if [ $? -ne 0 ]; then
	echo "Failed"
	exit 1
fi

echo "deploy the configuration..."
docker run --rm $INFRAKIT_OPTIONS $INFRAKIT_PLUGINS_OPTIONS $INFRAKIT_IMAGE \
           infrakit manager commit file://$INFRAKIT_HOME/config.json
echo done
