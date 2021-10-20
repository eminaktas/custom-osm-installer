#!/bin/bash
# Local OSM installer
# This installer is created based on OSM's installer here: https://osm.etsi.org/docs/user-guide/03-installing-osm.html#installation-options 
# maintaner: Emin Aktaş <emin.aktas@ulakhaberlesme.com.tr

USERNAME=`whoami`
# Check if the user is the root or not, if not use sudo
[ "$USERNAME" != "root" ] && SUDO="sudo" && echo -e "Commands are going to run with sudo"

function usage() {
    echo -e "usage: $0 [OPTIONS]"
    echo -e "Install OSM from binaries or source code (by default, from binaries)"
    echo -e "  OPTIONS"
    echo -e "     -h / --help               :    print this help"
    echo -e "     -y / --yes                :    do not prompt for confirmation, assumes yes"
    echo -e "     -O <orchestrator>         :    deploy osm services using container <orchestrator>. Valid value is 'k8s'.  If -o is not used then osm will be deployed using default orchestrator. When used with --uninstall, osm services deployed by the orchestrator will be uninstalled"
    echo -e "     -c <cri-name>             :    CRI name. Currently, docker and containerd is supported. To enable containerd type containerd (by default, docker)"
    echo -e "     -H <vca-host>             :    use specific juju host controller IP"
    echo -e "     -r <repo>                 :    use specified repository name for osm packages"
    echo -e "     -R <release>              :    use specified release for osm binaries (deb packages, lxd images, ...)"
    echo -e "     -u <repo-base>            :    use specified repository url for osm packages"
    echo -e "     -k <repo-key>             :    use specified repository public key url"
    echo -e "     -D <devops-path>          :    use local devops installation path"
    echo -e "     -t <docker-tag>           :    specify osm docker tag (default is latest)"
    echo -e "     -n <namespace>            :    user defined namespace when installed using k8s, default is osm"
    echo -e "     -K <juju-controller>      :    specifies the name of the controller to use - The controller must be already bootstrapped"
    echo -e "     -l <lxd-cloud>            :    LXD cloud yaml file"
    echo -e "     -L <lxd-credentials>      :    LXD credentials yaml file"
    echo -e "     --pla                     :    install the PLA module for placement support"
    echo -e "     --nolxd                   :    do not install and configure LXD (assumes LXD is already installed and configured)"
    echo -e "     --nojuju                  :    do not install juju, assumes already installed"
    echo -e "     --nocachelxdimages        :    do not cache local lxd images, do not create cronjob for that cache (will save installation time, might affect instantiation time)"  
    echo -e "     --deploy-charmed-services :    deploy the charmed services if this argumament not passed it will deploy it as it is"
    echo -e "     --uninstall               :    removes OSM and everything installed for it"
}

function ask_user() {
    # Asks to the user and parse a response among 'y', 'yes', 'n' or 'no'.
    read -e -p "$1" USER_CONFIRMATION
    while true ; do
        [ -z "$USER_CONFIRMATION" ] && [ "$2" == 'y' ] && return 0
        [ -z "$USER_CONFIRMATION" ] && [ "$2" == 'n' ] && return 1
        [ "${USER_CONFIRMATION,,}" == "yes" ] || [ "${USER_CONFIRMATION,,}" == "y" ] && return 0
        [ "${USER_CONFIRMATION,,}" == "no" ]  || [ "${USER_CONFIRMATION,,}" == "n" ] && return 1
        read -e -p "Please type 'yes' or 'no': " USER_CONFIRMATION
    done
}

function add_repo() {
    # Appends given repository address to the repository file.
    # If donotremove is not passed, it will remove the repository file.
    if [ "$2" != "donotremove" ] && [ -f "$REPO_PATH" ];
    then
        echo -e "Removing old repository file($REPO_PATH)"
        $SUDO rm $REPO_PATH
    fi
    echo -e "Adding repository in $REPO_PATH"
    wget -qO - $REPOSITORY_BASE/$RELEASE/$REPOSITORY_KEY| sudo apt-key add -
    $SUDO echo "$1" | $SUDO tee -a $REPO_PATH
}

function FATAL() {
    # Exists the program when this function is called
    echo "FATAL error: Cannot install OSM due to \"$1\""
    exit 1
}

function install_required_packages() {
    # Installs required packages.
    # Those packages are needed for this program to run successfully.
    echo -e "Checking if required packages are installed in the enviroment."
    $SUDO dpkg -l $REQUIRED_PACKAGES &>/dev/null \
    || echo -e "One or more required packages are not installed. Updating and installing packages." \
    && $SUDO apt-get update \
    && $SUDO apt-get install -y $REQUIRED_PACKAGES
    echo -e "Setting up the enviroment done!"
}

function get_default_if_ip_mtu() {
    # Finds and define default interface, ip and mtu variables
    echo -e "Getting default interface, its ip and mtu"
    DEFAULT_IF=$(ip route list|awk '$1=="default" {print $5; exit}')
    [ -z "$DEFAULT_IF" ] && DEFAULT_IF=$(route -n |awk '$1~/^0.0.0.0/ {print $8; exit}')
    [ -z "$DEFAULT_IF" ] && FATAL "Not possible to determine the interface with the default route 0.0.0.0"
    DEFAULT_IP=`ip -o -4 a s ${DEFAULT_IF} |awk '{split($4,a,"/"); print a[1]}'`
    [ -z "$DEFAULT_IP" ] && FATAL "Not possible to determine the IP address of the interface with the default route"
    DEFAULT_MTU=$(ip addr show ${DEFAULT_IF} | perl -ne 'if (/mtu\s(\d+)/) {print $1;}')
    echo -e "Getting default inetface, its ip and mtu done! \nDEFAULT_IF: $DEFAULT_IF, DEFAULT_IP: $DEFAULT_IP, DEFAULT_MTU, $DEFAULT_MTU"
}

function install_lxd() {
    # Installs LXD if not installed.
    echo -e "Installing lxd"
    # Apply sysctl production values for optimal performance
    $SUDO cp ${OSM_DEVOPS}/installers/60-lxd-production.conf /etc/sysctl.d/60-lxd-production.conf
    $SUDO sysctl --system
    
    # Install LXD
    $SUDO dpkg -l $LXD_REQUIRED_PACKAGES &>/dev/null \
    || echo -e "One or more required packages are not installed. Updating and installing packages." \
    && $SUDO apt-get update \
    && $SUDO apt-get install -y $LXD_REQUIRED_PACKAGES

    # Configure LXD
    [ "$USERNAME" != "root" ] && sudo usermod -a -G lxd $USERNAME
    cat ${OSM_DEVOPS}/installers/lxd-preseed.conf | sed 's/^config: {}/config:\n  core.https_address: '$DEFAULT_IP':8443/' | sg lxd -c "lxd init --preseed"
    sg lxd -c "lxd waitready"
    sg lxd -c "lxc profile device set default eth0 mtu $DEFAULT_MTU"
    sg lxd -c "lxc network set lxdbr0 bridge.mtu $DEFAULT_MTU"
    echo -e "Finished installation of lxd"
}

