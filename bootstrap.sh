#!/bin/bash
# @(#) starts infrakit and deploys the configuration
# @(#) if no argument is provided, the configuration is expected to be in $PWD


INFRAKIT_HOME=/infrakit
INFRAKIT_IMAGE_VERSION=${INFRAKIT_IMAGE_VERSION:-0.4.1}
INFRAKIT_INFRAKIT_IMAGE=infrakit/devbundle:$INFRAKIT_IMAGE_VERSION
INFRAKIT_AWS_IMAGE=infrakit/aws:$INFRAKIT_IMAGE_VERSION
INFRAKIT_DOCKER_IMAGE=infrakit/docker:dev
SSL_KEY_LENGTH=2048
CERTIFICATE_SERVER_IMAGE=ndegory/certauth:latest
CERT_DIR=~/.config/infrakit/certs
LOCAL_CONFIG=~/.config/infrakit/infrakit
INFRAKIT_OPTIONS="-e INFRAKIT_HOME=$INFRAKIT_HOME -v $LOCAL_CONFIG:$INFRAKIT_HOME"
INFRAKIT_PLUGINS_OPTIONS="-v /var/run/docker.sock:/var/run/docker.sock -e INFRAKIT_PLUGINS_DIR=$INFRAKIT_HOME/plugins"

# pull docker images
_pull_images() {
  local _images="infrakit $@"
  local _image
  local i
  for i in $_images; do
    _image=$(eval echo \$INFRAKIT_$(echo $i | tr '[:lower:]' '[:upper:]')_IMAGE)
    if [ -z "$_image" ]; then
      continue
    fi
    docker pull $_image
    if [ $? -ne 0 ]; then
      # fail back to locally generated image
      docker image ls $_image > /dev/null 2>&1
      if [ $? -ne 0 ]; then
        echo "no image with name $_image"
        exit 1
      fi
    fi
  done
}

# define and prepare the source directory
_set_source() {
  # Location of InfraKit templates
  InfraKitConfigurationBaseURL=$1
  mkdir -p $LOCAL_CONFIG || exit 1
  # if a remote location is provided, the configuration will be searched there
  if [ -n "$InfraKitConfigurationBaseURL" ]; then
    CONFIG_TPL=$InfraKitConfigurationBaseURL/config.$provider.tpl
    PLUGINS_CFG=$InfraKitConfigurationBaseURL/plugins.json
  else
  # or just use the local directory as the source
    cp bootstrap* *.sh *.tpl plugins.json *.ikt $LOCAL_CONFIG/
    CONFIG_TPL=file://$INFRAKIT_HOME/config.$provider.tpl
    PLUGINS_CFG=file://$INFRAKIT_HOME/plugins.json
  fi
  mkdir -p $LOCAL_CONFIG/logs $LOCAL_CONFIG/plugins $LOCAL_CONFIG/configs || exit 1
}

# sets the number of managers and workers
_set_size() {
  local _size=$1
  local _manager_size
  local _worker_size
  if [ $_size -gt 3 ]; then
    _manager_size=3
  else
    _manager_size=1
  fi
  _worker_size=$((_size - _manager_size))
  echo "$_manager_size managers and $_worker_size workers"
  echo "{{ global \"/swarm/size/manager\" \"$_manager_size\" }}" >> $LOCAL_CONFIG/env.ikt
  echo "{{ global \"/swarm/size/worker\" \"$_worker_size\" }}" >> $LOCAL_CONFIG/env.ikt
}

# run a certificate signing service
_run_certificate_service() {
  local IP
  # get the local private IP, first with the AWS metadata service, and then a more standard way
  IP=$(curl -m 3 169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null) || IP=$(ip a show dev eth0 2>/dev/null | grep inet | grep eth0 | tail -1 | sed -e 's/^.*inet.//g' -e 's/\/.*$//g')
  if [ -z "$IP" ];then
    IP=$(ifconfig $(netstat -nr | awk 'NF==6 && $1 ~/default/ {print $6}' | tail -1) | awk '$1 == "inet" {print $2}')
  fi
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
  docker container ls --format '{{.Names}}' | grep -qw certauth
  if [ $? -ne 0 ]; then
    echo "Run the certificate management service..."
    docker run -d --restart always -p 80 --name certauth $CERTIFICATE_SERVER_IMAGE || exit 1
  else
    echo "The certificate management service is already running"
  fi
  CERTIFICATE_SERVER_PORT=$(docker inspect certauth --format='{{(index (index .NetworkSettings.Ports "80/tcp") 0).HostPort}}')
  echo "certificate server listening on port $CERTIFICATE_SERVER_PORT"
  echo "{{ global \"/certificate/ca/service\" \"$IP:$CERTIFICATE_SERVER_PORT\" }}" >> $LOCAL_CONFIG/env.ikt
}

