# Install OSM in local

Deploy OSM in your local environment without installing everything but Kubernetes components.

## Install OSM to manage Helm deployments

OSM can manage Helm deployments in your cluster. We will only install OSM for this purpose.

We assume that you are already have a cluster. If you don't have you can create single node cluster with [minikube](https://minikube.sigs.k8s.io/docs/start/) or [kind](https://kind.sigs.k8s.io/).

To create a cluster with minikube.

```bash
minikube start --kubernetes-version=v1.23.4 --cpus 12 --memory 8192 --driver virtualbox --extra-config=apiserver.service-node-port-range=1-65535 --addons metallb
```

In you cluster you should activate loadbalancer and open all ports for your K8s cluster.

You can clone the [devops](https://osm.etsi.org/gerrit/#/admin/projects/osm/devops) project and give the directory path. Make sure you folder is in the right branch. For example, we are going to use v11.0 branch since default OSM version is v11.0.

```bash
./osm-installer.sh --nok8s --nolxd --nojuju --nohostclient --norequiredpackages -D <devops-path>
```