function install_juju() {
    # Installs Juju
    echo -e "Installing juju"
    JUJU_TEMPDIR="$(mktemp -d -q --tmpdir "jujufolder.XXXXXX")"
    trap '${SUDO} rm -rf "${JUJU_TEMPDIR}"' EXIT
    $SUDO curl --output ${JUJU_TEMPDIR}/juju-$JUJU_AGENT_VERSION-$JUJU_AGENT_RELEASE.tar.xz -LO https://launchpad.net/juju/$JUJU_AGENT_VERSION_M/$JUJU_AGENT_VERSION/+download/juju-$JUJU_AGENT_VERSION-$JUJU_AGENT_RELEASE.tar.xz
    $SUDO tar -xf ${JUJU_TEMPDIR}/juju-$JUJU_AGENT_VERSION-$JUJU_AGENT_RELEASE.tar.xz -C ${JUJU_TEMPDIR}
    [ "${USERNAME}" != "root" ] && sudo install -o $USERNAME -g $USERNAME -m 0755 ${JUJU_TEMPDIR}/juju /usr/local/bin/juju || install -m 0755 ${JUJU_TEMPDIR}/juju /usr/local/bin/juju
    [ -n "$INSTALL_NOCACHELXDIMAGES" ] || update_juju_images
    echo -e "Finished installation of juju"
}

function update_juju_images() {
    # Updates the Juju images
    crontab -l | grep update-juju-lxc-images || (crontab -l 2>/dev/null; echo "0 4 * * 6 $USERNAME ${OSM_DEVOPS}/installers/update-juju-lxc-images --xenial --bionic") | crontab -
    ${OSM_DEVOPS}/installers/update-juju-lxc-images --xenial --bionic
}

function juju_createcontroller_k8s() {
    # Creates Kubernetes Juju controller
    cat $KUBECONFIG | juju add-k8s $OSM_VCA_K8S_CLOUDNAME --client
    juju bootstrap $OSM_VCA_K8S_CLOUDNAME $OSM_STACK_NAME  \
            --config controller-service-type=loadbalancer \
            --config enable-os-upgrade=false \
            --agent-version=$JUJU_AGENT_VERSION
}

function juju_addlxd_cloud(){
    # Adds lxd cloud in the juju
    mkdir -p $HOME/.osm
    OSM_VCA_CLOUDNAME="lxd-cloud"
    LXDENDPOINT=$DEFAULT_IP
    LXD_CLOUD=$HOME/.osm/lxd-cloud.yaml
    LXD_CREDENTIALS=$HOME/.osm/lxd-credentials.yaml
    [ -n "$CONTROLLER_NAME" ] && _CONTROLLER_NAME=$CONTROLLER_NAME || _CONTROLLER_NAME=$OSM_STACK_NAME

    cat << EOF > $LXD_CLOUD
clouds:
  $OSM_VCA_CLOUDNAME:
    type: lxd
    auth-types: [certificate]
    endpoint: "https://$LXDENDPOINT:8443"
    config:
      ssl-hostname-verification: false
EOF
    openssl req -nodes -new -x509 -keyout $HOME/.osm/client.key -out $HOME/.osm/client.crt -days 3650 -subj "/C=TR/ST=Ankara/L=Ankara/O=ULAK/OU=OSM/CN=ulakhaberlesme.com.tr"
    local server_cert=`cat /var/lib/lxd/server.crt | sed 's/^/        /'`
    local client_cert=`cat $HOME/.osm/client.crt | sed 's/^/        /'`
    local client_key=`cat $HOME/.osm/client.key | sed 's/^/        /'`

    cat << EOF > $LXD_CREDENTIALS
credentials:
  $OSM_VCA_CLOUDNAME:
    lxd-cloud:
      auth-type: certificate
      server-cert: |
$server_cert
      client-cert: |
$client_cert
      client-key: |
$client_key
EOF
    lxc config trust add local: $HOME/.osm/client.crt
    juju add-cloud -c $_CONTROLLER_NAME $OSM_VCA_CLOUDNAME $LXD_CLOUD --force
    juju add-credential -c $_CONTROLLER_NAME $OSM_VCA_CLOUDNAME -f $LXD_CREDENTIALS
    sg lxd -c "lxd waitready"
    juju controller-config features=[k8s-operators]
}

function check_install_iptables_persistent(){
    # Installs iptables-persistent if not installed
    # Safe unattended install of iptables-persistent
    echo -e "Checking required packages: iptables-persistent"
    if ! dpkg -l iptables-persistent &>/dev/null; then
        echo -e "    Not installed.\nInstalling iptables-persistent requires root privileges"
        echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
        echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
        sudo apt-get -yq install iptables-persistent
    fi
}

function juju_createproxy() {
    # Creates proxy for juju
    check_install_iptables_persistent

    if ! $SUDO iptables -t nat -C PREROUTING -p tcp -m tcp -d $DEFAULT_IP --dport 17070 -j DNAT --to-destination $OSM_VCA_HOST; then
        $SUDO iptables -t nat -A PREROUTING -p tcp -m tcp -d $DEFAULT_IP --dport 17070 -j DNAT --to-destination $OSM_VCA_HOST
        $SUDO netfilter-persistent save
    fi
}

function juju_createcontroller() {
    if ! juju show-controller $OSM_STACK_NAME &> /dev/null; then
        # Not found created, create the controller
        [ "$USERNAME" != "root" ] && sudo usermod -a -G lxd ${USER}
        # --config enable-os-upgrade=false --config enable-os-refresh-update=false
        # added because of this bug (https://osm.etsi.org/bugzilla/show_bug.cgi?id=1629)
        # keep it until this bug is resolved
        sg lxd -c "juju bootstrap --config enable-os-upgrade=false --config enable-os-refresh-update=false --bootstrap-series=xenial --agent-version=$JUJU_AGENT_VERSION $OSM_VCA_CLOUDNAME $OSM_STACK_NAME"
    fi
    [ $(juju controllers | awk "/^${OSM_STACK_NAME}[\*| ]/{print $1}"|wc -l) -eq 1 ] || FATAL "Juju installation failed"
    juju controller-config features=[k8s-operators]
}