# generate a certificate for the Docker client
_get_client_certificate() {
  mkdir -p $CERT_DIR
  if [ $? -ne 0 ]; then
    exit 1
  fi
  if [ ! -f $CERT_DIR/ca.pem ]; then
    echo "Generate a self-signed CA..."
    # (used by the Swarm flavor plugin)
    curl localhost:$CERTIFICATE_SERVER_PORT/ca > $CERT_DIR/ca.pem
    echo "Generate a certificate for the Docker client..."
    openssl genrsa -out $CERT_DIR/client-key.pem $SSL_KEY_LENGTH
    openssl req -subj '/CN=client' -new -key $CERT_DIR/client-key.pem -out $CERT_DIR/client.csr
    curl --data "csr=$(cat $CERT_DIR/client.csr | sed 's/+/%2B/g');ext=extendedKeyUsage=clientAuth" localhost:$CERTIFICATE_SERVER_PORT/csr > $CERT_DIR/client.pem
    ls -l $CERT_DIR/client.pem
    rm -f $CERT_DIR/client.csr
  fi
}

# run the infrakit containers
# return 1 if a new container has been started
_run_ikt() {
  local _should_wait_for_plugins=0
  echo "group" > $LOCAL_CONFIG/leader
  docker container ls --format '{{.Names}}' | grep -qw infrakit
  if [ $? -ne 0 ]; then
    # cleanup
    rm -f $LOCAL_CONFIG/plugins/flavor-* $LOCAL_CONFIG/plugins/group*
    if [ "x$provider" = "xdocker" ]; then
        local _network=hostnet
        docker network create -d bridge --attachable $_network 2>/dev/null
        INFRAKIT_OPTIONS="$INFRAKIT_OPTIONS --network $_network"
    fi
    echo "Starting up InfraKit"
    docker run -d --restart always --name infrakit \
           -v $CERT_DIR:/etc/docker \
           $INFRAKIT_OPTIONS $INFRAKIT_PLUGINS_OPTIONS $INFRAKIT_INFRAKIT_IMAGE \
           infrakit plugin start --wait --config-url $PLUGINS_CFG --exec os --log 5 \
           manager group-stateless flavor-swarm flavor-vanilla flavor-combo
           _should_wait_for_plugins=1
  else
    echo "InfraKit container is already started"
  fi
  return $_should_wait_for_plugins
}

# run an infrakit plugin
# return 1 if a new plugin has been started
_run_ikt_plugin() {
  local _should_wait_for_plugins=0
  local _exception_list="vagrant terraform"
  local _plugin
  local _infrakit
  local _binary
  for _plugin in $_exception_list; do
    echo $@ | grep -q $_plugin
    if [ $? -eq 0 ]; then
      # can't run in the container, start it with the binary
      PATH=$PATH:$GOPATH/bin:$GOPATH/src/github.com/docker/infrakit/build
      _binary=$(which infrakit-instance-$_plugin 2>/dev/null)
      if [ -z "$_binary" ]; then
        echo "can't find the infrakit-instance-$_plugin binary, abort"
        exit 1
      fi
      if [ ! -x "$_binary" ]; then
        echo "the infrakit-instance-$_plugin binary is not executable, abort"
        exit 1
      fi
      _infrakit=$(which infrakit 2>/dev/null)
      if [ -z "$_infrakit" ]; then
        echo "can't find the infrakit binary, abort"
        exit 1
      fi
      if [ ! -x "$_infrakit" ]; then
        echo "the infrakit binary is not executable, abort"
        exit 1
      fi
      which $_plugin >/dev/null 2>&1
      if [ $? -ne 0 ]; then
        echo "WARNING - can't find the $_plugin binary"
      fi
      local _plugins_cfg=$PLUGINS_CFG
      echo $PLUGINS_CFG | grep -q "file://" && _plugins_cfg="file://$LOCAL_CONFIG/plugins.json"
      ps aux | grep -q [i]nfrakit-instance-$_plugin
      if [ $? -ne 0 ]; then
        # first, cleanup the pid and socket files
        rm -f $LOCAL_CONFIG/plugins/instance-${_plugin}*
        #INFRAKIT_HOME=$LOCAL_CONFIG INFRAKIT_PLUGINS_DIR=$LOCAL_CONFIG/plugins infrakit-instance-$_plugin --log 5 > $LOCAL_CONFIG/logs/instance-$_plugin.log 2>&1 &
        INFRAKIT_HOME=$LOCAL_CONFIG INFRAKIT_PLUGINS_DIR=$LOCAL_CONFIG/plugins ${_infrakit} plugin start --wait --config-url $_plugins_cfg --exec os --log 0 instance-$_plugin &
        _should_wait_for_plugins=1
        # we want the Docker container to be able to talk to the plugin, so fix the permission for that
        local _rc=1
        local _loop=0
        while [ $_rc -ne 0 ]; do
          chmod a+w $LOCAL_CONFIG/plugins/instance-${_plugin} 2>/dev/null
          _rc=$?
          if [ $((loop+1)) -gt 10 ]; then
            echo "Failed to change the socket permission for plugin $_plugin"
            break
          fi
          sleep 1
        done
      else
        echo "$_plugin is already started"
      fi
    fi
  done
  local _image
  for _plugin in $@; do
    echo $_exception_list | grep -qw $_plugin
    if [ $? -ne 0 ]; then
      docker container ls --format '{{.Names}}' | grep -qw instance-plugin-$_plugin
      if [ $? -ne 0 ]; then
        # first, cleanup the pid and socket files
        rm -f $LOCAL_CONFIG/plugins/instance-${_plugin}*
        _image=$(eval echo \${INFRAKIT_$(echo $_plugin | tr '[:lower:]' '[:upper:]')_IMAGE})
        if [ -z "$_image" ]; then
            echo "no image defined for plugin $_plugin"
            exit 1
        fi
        if [ "$_plugin" = "docker" ]; then
            local _network=hostnet
            INFRAKIT_OPTIONS="$INFRAKIT_OPTIONS --network $_network"
        fi
        echo "Starting up InfraKit $_plugin plugin (image $_image)..."
        docker run -d --restart always --name instance-plugin-$_plugin \
             $INFRAKIT_OPTIONS $INFRAKIT_PLUGINS_OPTIONS $_image \
             infrakit-instance-$_plugin --log 5
        if [ $? -ne 0 ]; then
            echo "Unable to start the $_plugin plugin"
            exit 1
        fi
        _should_wait_for_plugins=1
      else
        echo "$_plugin container is already running"
      fi
    fi
  done
  return $_should_wait_for_plugins
}

