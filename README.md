# CUSTOM OSM INSTALLER

## osm-installer.sh

This repository is to create a custom OSM and Kubernetes installers. Aim is to have more control on installation, updating, configuration and deletion process on OSM and Kubernetes. With that control, to provide more reliable enviroment.

`osm-installer.sh` is the script to install [OSM](https://osm.etsi.org) and its reqired packages.

## k8s-cluster-installer.sh

`k8s-cluster-installer.sh` is the script to set-up a single node K8s cluster. [Kubespray](https://kubespray.io) is being used to install a production level K8s cluster. The script supports remote and local installation. There are two installation methods, remote and local (by default, local).

## Known issues

* Kubespray cannot install K8s cluster with floating ip access when you want different network for cluster.