function generate_secret() {
    head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32
}

function generate_k8s_manifest_files() {
    #Kubernetes resources
    $SUDO cp -bR ${OSM_DEVOPS}/installers/docker/osm_pods $OSM_DOCKER_WORK_DIR
    # mongo.yaml will be removed if the mongo service is being deployed as a charmed service
    [ -n "$DEPLOY_CHARMED_SERVICES" ] && $SUDO rm -f $OSM_K8S_WORK_DIR/mongo.yaml || $SUDO sed -i "s|mongodb-k8s|mongo|g;s|/?replicaSet=rs0||g" $OSM_K8S_WORK_DIR/lcm.yaml $OSM_K8S_WORK_DIR/mon.yaml $OSM_K8S_WORK_DIR/nbi.yaml $OSM_K8S_WORK_DIR/pol.yaml $OSM_K8S_WORK_DIR/ro.yaml
    [ "$CRI_NAME" != "docker" ] && $SUDO sed -zi "s|        volumeMounts:\n        - name: socket\n          mountPath: /var/run/docker.sock\n      volumes:\n      - name: socket\n        hostPath:\n         path: /var/run/docker.sock||g" $OSM_K8S_WORK_DIR/kafka.yaml
}

function deploy_charmed_services() {
    # Deploys charmed services
    juju add-model $OSM_STACK_NAME $OSM_VCA_K8S_CLOUDNAME
    juju deploy ch:mongodb-k8s -m $OSM_STACK_NAME
}

function deploy_osm_services() {
    # Deploys osm pods and services
    kubectl apply -n $OSM_STACK_NAME -f $OSM_K8S_WORK_DIR
}

function deploy_osm_pla_service() {
    # corresponding to namespace_vol
    $SUDO  sed -i "s#path: /var/lib/osm#path: $OSM_NAMESPACE_VOL#g" $OSM_DOCKER_WORK_DIR/osm_pla/pla.yaml
    # corresponding to deploy_osm_services
    kubectl apply -n $OSM_STACK_NAME -f $OSM_DOCKER_WORK_DIR/osm_pla
}

