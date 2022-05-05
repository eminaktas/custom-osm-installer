# CUSTOM OSM INSTALLER

## osm-installer.sh

This repository is to create a custom OSM and Kubernetes installers. Aim is to have more control on installation, updating, configuration and deletion process on OSM and Kubernetes. With that control, to provide more reliable enviroment.

`osm-installer.sh` is the script to install [OSM](https://osm.etsi.org) and its reqired packages.

## k8s-cluster-installer.sh

`k8s-cluster-installer.sh` is the script to set-up a single node K8s cluster. [Kubespray](https://kubespray.io) is being used to install a production level K8s cluster. The script supports remote and local installation. There are two installation methods, remote and local (by default, local).

## Known issues

* Kubespray cannot install K8s cluster with floating ip access when you want different network for cluster.

## Helm Chart

```bash
helm upgrade --install helm-osm -n osm --create-namespace .
# Remove all pods (when pods are stuck)
kubectl delete pod --grace-period=0 --force $(k get pods | awk 'NR>1 {print $1}')
```

```yaml
{{ printf "%s%s" (include "kafka.zookeeper.fullname" .)) (tpl .Values.zookeeperChrootPath .)) | quote }}
```

### StorageClass

```bash
helm repo add openebs https://openebs.github.io/charts
helm repo update
helm upgrade --install openebs openebs/openebs -n openebs --create-namespace \
    --set legacy.enabled=false \
    --set ndm.enabled=false \
    --set localprovisioner.deviceClass.enabled=false \
    --set ndmOperator.enabled=false \
    --wait
kubectl patch storageclass openebs-hostpath -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

```bash
# Test mysql
# Ref: ref: https://dev.to/musolemasu/deploy-a-mysql-database-server-in-kubernetes-static-dpc
kubectl run -it --rm --image=mysql:8.0 --restart=Never mysql-client -- mysql -h mysql -password="password"
mysql> SHOW DATABASES;
mysql> SHOW GRANTS FOR 'www'@'localhost';
```
