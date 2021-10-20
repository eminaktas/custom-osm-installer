#!/bin/bash
# Single node K8s cluster installer with Kubespray
# maintaner: Emin Aktaş <emin.aktas@ulakhaberlesme.com.tr>

function usage() {
    echo -e "usage $0 [OPTIONS]"
    echo -e "Install single node K8s cluster with Kubespray (by default, local installation is active)"
    echo -e "  OPTIONS"
    echo -e "     -h / --help           :    print this help"
    echo -e "     -y / --yes            :    do not prompt for confirmation, assumes yes"
    echo -e "     -i <host>             :    remote machine ip address"
    echo -e "     -u <username>         :    remote machine username"
    echo -e "     -p <userpwd>          :    remote machine userpassword"
    echo -e "     -m <metallb-ip>       :    machine ip address for MetalLB. If not provided, script will use default ip address for local installation or host ip address for remote installation."
    echo -e "     -c <cri-name>         :    CRI name. Currently, docker and containerd is supported. To enable containerd type containerd (by default, docker)"
    echo -e "     -k <private-key>      :    private key for remote machine"
    echo -e "     -b <public-key>       :    public key for remote machine"
    echo -e "     -n <host-name>        :    machine name"
    echo -e "     -P <port-range>       :    kube apiserver node port range. It must be called as <number>-<number>. For example: 80-32767"
    echo -e "     --remote              :    install cluster to remote host (requires host(-i), username(-u) and password(-p) parameters)"
    echo -e "     --key-exists          :    use if public key is already installed to remote machine(by default, not exists)"
    echo -e "     --enable-metallb      :    use not to install MetalLB"
    echo -e "     --enable-ranchersc    :    enable Rancher local path provisioner"
    echo -e "     --enable-nodelocaldns :    enable node local dns"
    echo -e "     --uninstall           :    removes the installed k8s cluster. Provide the same paramters in the installation process that was used"
}

function ask_user() {
    # ask to the user and parse a response among 'y', 'yes', 'n' or 'no'. Case insensitive
    read -e -p "$1" USER_CONFIRMATION
    while true ; do
        [ -z "$USER_CONFIRMATION" ] && [ "$2" == 'y' ] && return 0
        [ -z "$USER_CONFIRMATION" ] && [ "$2" == 'n' ] && return 1
        [ "${USER_CONFIRMATION,,}" == "yes" ] || [ "${USER_CONFIRMATION,,}" == "y" ] && return 0
        [ "${USER_CONFIRMATION,,}" == "no" ]  || [ "${USER_CONFIRMATION,,}" == "n" ] && return 1
        read -e -p "Please type 'yes' or 'no': " USER_CONFIRMATION
    done
}

function setup_enviroment() {
    # Installs required packages for this installation
    echo -e "Checking if required packages are installed in the enviroment."
    [ "$USERNAME" != "root" ] && local SUDO="sudo" && echo -e "Commands is going to run with sudo"
    REQUIRED_PACKAGES="git expect python3-venv"
    $SUDO dpkg -l $REQUIRED_PACKAGES &>/dev/null \
    || echo -e "One or more required packages are not installed. Updating and installing packages." \
    && $SUDO apt-get update \
    && $SUDO apt-get install -y $REQUIRED_PACKAGES
    echo -e "Setting up the enviroment done!"
}

function clean_enviroment() {
    # Removes the unneeded packages
    echo -e "Cleaning the enviroment. Packages and temporary files is going to be deleted."
    [ "$USERNAME" != "root" ] && local SUDO="sudo" && echo -e "Commands is going to run with sudo"
    $SUDO apt-get remove -y $REQUIRED_PACKAGES
    # Clean up the unused packages
    $SUDO apt-get autoremove -y
    echo -e "Cleaning is done!"
}