function generate_docker_env_files() {
    echo "Doing a backup of existing env files"
    $SUDO cp $OSM_DOCKER_WORK_DIR/keystone-db.env{,~}
    $SUDO cp $OSM_DOCKER_WORK_DIR/keystone.env{,~}
    $SUDO cp $OSM_DOCKER_WORK_DIR/lcm.env{,~}
    $SUDO cp $OSM_DOCKER_WORK_DIR/mon.env{,~}
    $SUDO cp $OSM_DOCKER_WORK_DIR/nbi.env{,~}
    $SUDO cp $OSM_DOCKER_WORK_DIR/pol.env{,~}
    $SUDO cp $OSM_DOCKER_WORK_DIR/ro-db.env{,~}
    $SUDO cp $OSM_DOCKER_WORK_DIR/ro.env{,~}

    echo "Generating docker env files"
    # LCM
    if [ ! -f $OSM_DOCKER_WORK_DIR/lcm.env ]; then
        echo "OSMLCM_DATABASE_COMMONKEY=${OSM_DATABASE_COMMONKEY}" | $SUDO tee -a $OSM_DOCKER_WORK_DIR/lcm.env
    fi

    if ! grep -Fq "OSMLCM_VCA_HOST" $OSM_DOCKER_WORK_DIR/lcm.env; then
        echo "OSMLCM_VCA_HOST=${OSM_VCA_HOST}" | $SUDO tee -a $OSM_DOCKER_WORK_DIR/lcm.env
    else
        $SUDO sed -i "s|OSMLCM_VCA_HOST.*|OSMLCM_VCA_HOST=$OSM_VCA_HOST|g" $OSM_DOCKER_WORK_DIR/lcm.env
    fi

    if ! grep -Fq "OSMLCM_VCA_SECRET" $OSM_DOCKER_WORK_DIR/lcm.env; then
        echo "OSMLCM_VCA_SECRET=${OSM_VCA_SECRET}" | $SUDO tee -a $OSM_DOCKER_WORK_DIR/lcm.env
    else
        $SUDO sed -i "s|OSMLCM_VCA_SECRET.*|OSMLCM_VCA_SECRET=$OSM_VCA_SECRET|g" $OSM_DOCKER_WORK_DIR/lcm.env
    fi

    if ! grep -Fq "OSMLCM_VCA_PUBKEY" $OSM_DOCKER_WORK_DIR/lcm.env; then
        echo "OSMLCM_VCA_PUBKEY=${OSM_VCA_PUBKEY}" | $SUDO tee -a $OSM_DOCKER_WORK_DIR/lcm.env
    else
        $SUDO sed -i "s|OSMLCM_VCA_PUBKEY.*|OSMLCM_VCA_PUBKEY=${OSM_VCA_PUBKEY}|g" $OSM_DOCKER_WORK_DIR/lcm.env
    fi

    if ! grep -Fq "OSMLCM_VCA_CACERT" $OSM_DOCKER_WORK_DIR/lcm.env; then
        echo "OSMLCM_VCA_CACERT=${OSM_VCA_CACERT}" | $SUDO tee -a $OSM_DOCKER_WORK_DIR/lcm.env
    else
        $SUDO sed -i "s|OSMLCM_VCA_CACERT.*|OSMLCM_VCA_CACERT=${OSM_VCA_CACERT}|g" $OSM_DOCKER_WORK_DIR/lcm.env
    fi

    if [ -n "$OSM_VCA_APIPROXY" ]; then
        if ! grep -Fq "OSMLCM_VCA_APIPROXY" $OSM_DOCKER_WORK_DIR/lcm.env; then
            echo "OSMLCM_VCA_APIPROXY=${OSM_VCA_APIPROXY}" | $SUDO tee -a $OSM_DOCKER_WORK_DIR/lcm.env
        else
            $SUDO sed -i "s|OSMLCM_VCA_APIPROXY.*|OSMLCM_VCA_APIPROXY=${OSM_VCA_APIPROXY}|g" $OSM_DOCKER_WORK_DIR/lcm.env
        fi
    fi

    if ! grep -Fq "OSMLCM_VCA_ENABLEOSUPGRADE" $OSM_DOCKER_WORK_DIR/lcm.env; then
        echo "OSMLCM_VCA_ENABLEOSUPGRADE=false" | $SUDO tee -a $OSM_DOCKER_WORK_DIR/lcm.env
    fi

    if ! grep -Fq "OSMLCM_VCA_APTMIRROR" $OSM_DOCKER_WORK_DIR/lcm.env; then
        echo "# OSMLCM_VCA_APTMIRROR=http://archive.ubuntu.com/ubuntu/" | $SUDO tee -a $OSM_DOCKER_WORK_DIR/lcm.env
    fi

    if ! grep -Fq "OSMLCM_VCA_CLOUD" $OSM_DOCKER_WORK_DIR/lcm.env; then
        echo "OSMLCM_VCA_CLOUD=${OSM_VCA_CLOUDNAME}" | $SUDO tee -a $OSM_DOCKER_WORK_DIR/lcm.env
    else
        $SUDO sed -i "s|OSMLCM_VCA_CLOUD.*|OSMLCM_VCA_CLOUD=${OSM_VCA_CLOUDNAME}|g" $OSM_DOCKER_WORK_DIR/lcm.env
    fi

    if ! grep -Fq "OSMLCM_VCA_K8S_CLOUD" $OSM_DOCKER_WORK_DIR/lcm.env; then
        echo "OSMLCM_VCA_K8S_CLOUD=${OSM_VCA_K8S_CLOUDNAME}" | $SUDO tee -a $OSM_DOCKER_WORK_DIR/lcm.env
    else
        $SUDO sed -i "s|OSMLCM_VCA_K8S_CLOUD.*|OSMLCM_VCA_K8S_CLOUD=${OSM_VCA_K8S_CLOUDNAME}|g" $OSM_DOCKER_WORK_DIR/lcm.env
    fi

    # RO
    MYSQL_ROOT_PASSWORD=$(generate_secret)
    if [ ! -f $OSM_DOCKER_WORK_DIR/ro-db.env ]; then
        echo "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}" |$SUDO tee $OSM_DOCKER_WORK_DIR/ro-db.env
    fi
    if [ ! -f $OSM_DOCKER_WORK_DIR/ro.env ]; then
        echo "RO_DB_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}" |$SUDO tee $OSM_DOCKER_WORK_DIR/ro.env
    fi
    if ! grep -Fq "OSMRO_DATABASE_COMMONKEY" $OSM_DOCKER_WORK_DIR/ro.env; then
        echo "OSMRO_DATABASE_COMMONKEY=${OSM_DATABASE_COMMONKEY}" | $SUDO tee -a $OSM_DOCKER_WORK_DIR/ro.env
    fi

    # Keystone
    KEYSTONE_DB_PASSWORD=$(generate_secret)
    SERVICE_PASSWORD=$(generate_secret)
    if [ ! -f $OSM_DOCKER_WORK_DIR/keystone-db.env ]; then
        echo "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}" |$SUDO tee $OSM_DOCKER_WORK_DIR/keystone-db.env
    fi
    if [ ! -f $OSM_DOCKER_WORK_DIR/keystone.env ]; then
        echo "ROOT_DB_PASSWORD=${MYSQL_ROOT_PASSWORD}" |$SUDO tee $OSM_DOCKER_WORK_DIR/keystone.env
        echo "KEYSTONE_DB_PASSWORD=${KEYSTONE_DB_PASSWORD}" |$SUDO tee -a $OSM_DOCKER_WORK_DIR/keystone.env
        echo "SERVICE_PASSWORD=${SERVICE_PASSWORD}" |$SUDO tee -a $OSM_DOCKER_WORK_DIR/keystone.env
    fi

    # NBI
    if [ ! -f $OSM_DOCKER_WORK_DIR/nbi.env ]; then
        echo "OSMNBI_AUTHENTICATION_SERVICE_PASSWORD=${SERVICE_PASSWORD}" |$SUDO tee $OSM_DOCKER_WORK_DIR/nbi.env
        echo "OSMNBI_DATABASE_COMMONKEY=${OSM_DATABASE_COMMONKEY}" | $SUDO tee -a $OSM_DOCKER_WORK_DIR/nbi.env
    fi

    # MON
    if [ ! -f $OSM_DOCKER_WORK_DIR/mon.env ]; then
        echo "OSMMON_KEYSTONE_SERVICE_PASSWORD=${SERVICE_PASSWORD}" | $SUDO tee -a $OSM_DOCKER_WORK_DIR/mon.env
        echo "OSMMON_DATABASE_COMMONKEY=${OSM_DATABASE_COMMONKEY}" | $SUDO tee -a $OSM_DOCKER_WORK_DIR/mon.env
        echo "OSMMON_SQL_DATABASE_URI=mysql://root:${MYSQL_ROOT_PASSWORD}@mysql:3306/mon" | $SUDO tee -a $OSM_DOCKER_WORK_DIR/mon.env
    fi

    if ! grep -Fq "OS_NOTIFIER_URI" $OSM_DOCKER_WORK_DIR/mon.env; then
        echo "OS_NOTIFIER_URI=http://${DEFAULT_IP}:8662" |$SUDO tee -a $OSM_DOCKER_WORK_DIR/mon.env
    else
        $SUDO sed -i "s|OS_NOTIFIER_URI.*|OS_NOTIFIER_URI=http://$DEFAULT_IP:8662|g" $OSM_DOCKER_WORK_DIR/mon.env
    fi

    if ! grep -Fq "OSMMON_VCA_HOST" $OSM_DOCKER_WORK_DIR/mon.env; then
        echo "OSMMON_VCA_HOST=${OSM_VCA_HOST}" | $SUDO tee -a $OSM_DOCKER_WORK_DIR/mon.env
    else
        $SUDO sed -i "s|OSMMON_VCA_HOST.*|OSMMON_VCA_HOST=$OSM_VCA_HOST|g" $OSM_DOCKER_WORK_DIR/mon.env
    fi

    if ! grep -Fq "OSMMON_VCA_SECRET" $OSM_DOCKER_WORK_DIR/mon.env; then
        echo "OSMMON_VCA_SECRET=${OSM_VCA_SECRET}" | $SUDO tee -a $OSM_DOCKER_WORK_DIR/mon.env
    else
        $SUDO sed -i "s|OSMMON_VCA_SECRET.*|OSMMON_VCA_SECRET=$OSM_VCA_SECRET|g" $OSM_DOCKER_WORK_DIR/mon.env
    fi

    if ! grep -Fq "OSMMON_VCA_CACERT" $OSM_DOCKER_WORK_DIR/mon.env; then
        echo "OSMMON_VCA_CACERT=${OSM_VCA_CACERT}" | $SUDO tee -a $OSM_DOCKER_WORK_DIR/mon.env
    else
        $SUDO sed -i "s|OSMMON_VCA_CACERT.*|OSMMON_VCA_CACERT=${OSM_VCA_CACERT}|g" $OSM_DOCKER_WORK_DIR/mon.env
    fi


    # POL
    if [ ! -f $OSM_DOCKER_WORK_DIR/pol.env ]; then
        echo "OSMPOL_SQL_DATABASE_URI=mysql://root:${MYSQL_ROOT_PASSWORD}@mysql:3306/pol" | $SUDO tee -a $OSM_DOCKER_WORK_DIR/pol.env
    fi

    echo "Finished generation of docker env files"
}

