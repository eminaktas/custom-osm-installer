# OSM INSTALLER

This repository is to create a custom OSM and Kubernetes installers. Aim is to have more control on installation, updating, configuration and deletion process on OSM and Kubernetes. With that control, to provide more reliable enviroment.

`osm-installer.sh` is the script to install [OSM](https://osm.etsi.org) and its reqired packages.

## Usage

This part explains how you can use the osm installer.

### Installation

```bash
$ ./osm-installer.sh -h
Commands are going to run with sudo
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
     --nolxd                   :    do not install and configure LXD (assumes LXD is already installed and configured)
     --nojuju                  :    do not install juju, assumes already installed
     --nocachelxdimages        :    do not cache local lxd images, do not create cronjob for that cache (will save installation time, might affect instantiation time)
     --deploy-charmed-services :    deploy the charmed services if this argumament not passed it will deploy it as it is
     --uninstall               :    removes OSM and everything installed for it
```

## K8s Cluster Installer

`k8s-cluster-installer.sh` is the script to set-up a single node K8s cluster. [Kubespray](https://kubespray.io) is being used to install a production level K8s cluster. The script supports remote and local installation. There are two installation methods, remote and local (by default, local). 

## Usage

This part explains how you can use the single node K8s cluster installer.

### Local installation

Don't need to provide any parameter for local installation, just call the script.

```bash
$ ./k8s-cluster-installer.sh
```

By default, it will install Docker as CRI, MetalLB and adjusts for accessing to cluster with your current user.

### Remote installation

```bash
$ ./k8s-cluster-installer.sh -i <host> -u <username> -p <userpassword>
```

For more adjustment:

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

## Known issues

* Kubespray cannot install K8s cluster with floating ip access when you want different network for cluster.