function start_k8s_cluster_installation() {
    # Starts the single node K8s cluster installation
    echo -e "Cluster installation is started."
    pushd $KUBESPRAY_FOLDER
    if [ "$INSTALLATION_TYPE" == "remote" ];
    then
        ansible-playbook -i inventory/$CLUSTER_FOLDER/hosts.yml -u $USERNAME -b -v --private-key=$PRIV_KEY cluster.yml
    else
        ansible-playbook -i inventory/$CLUSTER_FOLDER/hosts.ini --connection=local -b -v cluster.yml
    fi
    popd
    echo -e "Cluster installation is done!"
}

function generate_key() {
    # Generates a key pair for remote access without password
    KEYGEN_FOLDER="$(mktemp -d -q --tmpdir "keygenfolder.XXXXXX")"
    trap 'rm -rf "${KEYGEN_FOLDER}"' EXIT
    echo -e "A key pair to be generated is going to be stored in the created $KEYGEN_FOLDER."
    ssh-keygen -t rsa -b 2048 -f $KEYGEN_FOLDER/id_rsa -N "" -C "temp-key-generated-by-osm-installer"
    # Fixing the permission of the generated key pairs
    chmod 400 $KEYGEN_FOLDER/*
    PUB_KEY=$KEYGEN_FOLDER/id_rsa.pub
    PRIV_KEY=$KEYGEN_FOLDER/id_rsa
}

function install_key() {
    # Installs the public key to the remote machine
    echo -e "$PUB_KEY public key is going to be used."
    expect <(cat <<EOD
spawn ssh-copy-id -i $PUB_KEY -oStrictHostKeyChecking=no $USERNAME@$HOST
expect "assword:"
send "$USERPASSWORD\r"
interact
EOD
)
}

function remove_installed_key() {
    # Removes the public key from remote machine
    _pub_key=$(awk '{print $2}' $PUB_KEY)
    echo -e "$PRIV_KEY private key by script is going to be used."
    ssh -i $PRIV_KEY $HOST -oStrictHostKeyChecking=no "sed -i '\#$_pub_key#d' .ssh/authorized_keys"
    echo -e "Public key is removed from remote machine."
}

function setup_kubespray() {
    # Set ups an enviroment for Kubespray to execute the Ansible playbook
    echo -e "Setting up an enviroment for Kubespray to execute the Ansible playbook."
    KUBESPRAY_FOLDER="$(mktemp -d -q --tmpdir "kubesprayfolder.XXXXXX")"
    trap 'rm -rf "${KUBESPRAY_FOLDER}"' EXIT
    git clone https://github.com/kubernetes-sigs/kubespray.git $KUBESPRAY_FOLDER
    pushd $KUBESPRAY_FOLDER
    git checkout $KUBESPRAY_VER
    # Create virtual env for required packages
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
    popd
    echo -e "Setting up the enviroment for Kubespray done!"
}

function update_inventory() {
    # Copies a sample inventory and updates for cluster installation
    echo -e "Updating Ansible inventory folder."
    if [ "$INSTALLATION_TYPE" == "remote" ];
    then
        cp -rfp $KUBESPRAY_FOLDER/inventory/sample $KUBESPRAY_FOLDER/inventory/$CLUSTER_FOLDER
	# Update Ansible inventory
	declare -a IPS=($HOST)
	CONFIG_FILE=$KUBESPRAY_FOLDER/inventory/$CLUSTER_FOLDER/hosts.yml python3 $KUBESPRAY_FOLDER/contrib/inventory_builder/inventory.py ${IPS[@]}
	# Fix the name node1 in the hosts.yml
	sed -i 's|node1|'$HOST_NAME'|' $KUBESPRAY_FOLDER/inventory/$CLUSTER_FOLDER/hosts.yml
	cat $KUBESPRAY_FOLDER/inventory/$CLUSTER_FOLDER/hosts.yml
    else
        cp -rfp $KUBESPRAY_FOLDER/inventory/local $KUBESPRAY_FOLDER/inventory/$CLUSTER_FOLDER
	# hosts.ini is already provided for local installation. No need to update Ansible inventory.
	# Fix the name node1 in the hosts.ini
	sed -i 's|node1|'$HOST_NAME'|' $KUBESPRAY_FOLDER/inventory/$CLUSTER_FOLDER/hosts.ini
	cat $KUBESPRAY_FOLDER/inventory/$CLUSTER_FOLDER/hosts.ini
    fi
    echo -e "Ansible inventory updated."
}

function get_default_ip() {
    # Finds the default interface and ip
    DEFAULT_IF=$(ip route list|awk '$1=="default" {print $5; exit}')
    [ -z "$DEFAULT_IF" ] && DEFAULT_IF=$(route -n |awk '$1~/^0.0.0.0/ {print $8; exit}')
    [ -z "$DEFAULT_IF" ] && echo -e "Not possible to determine the interface with the default route 0.0.0.0" && exit 1
    DEFAULT_IP=`ip -o -4 a s ${DEFAULT_IF} |awk '{split($4,a,"/"); print a[1]}'`
    [ -z "$DEFAULT_IP" ] && echo -e "Not possible to determine the IP address of the interface with the default route" && exit 1
}

function enable_metallb() {
    # Enables the metalLB in group_vars/k8s_cluster/addons.yml
    echo -e "Enabling MetalLB for the cluster."
    [ -z "$ADDONS_PATH" ] && ADDONS_PATH="$KUBESPRAY_FOLDER/inventory/$CLUSTER_FOLDER/group_vars/k8s_cluster/addons.yml"
    if [ -z "$METALLB_IP" ];
    then
        if [ "$INSTALLATION_TYPE" == "local" ];
	    then
            get_default_ip
	        METALLB_IP=$DEFAULT_IP
	    else
	        METALLB_IP=$HOST
	    fi
    fi
    echo -e "MetalLB ip range is going to be $METALLB_IP-$METALLB_IP."
    sed -i 's|metallb_enabled: false|metallb_enabled: true|' $ADDONS_PATH
    sed -zi 's|# metallb_ip_range:\n#   - "10.5.0.50-10.5.0.99"|metallb_ip_range:\n  - "'$METALLB_IP'-'$METALLB_IP'"|' $ADDONS_PATH
    sed -zi 's|# metallb_controller_tolerations:\n#   - key: "node-role.kubernetes.io/master"\n#     operator: "Equal"\n#     value: ""\n#     effect: "NoSchedule"\n#   - key: "node-role.kubernetes.io/control-plane"\n#     operator: "Equal"\n#     value: ""\n#     effect: "NoSchedule"\n# metallb_version: v0.9.6\n# metallb_protocol: "layer2"|metallb_controller_tolerations:\n  - key: "node-role.kubernetes.io/master"\n    operator: "Equal"\n    value: ""\n    effect: "NoSchedule"\n  - key: "node-role.kubernetes.io/control-plane"\n    operator: "Equal"\n    value: ""\n    effect: "NoSchedule"\nmetallb_version: '$METALLB_VER'\nmetallb_protocol: "layer2"|' $ADDONS_PATH
    # set kube_proxy_strict_arp to true for MetalLb to work
    [ -z "$K8S_CLUSTER_PATH" ] && K8S_CLUSTER_PATH="$KUBESPRAY_FOLDER/inventory/$CLUSTER_FOLDER/group_vars/k8s_cluster/k8s-cluster.yml"
    sed -i 's|kube_proxy_strict_arp: false|kube_proxy_strict_arp: true|' $K8S_CLUSTER_PATH
    echo -e "MetalLb is enabled."
    cat $ADDONS_PATH
}

function enable_containerd() {
    # Enables contanerd CRI
    echo -e "Enabling the containerd CRI."
    [ -z "$K8S_CLUSTER_PATH" ] && K8S_CLUSTER_PATH="$KUBESPRAY_FOLDER/inventory/$CLUSTER_FOLDER/group_vars/k8s_cluster/k8s-cluster.yml"
    sed -i 's|container_manager: docker|container_manager: containerd|' $K8S_CLUSTER_PATH
    [ -z "$ETCD_PATH" ] && ETCD_PATH="$KUBESPRAY_FOLDER/inventory/$CLUSTER_FOLDER/group_vars/etcd.yml"
    sed -i 's|etcd_deployment_type: docker|etcd_deployment_type: host|' $ETCD_PATH
    # Define registry mirror for Docker Hub
    [ -z "$CONTAINERD_PATH" ] && CONTAINERD_PATH="$KUBESPRAY_FOLDER/inventory/$CLUSTER_FOLDER/group_vars/all/containerd.yml"
    sed -i 's|# containerd_registries:\n#   "docker.io": "https://registry-1.docker.io"|containerd_registries:\n  "docker.io":\n    - "https://mirror.gcr.io"\n    - "https://registry-1.docker.io"|' $CONTAINERD_PATH
    echo -e "Containerd CRI is enabled."
}

function enable_rancher_local_path_provisioner() {
    # Enables Rancher local path provisioner
    echo -e "Enabling Rancher local path provisioner"
    [ -z "$ADDONS_PATH" ] && ADDONS_PATH="$KUBESPRAY_FOLDER/inventory/$CLUSTER_FOLDER/group_vars/k8s_cluster/addons.yml"
    sed -i 's|local_path_provisioner_enabled: false|local_path_provisioner_enabled: true|' $ADDONS_PATH
    sed -i 's|# local_path_provisioner_storage_class: "local-path|local_path_provisioner_storage_class: "local-path|' $ADDONS_PATH
    sed -i 's|# local_path_provisioner_image_repo: "rancher/local-path-provisioner"|local_path_provisioner_image_repo: "rancher/local-path-provisioner"|' $ADDONS_PATH
    sed -i 's|# local_path_provisioner_image_tag: "v0.0.19"|local_path_provisioner_image_tag: "v0.0.19"|' $ADDONS_PATH
    echo -e "Rancher local path provisioner enabled."
}

function setup_kubectl() {
    # Set ups kubectl cli for the user currently logged in to run kubectl commands
    echo -e "Setting up kubectl cli for the current user."
    if [ "$INSTALLATION_TYPE" == "remote" ];
    then
        # SSH to the remote machine, then do the steps for kubectl command to run for the user that logged in
        if [ "$USERNAME" != "root" ];
        then
            echo -e "$PRIV_KEY private key by script is going to be used."
            # Option 1
            # ssh -i $PRIV_KEY -oStrictHostKeyChecking=no $HOST "sudo cp -r /root/.kube $HOME && sudo chown -R $USERNAME:$USERNAME $HOME/.kube"
            # Option 2
            ssh -i $PRIV_KEY -oStrictHostKeyChecking=no $HOST "sudo chown -R $USERNAME:$USERNAME /etc/kubernetes/admin.conf && echo -e '# Allow the current user to access the kubernetes cluster\nexport KUBECONFIG=/etc/kubernetes/admin.conf' >> $HOME/.profile"
        fi
    else
        if [ "$USERNAME" != "root" ];
        then
            # Option 1
            # sudo cp -r /root/.kube $HOME && sudo chown -R $USERNAME:$USERNAME $HOME/.kube
            # Option 2
            source ./adminconf.sh
            sudo chown -R $USERNAME:$USERNAME /etc/kubernetes/admin.conf && echo -e '# Allow the current user to access the kubernetes cluster\nexport KUBECONFIG=/etc/kubernetes/admin.conf' >> $HOME/.profile
        fi
    fi
    echo -e "Setting up kubectl cli is done!"
}

function remove_dns_autoscaler() {
    # Removes dns-autoscale deployment
    # Since this is a single node installation, it won't be needed
    # and each coredns pod can run on one node, so it won't be able to run
    if [ "$INSTALLATION_TYPE" == "remote" ];
    then
        ssh -i $PRIV_KEY -oStrictHostKeyChecking=no $HOST "KUBECONFIG=/etc/kubernetes/admin.conf kubectl delete deployment dns-autoscaler -n kube-system"
    else
        KUBECONFIG=/etc/kubernetes/admin.conf kubectl delete deployments.apps dns-autoscaler -n kube-system
    fi
}

function scale_coredns() {
    # Scales the coredns replicas to 1
    # By defaullt, it has two replicas. Since it's a single node cluster,
    # second coredns pod will never activate.
    if [ "$INSTALLATION_TYPE" == "remote" ];
    then
        ssh -i $PRIV_KEY -oStrictHostKeyChecking=no $HOST "KUBECONFIG=/etc/kubernetes/admin.conf kubectl scale deployment coredns -n kube-system --replicas 1"
    else
        KUBECONFIG=/etc/kubernetes/admin.conf kubectl scale deployment coredns -n kube-system --replicas 1
    fi
}

function remove_remote_host_identification() {
    # Removes the old remote host identification if exists
    ssh-keygen -R "$HOST"
}

function add_node_port_range() {
    # Adds kube_apiserver_node_port_range in the k8s-cluster.yml
    [ -z "$K8S_CLUSTER_PATH" ] && K8S_CLUSTER_PATH="$KUBESPRAY_FOLDER/inventory/$CLUSTER_FOLDER/group_vars/k8s_cluster/k8s-cluster.yml"
    echo 'kube_apiserver_node_port_range: "'$1'"' | tee -a $K8S_CLUSTER_PATH
}

function disable_node_localdns() {
    [ -z "$K8S_CLUSTER_PATH" ] && K8S_CLUSTER_PATH="$KUBESPRAY_FOLDER/inventory/$CLUSTER_FOLDER/group_vars/k8s_cluster/k8s-cluster.yml"
    sed -i "s|enable_nodelocaldns: true|enable_nodelocaldns: false|g" $K8S_CLUSTER_PATH
    sed -i "s|nodelocaldns_ip: 169.254.25.10|# nodelocaldns_ip: 169.254.25.10|g" $K8S_CLUSTER_PATH
    sed -i "s|nodelocaldns_health_port: 9254|# nodelocaldns_health_port: 9254|g" $K8S_CLUSTER_PATH
}

function unistall_k8s_cluster() {
    # Unistalls the single node K8s cluster installation
    if [ "$INSTALLATION_TYPE" == "remote" ];
    then
        if [ -n "$HOST" ] && [ -n "$USERNAME" ] && [ -n "$USERPASSWORD" ];
        then
            echo -e "Remote uninstallation is being proccess. (host: $HOST, username: $USERNAME, userpassword: $USERPASSWORD)"
        else
            echo -e "You are missing one or more of the parameters (host: $HOST, username: $USERNAME or userpassword: $USERPASSWORD) for remote installation"
        usage && exit 1
        fi
    else
        echo -e "Local uninstallation is being process."
    fi

    [ -z "$ASSUME_YES" ] && ! ask_user "The installation will uninstall the k8s cluster
    KUBESPRAY_VER: $KUBESPRAY_VER
    INSTALLATION_TYPE: $INSTALLATION_TYPE
    METALLB_VER: $METALLB_VER
    ENABLE_METALLB: $ENABLE_METALLB
    CLUSTER_FOLDER: $CLUSTER_FOLDER
    CRI_NAME: $CRI_NAME
    HOST_NAME: $HOST_NAME
    HOST: $HOST
    USERNAME: $USERNAME
    USERPASSWORD: $USERPASSWORD
    PRIV_KEY: $PRIV_KEY
    PUB_KEY: $PUB_KEY
    KEY_ALREADY_INSTALLED: $KEY_ALREADY_INSTALLED
    ENABLE_RANCHERSC: $ENABLE_RANCHERSC
    APISERVER_NODE_PORT_RANGE: $APISERVER_NODE_PORT_RANGE
    ENABLE_NODELOCALDNS: $ENABLE_NODELOCALDNS
    Do you want to proceed (Y/n)? " y && echo -e "Cancelled!" && exit 1

    echo -e "Cluster uninstallation is started."
    pushd $KUBESPRAY_FOLDER
    if [ "$INSTALLATION_TYPE" == "remote" ];
    then
        expect <(cat <<EOD
spawn ansible-playbook -i inventory/$CLUSTER_FOLDER/hosts.yml -u $USERNAME -b --private-key=$PRIV_KEY reset.yml
expect "Are you sure you want to reset cluster state? Type 'yes' to reset your cluster. *:"
send "yes\r"
interact
EOD
)
    else
        expect <(cat <<EOD
spawn ansible-playbook -i inventory/$CLUSTER_FOLDER/hosts.ini --connection=local -b reset.yml
expect "Are you sure you want to reset cluster state? Type 'yes' to reset your cluster. *:"
send "yes\r"
interact
EOD
)
    fi
    popd
    echo -e "Cluster installation is done!"
}

# DEFAULT VARIABLES
KUBESPRAY_VER="release-2.16"
INSTALLATION_TYPE="local"
METALLB_VER="v0.9.6"
CLUSTER_FOLDER="single_node_cluster"
CRI_NAME="docker" # For Kubespray release-2.16, default CRI is docker.
KEY_EXISTS="n"
# GLOBAL VARIABLES
UNINSTALL=""
PRIV_KEY=""
PUB_KEY=""
HOST=""
USERNAME=`whoami`
USERPASSWORD=""
METALLB_IP=""
KEYGEN_FOLDER=""
KUBESPRAY_FOLDER=""
ADDONS_PATH=""
K8S_CLUSTER_PATH=""
REQUIRED_PACKAGES=""
HOST_NAME="k8s-sinlge-node-cluster"
FORBID_METALLB="n"
RANCHER_SC="n"
APISERVER_NODE_PORT_RANGE=""
ENABLE_NODELOCALDNS="n"

while getopts ":i:u:p:m:c:k:b:n:P:-: hy" o; do
    case "${o}" in
        i)
            HOST=${OPTARG}
            ;;
        u)
            USERNAME=${OPTARG}
            ;;
        p)
            USERPASSWORD=${OPTARG}
            ;;
        m)
            METALLB_IP=${OPTARG}
            ;;
        c)
            CRI_NAME=${OPTARG}
            ;;
        k)
            PRIV_KEY=${OPTARG}
            ;;
        b)
            PUB_KEY=${OPTARG}
            ;;
        n)
            HOST_NAME=${OPTARG}
            ;;
        P)
            APISERVER_NODE_PORT_RANGE=${OPTARG}
            ;;
        -)
            [ "${OPTARG}" == "help" ] && usage && exit 0
            [ "${OPTARG}" == "yes" ] && ASSUME_YES="y" && continue
            [ "${OPTARG}" == "remote" ] && INSTALLATION_TYPE="remote" && continue
            [ "${OPTARG}" == "key-exists" ] && KEY_EXISTS="y" && continue
            [ "${OPTARG}" == "enable-metallb" ] && ENABLE_METALLB="y" && continue
            [ "${OPTARG}" == "enable-ranchersc" ] && ENABLE_RANCHERSC="y" && continue
            [ "${OPTARG}" == "enable-nodelocaldns" ] && ENABLE_NODELOCALDNS="y" && continue
            [ "${OPTARG}" == "uninstall" ] && UNINSTALL="y" && continue
            echo -e "Invalid option: '--$OPTARG'\n" >&2
            usage && exit 1
            ;;
        :)
            echo -e "Option -$OPTARG requires an argument" >&2
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

if [ -z "$UNINSTALL" ];
then
    # If remote installation true, make sure host, username and userpassword parameters are provided
    if [ "$INSTALLATION_TYPE" == "remote" ];
    then
        if [ -n "$HOST" ] && [ -n "$USERNAME" ] && [ -n "$USERPASSWORD" ];
        then
            echo -e "Remote installation is being proccess. (host: $HOST, username: $USERNAME, userpassword: $USERPASSWORD)"
        else
            echo -e "You are missing one or more of the parameters (host: $HOST, username: $USERNAME or userpassword: $USERPASSWORD) for remote installation"
        usage && exit 1
        fi
    else
        echo -e "Local installation is being process."
    fi

    [ -z "$ASSUME_YES" ] && ! ask_user "The installation will install and initialize Kubernetes with following parameters
    KUBESPRAY_VER: $KUBESPRAY_VER
    INSTALLATION_TYPE: $INSTALLATION_TYPE
    METALLB_VER: $METALLB_VER
    ENABLE_METALLB: $ENABLE_METALLB
    CLUSTER_FOLDER: $CLUSTER_FOLDER
    CRI_NAME: $CRI_NAME
    HOST_NAME: $HOST_NAME
    HOST: $HOST
    USERNAME: $USERNAME
    USERPASSWORD: $USERPASSWORD
    PRIV_KEY: $PRIV_KEY
    PUB_KEY: $PUB_KEY
    KEY_ALREADY_INSTALLED: $KEY_ALREADY_INSTALLED
    ENABLE_RANCHERSC: $ENABLE_RANCHERSC
    APISERVER_NODE_PORT_RANGE: $APISERVER_NODE_PORT_RANGE
    ENABLE_NODELOCALDNS: $ENABLE_NODELOCALDNS
    Do you want to proceed (Y/n)? " y && echo -e "Cancelled!" && exit 1
fi

# Call the function in the installation order
# Remove the old remote host identification if exists
remove_remote_host_identification

# Install packages for this script to work properly.
setup_enviroment

# If installation is remote, generate install a key pair if needed. 
if [ "$INSTALLATION_TYPE" == "remote" ];
then 
[ -z "$PRIV_KEY" ] || [ -z "$PUB_KEY" ] && echo -e "public, private or both key are not provided, key pair will be generated for remote installation." && generate_key
[ "$KEY_EXISTS" == "n" ] && install_key
fi

# Set up Kubespray
setup_kubespray

# Update inventory
update_inventory

# Enable MetalLb
[ "$ENABLE_METALLB" == "y" ] && enable_metallb

# Enable containerd
if [ "$CRI_NAME" == "containerd" ];
then
    echo -e "Containerd is going to be the CRI for this cluster"
    enable_containerd
else
    echo -e "Docker is going to be the CRI for this cluster"
fi

[ "$ENABLE_RANCHERSC" == "y" ] && enable_rancher_local_path_provisioner

[ -n "$APISERVER_NODE_PORT_RANGE" ] && add_node_port_range $APISERVER_NODE_PORT_RANGE

[ "$ENABLE_NODELOCALDNS" == "n" ] && disable_node_localdns

# Unistall the k8s cluster
[ "$UNINSTALL" == "y" ] && unistall_k8s_cluster

if [ -z "$UNINSTALL" ];
then
    # Start Kubernetes cluster installation
    start_k8s_cluster_installation

    # Set up kubectl CLI for the user
    setup_kubectl

    # Remove dns-autoscaler
    remove_dns_autoscaler

    echo -e "Sleeping 5 secs to make sure that the dns autoscaler is removed."
    sleep 5

    # Scale coredns replicas to 1
    scale_coredns
fi

# Remove the generated key pair
[ "$INSTALLATION_TYPE" == "remote" ] && [ "$KEY_EXISTS" == "n" ] && remove_installed_key

# Clean the enviroment after intallation is done.
clean_enviroment

[ -z "$UNINSTALL" ] && echo -e "Single node Kubernetes cluster installation is successfully done!"

exit 0