function add_local_k8scluster() {
    /usr/bin/osm --all-projects vim-create \
      --name _system-osm-vim \
      --account_type dummy \
      --auth_url http://dummy \
      --user osm --password osm --tenant osm \
      --description "dummy" \
      --config '{management_network_name: mgmt}'
    /usr/bin/osm --all-projects k8scluster-add \
      --creds ${HOME}/.kube/config \
      --vim _system-osm-vim \
      --k8s-nets '{"net1": null}' \
      --version '1.20' \
      --description "OSM Internal Cluster" \
      _system-osm-k8s
}

function parse_yaml() {
    TAG=$1
    shift
    services=$@
    for module in $services; do
        if [ "$module" == "pla" ]; then
            if [ -n "$INSTALL_PLA" ]; then
                echo "Updating K8s manifest file from opensourcemano\/${module}:.* to ${DOCKER_USER}\/${module}:${TAG}"
                $SUDO sed -i "s#opensourcemano/pla:.*#${DOCKER_USER}/pla:${TAG}#g" ${OSM_DOCKER_WORK_DIR}/osm_pla/pla.yaml
            fi
        else
            echo "Updating K8s manifest file from opensourcemano\/${module}:.* to ${DOCKER_USER}\/${module}:${TAG}"
            $SUDO sed -i "s#opensourcemano/${module}:.*#${DOCKER_USER}/${module}:${TAG}#g" ${OSM_K8S_WORK_DIR}/${module}.yaml
        fi
    done
}

function update_manifest_files() {
    osm_services="nbi lcm ro pol mon ng-ui keystone pla"
    list_of_services=""
    for module in $osm_services; do
        module_upper="${module^^}"
        list_of_services="$list_of_services $module"
    done
    # TODO: Change 9 to 10 when 10 point release is on the air.
    if [ ! "$OSM_DOCKER_TAG" == "9" ]; then
        parse_yaml $OSM_DOCKER_TAG $list_of_services
    fi
}

function namespace_vol() {
    osm_services="nbi lcm ro pol mon kafka mysql prometheus"
    for osm in $osm_services; do
        $SUDO sed -i "s#path: /var/lib/osm#path: $OSM_NAMESPACE_VOL#g" $OSM_K8S_WORK_DIR/$osm.yaml
    done
}

function kube_secrets() {
    # Creates secrets from env files which will be used by containers
    kubectl create ns $OSM_STACK_NAME
    kubectl create secret generic lcm-secret -n $OSM_STACK_NAME --from-env-file=$OSM_DOCKER_WORK_DIR/lcm.env
    kubectl create secret generic mon-secret -n $OSM_STACK_NAME --from-env-file=$OSM_DOCKER_WORK_DIR/mon.env
    kubectl create secret generic nbi-secret -n $OSM_STACK_NAME --from-env-file=$OSM_DOCKER_WORK_DIR/nbi.env
    kubectl create secret generic ro-db-secret -n $OSM_STACK_NAME --from-env-file=$OSM_DOCKER_WORK_DIR/ro-db.env
    kubectl create secret generic ro-secret -n $OSM_STACK_NAME --from-env-file=$OSM_DOCKER_WORK_DIR/ro.env
    kubectl create secret generic keystone-secret -n $OSM_STACK_NAME --from-env-file=$OSM_DOCKER_WORK_DIR/keystone.env
    kubectl create secret generic pol-secret -n $OSM_STACK_NAME --from-env-file=$OSM_DOCKER_WORK_DIR/pol.env
}