# destroy the instances managed by infrakit
_destroy_groups() {
  local _groups
  local _group
  _groups=$(docker exec infrakit infrakit group ls 2>/dev/null | tail -n +2)
  for _group in $_groups; do
    grep -q "\"$_group\"" $LOCAL_CONFIG/config.json
    if [ $? -eq 0 ]; then
      docker exec infrakit infrakit group destroy $_group
    fi
  done
}

# kill the infrakit container
_kill_ikt() {
  docker container rm -f infrakit >/dev/null 2>&1 && echo "infrakit container has been removed"
}

# kill the infrakit plugins (container or process)
_kill_plugins() {
  local _plugin
  for _plugin in $VALID_PROVIDERS; do
    docker container rm -f instance-plugin-$_plugin 2>/dev/null || killall infrakit-instance-$_plugin 2>/dev/null && echo "$_plugin plugin has been stopped"
  done
  killall infrakit 2>/dev/null
}

# removes the configuration files
_clean_config() {
  if [ -f $LOCAL_CONFIG/config.json ]; then
    rm -f $LOCAL_CONFIG/config.json
    echo "config.json has been removed"
  fi
  if [ -f $LOCAL_CONFIG/env.ikt ]; then
    rm -f $LOCAL_CONFIG/env.ikt
    echo "env.ikt has been removed"
  fi
}

# convert the template of the configuration file
_prepare_config() {
  echo "prepare the InfraKit configuration file..."
  docker exec infrakit infrakit template --log 5 --url $CONFIG_TPL > $LOCAL_CONFIG/config.json
  if [ $? -ne 0 ]; then
    echo "Failed, template URL was $CONFIG_TPL"
    exit 1
  fi
}

# deploy the infrakit configuration
_deploy_config() {
  echo "deploy the configuration..."
  docker exec infrakit infrakit manager commit file://$INFRAKIT_HOME/config.json
}

VALID_PROVIDERS="aws docker terraform vagrant"
provider=docker
pull=1
clustersize=5
clean=0
while getopts ":p:n:hfc" opt; do
  case $opt in
  n)
      clustersize=$OPTARG
      ;;
  p)
      provider=""
      echo "$VALID_PROVIDERS" | grep -wq "$OPTARG" && provider=$OPTARG
      if [ -z "$provider" ]; then
          echo "Valid providers are $VALID_PROVIDERS"
          exit 1
      fi
      ;;
  h)
      echo "Usage: $(basename $0) [-p provider] [-n cluster size] [-f] [-h]"
      exit 0
      ;;
  f)
      # don't pull images
      pull=0
      ;;
  c)
      clean=1
      ;;
  \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done
shift "$((OPTIND-1))"

if [ $clean -eq 1 ]; then
  _destroy_groups
  _kill_plugins
  _kill_ikt
  _clean_config
  exit
fi
if [ $pull -eq 1 ]; then
  _pull_images $provider
fi
_set_source $1
_set_size $clustersize
if [ "$provider" != "docker" ]; then _run_certificate_service; fi
_get_client_certificate
_run_ikt
started=$?
_run_ikt_plugin $provider
started=$((started + $?))
if [ $started -gt 0 ]; then echo "waiting for plugins to be available..."; sleep 5; fi
_prepare_config
_deploy_config
echo done
