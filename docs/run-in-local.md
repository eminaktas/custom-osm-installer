# Run OSM in local

Deploy OSM in your local environment without installing everything but Kubernetes components.

## Install OSM to manage Helm deployments

OSM can manage Helm deployments in your cluster. We will only install OSM for this purpose.

We assume that you are already have a cluster. If you don't have you can create single node cluster with [minikube](https://minikube.sigs.k8s.io/docs/start/) or [kind](https://kind.sigs.k8s.io/).

To create a cluster with minikube.

```bash
minikube start --kubernetes-version=v1.23.4 --cpus 12 --memory 8192 --extra-config=apiserver.service-node-port-range=1-65535 --addons metallb
```

In you cluster you should activate loadbalancer and open all ports for your K8s cluster.

You can clone the [devops](https://osm.etsi.org/gerrit/#/admin/projects/osm/devops) project and give the directory path. Make sure you folder is in the right branch. For example, we are going to use v11.0 branch since default OSM version is v11.0.

```bash
./osm-installer.sh --nok8s --nolxd --nojuju --nohostclient --norequiredpackages -D <devops-path>
```

## Add a cluster

Since we did not install osm cli in our machine along with installation. We will run these commands in a container. I already did it in conitaner before you can find the Dockerfile and commands [here](https://github.com/eminaktas/learning-process-dump/tree/main/osm-client-container).

Create osmclient pod

```bash
kubectl apply -f https://raw.githubusercontent.com/eminaktas/learning-process-dump/main/osm-client-container/osmclient-pod.yaml
```

If you installed your cluster with minikube and your current context is minikube, use the following command to extract config file

```bash
kubectl config view --raw --minify --flatten > /tmp/kubeconfig
```

As osmclient and osm is running in the same cluster, you don't need to change anything but for kubeconfig, you might need to change server ip and port if it has 127.0.0.1 and a random port which cannot be use to access cluster. Change ip and port number according the information in kube-apiserver.

```bash
kubectl describe pod kube-apiserver-minikube -n kube-system
..
Labels:               component=kube-apiserver
                      tier=control-plane
Annotations:          kubeadm.kubernetes.io/kube-apiserver.advertise-address.endpoint: 192.168.49.2:8443
..
```

Like above, you will find the ip and port number. And, change server ip and port in kubeconfig that we just extracted.

```yaml
..
- cluster:
    certificate-authority: ...
    extensions:
    - extension:
        last-update: Fri, 01 Apr 2022 09:15:04 +03
        provider: minikube.sigs.k8s.io
        version: v1.24.0
      name: cluster_info
    # Before
    # server: https://127.0.0.1:55631
    # After
    server: https://192.168.49.2:8443
..
```

Copy the kubeconfig file the osmclient container.

```bash
kubectl cp /tmp/kubeconfig osm/osmclient:/tmp/kubeconfig
```

Get inside of osmclient pod

```bash
kubectl exec -it osmclient -- bash
```

Then, first create a dummy vim for osm, and define your cluster to osm

```bash
osm vim-create \
    --name dummy-osm-vim \
    --account_type dummy \
    --auth_url http://dummy \
    --user osm --password osm --tenant osm \
    --description "dummy" \
    --config '{management_network_name: mgmt}'

osm k8scluster-add \
    --creds /tmp/kubeconfig \
    --vim dummy-osm-vim \
    --k8s-nets '{"net1": null}' \
    --version '1.23.4' \
    --description "OSM Internal Cluster" \
    my-k8s
```

Let's check if our dummy vim and k8s-cluster is added.

```bash
osm vim-list
+---------------+--------------------------------------+-------------------+
| vim name      | uuid                                 | operational state |
+---------------+--------------------------------------+-------------------+
| dummy-osm-vim | 8783978b-3d33-4649-8c06-a46469718f85 | ENABLED           |
+---------------+--------------------------------------+-------------------+
osm k8scluster-list
+--------+--------------------------------------+---------------+-------------------+-------------------+
| Name   | Id                                   | VIM           | Operational State | Op. state details |
+--------+--------------------------------------+---------------+-------------------+-------------------+
| my-k8s | 2728d839-1335-4baa-a2ef-c48a83595d81 | dummy-osm-vim | DEGRADED          | Helm: ENABLED     |
|        |                                      |               |                   | Juju: ERROR       |
+--------+--------------------------------------+---------------+-------------------+-------------------+
```

Since we don't have and don't need juju, it is normal to see Error here.

## Run a Robot test

To test our environment, we will run a robot test. However, we have to disable some of the lines for the robot test since we already did some of the steps, we will see soon.

Install reqired packages in the osmclient container.

```bash
pip install --ignore-installed haikunator requests pyvcloud progressbar pathlib robotframework robotframework-seleniumlibrary robotframework-requests robotframework-SSHLibrary yq
apt-get install jq
```

Clone the tests repository and we will run a helm test. We are going to use `testsuite/k8s_11-simple_helm_k8s_scaling.robot` file. Before you run the test,

- take `Add K8s Cluster To OSM`, `Remove K8s Cluster from OSM` and `Run Keyword If Any Tests Failed  Delete K8s Cluster   ${k8scluster_name}` tests to the comment line
- change `k8scluster_name` variable value to `my-k8s` which we added our cluster with this name.
- set the `publickey` as `${EMPTY}`. It is also not needed.

If you don't apply these you might see some errors.

You need to clone tests and osm-packages repositories to osmclient pod.

```bash
git clone https://osm.etsi.org/gitlab/vnf-onboarding/osm-packages.git
git clone https://osm.etsi.org/gitlab/osm/tests.git
```

```bash
cd tests/robot-systest
export ROBOT_REPORT_FOLDER=robot-reports
# This is the value we defined for dummy-vim
export VIM_MGMT_NET=mgmt
export VIM_TARGET=dummy-osm-vim
# Folder path for osm-packages repository
export PACKAGES_FOLDER=<osm-packages-path>
# Folder path for tests/robot-systest repository
export ROBOT_DEVOPS_FOLDER=<tests-robot-systest-path>
# Add this variable. Unless, it prints error.
export OSM_RSA_FILE=
mkdir ${ROBOT_REPORT_FOLDER}
robot -d ${ROBOT_REPORT_FOLDER} testsuite/k8s_11-simple_helm_k8s_scaling.robot
```

At the end, we have perfect result.

```bash
==============================================================================
K8S 11-Simple Helm K8S Scaling :: [K8s-11] Simple Helm K8s Scale.
==============================================================================
Create Simple K8s Scale VNF Descriptor                                | PASS |
------------------------------------------------------------------------------
Create Simple K8s Scale NS Descriptor                                 | PASS |
------------------------------------------------------------------------------
Create Network Service Instance                                       | PASS |
------------------------------------------------------------------------------
Get Vnf Id                                                            | PASS |
------------------------------------------------------------------------------
Get Scale Count Before Scale Out :: Get the scale count of the app... | PASS |
------------------------------------------------------------------------------
Perform Manual KDU Scale Out :: Scale out the application of netwo... | PASS |
------------------------------------------------------------------------------
[ WARN ] Keyword 'BuiltIn.Run Keyword Unless' is deprecated.
Check Scale Count After Scale Out :: Check whether the scale count... | PASS |
------------------------------------------------------------------------------
Perform Manual KDU Scale In :: Scale in the application of network... | PASS |
------------------------------------------------------------------------------
[ WARN ] Keyword 'BuiltIn.Run Keyword Unless' is deprecated.
Check Scale Count After Scale In :: Check whether the scale count ... | PASS |
------------------------------------------------------------------------------
Delete NS K8s Instance Test                                           | PASS |
------------------------------------------------------------------------------
Delete NS Descriptor Test                                             | PASS |
------------------------------------------------------------------------------
Delete VNF Descriptor Test                                            | PASS |
------------------------------------------------------------------------------
K8S 11-Simple Helm K8S Scaling :: [K8s-11] Simple Helm K8s Scale.     | PASS |
12 tests, 12 passed, 0 failed
==============================================================================
Output:  /tmp/tests/robot-systest/robot-reports/output.xml
Log:     /tmp/tests/robot-systest/robot-reports/log.html
Report:  /tmp/tests/robot-systest/robot-reports/report.html
```