function install_osmclient(){
    CLIENT_RELEASE=${RELEASE#"-R "}
    CLIENT_REPOSITORY_KEY="OSM%20ETSI%20Release%20Key.gpg"
    CLIENT_REPOSITORY=${REPOSITORY#"-r "}
    CLIENT_REPOSITORY_BASE=${REPOSITORY_BASE#"-u "}
    key_location=$CLIENT_REPOSITORY_BASE/$CLIENT_RELEASE/$CLIENT_REPOSITORY_KEY
    curl $key_location | sudo apt-key add -
    add_repo "deb [arch=amd64] $CLIENT_REPOSITORY_BASE/$CLIENT_RELEASE $CLIENT_REPOSITORY osmclient IM" "donotremove"
    $SUDO apt-get update
    $SUDO apt-get install -y python3-pip
    $SUDO -H LC_ALL=C python3 -m pip install -U pip
    $SUDO -H LC_ALL=C python3 -m pip install -U python-magic pyangbind verboselogs
    $SUDO apt-get install -y python3-osm-im python3-osmclient
    if [ -f /usr/lib/python3/dist-packages/osm_im/requirements.txt ]; then
        python3 -m pip install -r /usr/lib/python3/dist-packages/osm_im/requirements.txt
    fi
    if [ -f /usr/lib/python3/dist-packages/osmclient/requirements.txt ]; then
        sudo apt-get install -y libcurl4-openssl-dev libssl-dev
        python3 -m pip install -r /usr/lib/python3/dist-packages/osmclient/requirements.txt
    fi
    $SUDO echo -e '# enable to use of osmclient\nexport OSM_HOSTNAME='$DEFAULT_IP'' >> ${HOME}/.bashrc
    export OSM_HOSTNAME=$DEFAULT_IP
    echo -e "OSM client assumes that OSM host is running in $DEFAULT_IP."
    echo -e "In case you want to interact with a different OSM host, you will have to configure this env variable in your .bashrc file:"
    echo -e "     export OSM_HOSTNAME=<OSM_host>"
}

function parse_juju_password {
    # Takes a juju/accounts.yaml file and returns the password specific
    # for a controller.
    password_file="${HOME}/.local/share/juju/accounts.yaml"
    local controller_name=$1
    local s='[[:space:]]*' w='[a-zA-Z0-9_-]*' fs=$(echo @|tr @ '\034')
    sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p" $password_file |
    awk -F$fs -v controller=$controller_name '{
        indent = length($1)/2;
        vname[indent] = $2;
        for (i in vname) {if (i > indent) {delete vname[i]}}
        if (length($3) > 0) {
            vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
            if (match(vn,controller) && match($2,"password")) {
                printf("%s",$3);
            }
        }
    }'
}

function install_k8s_monitoring() {
    echo -e "WIP"
}

function uninstall_k8s_monitoring() {
    echo -e "WIP"
}

function remove_k8s_namespace() {
    # Removes osm deployments and services
    if kubectl get ns $1 &> /dev/null; then
        kubectl delete ns $1
    fi
}

function fix_server_host() {
    # Changes the server host from localhost to default host (ens3 ip)
    $SUDO sed -i "s|    server: https://127.0.0.1:6443|    server: https://$DEFAULT_IP:6443|" $KUBECONFIG
    echo -e "$DEFAULT_IP added to $KUBECONFIG file"
    cat $KUBECONFIG
}

function install_osm() {
    # Installs OSM
    if [ -n "$KUBERNETES" ];
    then
        [ -z "$ASSUME_YES" ] && ! ask_user "The installation will do the following
        1. Install and initialize Kubernetes
        2. Install and configure LXD
        3. Install juju
        as pre-requirements.
        Do you want to proceed (Y/n)? " y && echo -e "Cancelled!" && exit 1
    else
        [ -z "$ASSUME_YES" ] && ! ask_user "This installation supports only Kubernetes installation at the moment. New installation methods need to be discussed (Y/n)? " y && echo -e "Cancelled!" && exit 1
        exit 1
    fi
    echo -e "Installing OSM"

    get_default_if_ip_mtu

    # if no host is passed in, we need to install lxd/juju, unless explicilty asked not to
    [ -z "$OSM_VCA_HOST" ] && [ -z "$INSTALL_NOLXD" ] && [ -z "$LXD_CLOUD_FILE" ] && install_lxd

    echo "Creating folders for installation"
    [ ! -d "$OSM_DOCKER_WORK_DIR" ] && $SUDO mkdir -p $OSM_DOCKER_WORK_DIR
    [ ! -d "$OSM_DOCKER_WORK_DIR/osm_pla" -a -n "$INSTALL_PLA" ] && $SUDO mkdir -p $OSM_DOCKER_WORK_DIR/osm_pla

    # Call single node K8s cluster installer
    if [ -n "$KUBERNETES" ];
    then
        echo -e "k8s-cluster-installer.sh is going to set up a single node Kubernetes cluster"
        ./k8s-cluster-installer.sh -y -n osm-machine -c $CRI_NAME -P 80-32767 \
            --enable-ranchersc --enable-metallb
        # Adding the kubeconfig file location as env
        source ./adminconf.sh
        if [ -n "$INSTALL_K8S_MONITOR" ];
        then
            # uninstall OSM MONITORING
            uninstall_k8s_monitoring
        fi
        # Remove old namespace
        remove_k8s_namespace $OSM_STACK_NAME
    else
        echo -e "Only K8s installation is supported at the moment"
        exit 1
    fi

    if [ -z "$INSTALL_NOJUJU" ]; then
        install_juju
        if [ -z "$OSM_VCA_HOST" ]; then
            if [ -z "$CONTROLLER_NAME" ]; then
                if [ -n "$KUBERNETES" ]; then
                    # Fix the server ip in KUBECONFIG(/etc/kubernetes/admin.conf)
                    fix_server_host
                    juju_createcontroller_k8s
                    juju_addlxd_cloud
                else
                    if [ -n "$LXD_CLOUD_FILE" ]; then
                        [ -z "$LXD_CRED_FILE" ] && FATAL "The installer needs the LXD credential yaml if the LXD is external"
                        OSM_VCA_CLOUDNAME="lxd-cloud"
                        juju add-cloud $OSM_VCA_CLOUDNAME $LXD_CLOUD_FILE --force || juju update-cloud $OSM_VCA_CLOUDNAME --client -f $LXD_CLOUD_FILE
                        juju add-credential $OSM_VCA_CLOUDNAME -f $LXD_CRED_FILE || juju update-credential $OSM_VCA_CLOUDNAME lxd-cloud-creds -f $LXD_CRED_FILE
                    fi
                    juju_createcontroller
                    juju_createproxy
                fi
            else
                OSM_VCA_CLOUDNAME="lxd-cloud"
                if [ -n "$LXD_CLOUD_FILE" ]; then
                    [ -z "$LXD_CRED_FILE" ] && FATAL "The installer needs the LXD credential yaml if the LXD is external"
                    juju add-cloud -c $CONTROLLER_NAME $OSM_VCA_CLOUDNAME $LXD_CLOUD_FILE --force || juju update-cloud lxd-cloud -c $CONTROLLER_NAME -f $LXD_CLOUD_FILE
                    juju add-credential -c $CONTROLLER_NAME $OSM_VCA_CLOUDNAME -f $LXD_CRED_FILE || juju update-credential lxd-cloud -c $CONTROLLER_NAME -f $LXD_CRED_FILE
                else
                    juju_addlxd_cloud
                    # Not needed since juju_addlxd_cloud has the below commands
                    # lxc config trust add local: ~/.osm/client.crt
                    # juju add-cloud -c $CONTROLLER_NAME $OSM_VCA_CLOUDNAME ~/.osm/lxd-cloud.yaml --force || juju update-cloud lxd-cloud -c $CONTROLLER_NAME -f ~/.osm/lxd-cloud.yaml
                    # juju add-credential -c $CONTROLLER_NAME $OSM_VCA_CLOUDNAME -f ~/.osm/lxd-credentials.yaml || juju update-credential lxd-cloud -c $CONTROLLER_NAME -f ~/.osm/lxd-credentials.yaml
                fi
            fi
            [ -z "$CONTROLLER_NAME" ] && OSM_VCA_HOST=`sg lxd -c "juju show-controller $OSM_STACK_NAME"|grep api-endpoints|awk -F\' '{print $2}'|awk -F\: '{print $1}'`
            [ -n "$CONTROLLER_NAME" ] && OSM_VCA_HOST=`juju show-controller $CONTROLLER_NAME |grep api-endpoints|awk -F\' '{print $2}'|awk -F\: '{print $1}'`
            [ -z "$OSM_VCA_HOST" ] && FATAL "Cannot obtain juju controller IP address"
        fi

        if [ -z "$OSM_VCA_SECRET" ]; then
            [ -z "$CONTROLLER_NAME" ] && OSM_VCA_SECRET=$(parse_juju_password $OSM_STACK_NAME)
            [ -n "$CONTROLLER_NAME" ] && OSM_VCA_SECRET=$(parse_juju_password $CONTROLLER_NAME)
            [ -z "$OSM_VCA_SECRET" ] && FATAL "Cannot obtain juju secret"
        fi
        if [ -z "$OSM_VCA_PUBKEY" ]; then
            OSM_VCA_PUBKEY=$(cat $HOME/.local/share/juju/ssh/juju_id_rsa.pub)
            [ -z "$OSM_VCA_PUBKEY" ] && FATAL "Cannot obtain juju public key"
        fi
        if [ -z "$OSM_VCA_CACERT" ]; then
            [ -z "$CONTROLLER_NAME" ] && OSM_VCA_CACERT=$(juju controllers --format json | jq -r --arg controller $OSM_STACK_NAME '.controllers[$controller]["ca-cert"]' | base64 | tr -d \\n)
            [ -n "$CONTROLLER_NAME" ] && OSM_VCA_CACERT=$(juju controllers --format json | jq -r --arg controller $CONTROLLER_NAME '.controllers[$controller]["ca-cert"]' | base64 | tr -d \\n)
        [ -z "$OSM_VCA_CACERT" ] && FATAL "Cannot obtain juju CA certificate"
        fi
        # Set OSM_VCA_APIPROXY only when it is not a k8s installation
        if [ -z "$KUBERNETES" ]; then
            if [ -z "$OSM_VCA_APIPROXY" ]; then
                OSM_VCA_APIPROXY=$DEFAULT_IP
                [ -z "$OSM_VCA_APIPROXY" ] && FATAL "Cannot obtain juju api proxy"
            fi
            juju_createproxy
        fi
    fi

    if [ -z "$OSM_DATABASE_COMMONKEY" ]; then
        OSM_DATABASE_COMMONKEY=$(generate_secret)
        [ -z "OSM_DATABASE_COMMONKEY" ] && FATAL "Cannot generate common db secret"
    fi

    if [ -n "$KUBERNETES" ]; then
        generate_k8s_manifest_files
    else
        echo -e "Only, Kubernetes installation is supported at the moment."
        exit 1
    fi
    
    generate_docker_env_files

    if [ -n "$KUBERNETES" ]; then
        [ -n "$DEPLOY_CHARMED_SERVICES" ] && deploy_charmed_services
        kube_secrets
        update_manifest_files
        namespace_vol
        deploy_osm_services
        if [ -n "$INSTALL_PLA"]; then
            # optional PLA install
            deploy_osm_pla_service
        fi
        if [ -n "$INSTALL_K8S_MONITOR" ]; then
            # install OSM MONITORING
            install_k8s_monitoring
        fi
    else
        echo -e "Only, Kubernetes installation is supported at the moment."
    fi

    [ -z "$INSTALL_NOHOSTCLIENT" ] && install_osmclient

    echo -e "Checking OSM health state..."
    if [ -n "$KUBERNETES" ]; then
        $OSM_DEVOPS/installers/osm_health.sh -s ${OSM_STACK_NAME} -k || \
        echo -e "OSM is not healthy, but will probably converge to a healthy state soon." && \
        echo -e "Check OSM status with: kubectl -n ${OSM_STACK_NAME} get all"
    else
        echo -e "Only, Kubernetes installation is supported at the moment."
        exit 1
        # $OSM_DEVOPS/installers/osm_health.sh -s ${OSM_STACK_NAME} || \
        # echo -e "OSM is not healthy, but will probably converge to a healthy state soon." && \
        # echo -e "Check OSM status with: docker service ls; docker stack ps ${OSM_STACK_NAME}"
    fi

    [ -n "$KUBERNETES" ] && add_local_k8scluster
}

function remove_volumes() {
    if [ -n "$KUBERNETES" ]; then
        k8_volume=$1
        echo -e "Removing ${k8_volume}"
        $WORKDIR_SUDO rm -rf ${k8_volume}
    else
        echo -e "Only K8s is supported at the moment"
    fi
}

function remove_crontab_job() {
    crontab -l | grep -v '${OSM_DEVOPS}/installers/update-juju-lxc-images'  | crontab -
}

function uninstall_osmclient() {
    echo -e "Removing osmclient"
    $SUDO apt-get remove --purge -y python-osmclient
    $SUDO apt-get remove --purge -y python3-osmclient
}

function uninstall_osmdevops() {
    echo -e "Removing osm-devops"
    $SUDO apt-get remove --purge -y osm-devops
}

function uninstall_required_packages(){
    echo -e "Removing required packages: $REQUIRED_PACKAGES"
    $SUDO apt-get remove --purge -y $REQUIRED_PACKAGES
}

function uninstall_lxd(){
    echo -e "Removing LXD required packages: $LXD_REQUIRED_PACKAGES"
    $SUDO apt-get remove --purge -y $LXD_REQUIRED_PACKAGES
}

function uninstall_juju() {
    echo -e "Removing Juju"
    $SUDO rm -rf $HOME/.local/share/juju
    $SUDO rm -rf /usr/local/bin/juju

}

function uninstall_osm() {
    # Uninstalls OSM
    [ -z "$ASSUME_YES" ] && ! ask_user "The installation will uninstall OSM and other packages and tools
    Do you want to proceed (Y/n)? " y && echo -e "Cancelled!" && exit 1
    echo -e "Uninstalling OSM"
    [ -z "$CONTROLLER_NAME" ] && sg lxd -c "juju kill-controller -t 0 -y $OSM_STACK_NAME"
    if [ -n "$KUBERNETES" ];
    then
        uninstall_k8s_monitoring
        ./k8s-cluster-installer.sh --uninstall -y -n osm-machine -c $CRI_NAME \
            --enable-ranchersc --enable-metallb
        remove_volumes $OSM_NAMESPACE_VOL
    else
        echo -e "Only K8s uninstallation is supported at the moment"
        exit 1
    fi
    echo "Removing $OSM_DOCKER_WORK_DIR"
    $SUDO rm -rf $OSM_DOCKER_WORK_DIR
    remove_crontab_job
    [ -z "$INSTALL_NOHOSTCLIENT" ] && uninstall_osmclient
    uninstall_osmdevops
    echo -e "Removing the repository file"
    $SUDO rm -rf $REPO_PATH
    uninstall_required_packages
    [ -z "$INSTALL_NOLXD" ] && uninstall_lxd
    [ -z "$INSTALL_NOJUJU" ] && uninstall_juju
    echo -e "Removing $HOME/.osm folder"
    $SUDO rm -rf $HOME/.osm
}

REQUIRED_PACKAGES="git wget curl tar software-properties-common apt-transport-https jq"
LXD_REQUIRED_PACKAGES="liblxc1 lxc-common lxcfs lxd lxd-client"
KUBERNETES="y"
UNINSTALL=""
UPDATE=""
ASSUME_YES=""
RELEASE="ReleaseTEN"
REPOSITORY="stable"
INSTALL_PLA=""
INSTALL_NOLXD=""
INSTALL_NOJUJU=""
INSTALL_NOHOSTCLIENT=""
INSTALL_NOCACHELXDIMAGES=""
DEPLOY_CHARMED_SERVICES=""
JUJU_AGENT_VERSION_M=2.8
JUJU_AGENT_VERSION_R=6
JUJU_AGENT_RELEASE="ubuntu" # for 2.9.x and later juju versions, use "linux-amd64"
JUJU_AGENT_VERSION="${JUJU_AGENT_VERSION_M}.${JUJU_AGENT_VERSION_R}"
OSM_DEVOPS=/usr/share/osm-devops
OSM_VCA_HOST=
OSM_VCA_SECRET=
OSM_VCA_PUBKEY=
OSM_VCA_CLOUDNAME="localhost"
OSM_VCA_K8S_CLOUDNAME="k8scloud"
OSM_STACK_NAME=osm
OSM_WORK_DIR="/etc/osm"
OSM_DOCKER_WORK_DIR="/etc/osm/docker"
OSM_K8S_WORK_DIR="${OSM_DOCKER_WORK_DIR}/osm_pods"
OSM_HOST_VOL="/var/lib/osm"
OSM_NAMESPACE_VOL="${OSM_HOST_VOL}/${OSM_STACK_NAME}"
OSM_DOCKER_TAG=latest
KAFKA_TAG=2.11-1.0.2
PROMETHEUS_TAG=v2.4.3
GRAFANA_TAG=latest
PROMETHEUS_NODE_EXPORTER_TAG=0.18.1
PROMETHEUS_CADVISOR_TAG=latest
KEYSTONEDB_TAG=10
OSM_DATABASE_COMMONKEY=
RE_CHECK='^[a-z0-9]([-a-z0-9]*[a-z0-9])?$'
CRI_NAME="docker"
DOCKER_USER=opensourcemano
REPO_PATH=/etc/apt/sources.list.d/osm-repo.list
REPOSITORY_KEY="OSM%20ETSI%20Release%20Key.gpg"
REPOSITORY_BASE="https://osm-download.etsi.org/repository/osm/debian"

while getopts ":c:H:k:r:R:u:D:t:n:O:K:l:L:-: hy" o; do
    case "${o}" in
        c)
            CRI_NAME=${OPTARG}
            ;;
        O)
            # [ "${OPTARG}" == "swarm" ] && KUBERNETES="" && REPO_ARGS+=(-c "${OPTARG}") && continue
            [ "${OPTARG}" == "k8s" ] && KUBERNETES="y" && continue
            echo -e "Invalid argument for -i : ' $OPTARG'\n" >&2
            usage && exit 1
            ;;
        K)
            CONTROLLER_NAME="${OPTARG}"
            ;;
        H)
            OSM_VCA_HOST="${OPTARG}"
            ;;
        k)
            REPOSITORY_KEY="${OPTARG}"
            REPO_ARGS+=(-k "$REPOSITORY_KEY")
            ;;
        r)
            REPOSITORY="${OPTARG}"
            REPO_ARGS+=(-r "$REPOSITORY")
            ;;
        R)
            RELEASE="${OPTARG}"
            REPO_ARGS+=(-R "$RELEASE")
            ;;
        u)
            REPOSITORY_BASE="${OPTARG}"
            REPO_ARGS+=(-u "$REPOSITORY_BASE")
            ;;
        D)
            OSM_DEVOPS="${OPTARG}"
            ;;
        t)
            OSM_DOCKER_TAG="${OPTARG}"
            REPO_ARGS+=(-t "$OSM_DOCKER_TAG")
            ;;
        n)
            OSM_STACK_NAME="${OPTARG}" && [ -n "$KUBERNETES" ] && [[ ! "${OPTARG}" =~ $RE_CHECK ]] && echo "Namespace $OPTARG is invalid. Regex used for validation is $RE_CHECK" && exit 0
            ;;
        l)
            LXD_CLOUD_FILE="${OPTARG}"
            ;;
        L)
            LXD_CRED_FILE="${OPTARG}"
            ;;
        -)
            [ "${OPTARG}" == "help" ] && usage && exit 0
            [ "${OPTARG}" == "yes" ] && ASSUME_YES="y" && continue
            [ "${OPTARG}" == "nolxd" ] && INSTALL_NOLXD="y" && continue
            [ "${OPTARG}" == "nojuju" ] && INSTALL_NOJUJU="y" && continue
            [ "${OPTARG}" == "nocachelxdimages" ] && INSTALL_NOCACHELXDIMAGES="y" && continue
            [ "${OPTARG}" == "pla" ] && INSTALL_PLA="y" && continue
            [ "${OPTARG}" == "deploy-charmed-services " ] && DEPLOY_CHARMED_SERVICES="y" && continue
            [ "${OPTARG}" == "uninstall" ] && UNINSTALL="y" && continue
            echo -e "Invalid option: '--$OPTARG'\n" >&2
            usage && exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument" >&2
            usage && exit 1
            ;;
        \?)
            echo -e "Invalid option: '-$OPTARG'\n" >&2
            usage && exit 1
            ;;
        h)
            usage && exit 0
            ;;
        y)
            ASSUME_YES="y"
            ;;
        *)
            usage && exit 1
            ;;
    esac
done

# Removes OSM and its needed packages and tools
[ "$UNINSTALL" == "y" ] && uninstall_osm && echo -e "DONE" && exit 0

# The required packages is going be left to the osm-machine
install_required_packages

# OSM devops repository
add_repo "deb [arch=amd64] $REPOSITORY_BASE/$RELEASE $REPOSITORY devops"

$SUDO apt-get -y -q update
$SUDO apt-get install -y osm-devops

[ "${OSM_STACK_NAME}" == "osm" ] || OSM_DOCKER_WORK_DIR="$OSM_WORK_DIR/stack/$OSM_STACK_NAME"
[ -n "$KUBERNETES" ] && OSM_K8S_WORK_DIR="$OSM_DOCKER_WORK_DIR/osm_pods" && OSM_NAMESPACE_VOL="${OSM_HOST_VOL}/${OSM_STACK_NAME}"

# Call OSM installer function to start installation
install_osm

exit 0
