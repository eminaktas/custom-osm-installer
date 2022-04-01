# User Guide

## osm-installer.sh Usage

This part explains how you can use the osm installer.

```bash
./osm-installer.sh
```

### CLI Options

```bash
./osm-installer.sh -h
usage: ./osm-installer.sh [OPTIONS]
Install OSM from binaries or source code (by default, from binaries)
  OPTIONS
     -h / --help               :    print this help
     -y / --yes                :    do not prompt for confirmation, assumes yes
     -O <orchestrator>         :    deploy osm services using container <orchestrator>. Valid value is 'k8s'.  If -o is not used then osm will be deployed using default orchestrator. When used with --uninstall, osm services deployed by the orchestrator will be uninstalled
     -c <cri-name>             :    CRI name. Currently, docker and containerd is supported. To enable containerd type containerd (by default, docker)
     -H <vca-host>             :    use specific juju host controller IP
     -r <repo>                 :    use specified repository name for osm packages
     -R <release>              :    use specified release for osm binaries (deb packages, lxd images, ...)
     -u <repo-base>            :    use specified repository url for osm packages
     -k <repo-key>             :    use specified repository public key url
     -D <devops-path>          :    use local devops installation path
     -t <docker-tag>           :    specify osm docker tag (default is latest)
     -n <namespace>            :    user defined namespace when installed using k8s, default is osm
     -K <juju-controller>      :    specifies the name of the controller to use - The controller must be already bootstrapped
     -l <lxd-cloud>            :    LXD cloud yaml file
     -L <lxd-credentials>      :    LXD credentials yaml file
     --pla                     :    install the PLA module for placement support
     --nok8s                   :    do not install k8s
     --nolxd                   :    do not install and configure LXD (assumes LXD is already installed and configured)
     --nojuju                  :    do not install juju, assumes already installed
     --nohostclient            :    do not install osmclient
     --norequiredpackages      :    do not install 'git wget curl tar software-properties-common apt-transport-https jq' packages. Use this if you have these packages already installed
     --nocachelxdimages        :    do not cache local lxd images, do not create cronjob for that cache (will save installation time, might affect instantiation time)
     --nosudo                  :    do not use sudo for commands
     --deploy-charmed-services :    deploy the charmed services if this argumament not passed it will deploy it as it is
     --uninstall               :    removes OSM and everything installed for it
```

## k8s-cluster-installer.sh Usage

This part explains how you can use the single node K8s cluster installer.

### Local installation

Don't need to provide any parameter for local installation, just call the script.

```bash
./k8s-cluster-installer.sh
```

By default, it will install Docker as CRI, MetalLB and adjusts for accessing to cluster with your current user.

### Remote installation

```bash
./k8s-cluster-installer.sh -i <host> -u <username> -p <userpassword>
```

### CLI Options

```bash
$ ./k8s-cluster-installer.sh -h
usage ./k8s-cluster-installer.sh [OPTIONS]
Install single node K8s cluster with Kubespray (by default, local installation is active)
  OPTIONS
     -h / --help           :    print this help
     -y / --yes            :    do not prompt for confirmation, assumes yes
     -i <host>             :    remote machine ip address
     -u <username>         :    remote machine username
     -p <userpwd>          :    remote machine userpassword
     -m <metallb-ip>       :    machine ip address for MetalLB. If not provided, script will use default ip address for local installation or host ip address for remote installation.
     -c <cri-name>         :    CRI name. Currently, docker and containerd is supported. To enable containerd type containerd (by default, docker)
     -k <private-key>      :    private key for remote machine
     -b <public-key>       :    public key for remote machine
     -n <host-name>        :    machine name
     -P <port-range>       :    kube apiserver node port range. It must be called as <number>-<number>. For example: 80-32767
     --remote              :    install cluster to remote host (requires host(-i), username(-u) and password(-p) parameters)
     --key-exists          :    use if public key is already installed to remote machine(by default, not exists)
     --enable-metallb      :    use not to install MetalLB
     --enable-ranchersc    :    enable Rancher local path provisioner
     --enable-nodelocaldns :    enable node local dns
     --uninstall           :    removes the installed k8s cluster. Provide the same paramters in the installation process that was used
```
