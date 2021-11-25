# K8s Cluster Setup
Use kcli or kubeadmin to create a K8s cluster on Ubuntu 20.04

kcli install and setup instructions are available here - 
https://kcli.readthedocs.io/en/latest/

Use kcli to create a two-node cluster using Ubuntu 20.04 

```
kcli create kube generic -P image=ubuntu2004 -P workers=1 testk8s
```

If using single node cluster then label the node as shown below
```
kubectl label node <node-name> node-role.kubernetes.io/worker=
```

## Replace containerd on the worker

Replace containerd on the worker node by building a new containerd from https://github.com/confidential-containers/containerd/tree/ali-CCv0

# Install Confidential Containers Operator

```
kubectl apply -f https://raw.githubusercontent.com/confidential-containers/operator/main/deploy/deploy.yaml
```

# Install Confidential Containers Runtime

```
kubectl apply  -f https://raw.githubusercontent.com/confidential-containers/operator/main/config/samples/ccruntime.yaml
```

Check if `runtimeclass` have been successfully created
```
kubectl get runtimeclass
```

# Create sample POD

Regular Kata POD
```
kubectl apply -f  https://raw.githubusercontent.com/confidential-containers/operator/ccv0-demo/demo/nginx-deployment-kata.yaml
```

Confidential Container where container image will be pulled inside the VM
```
kubectl apply -f  https://raw.githubusercontent.com/confidential-containers/operator/ccv0-demo/demo/nginx-deployment-cc.yaml
```

# Verify 

Get container ID from POD

```
export PODNAME=<podname>
containerID=$(kubectl get pod $PODNAME -o=jsonpath='{.status.containerStatuses[*].containerID}' | cut -d "/" -f3)
echo $containerID
```

Login to the worker node and run the following commands
```
export containerID=<set-containerd-from-previous-step>
sandboxID=$(crictl inspect $containerID | jq -r '.info.sandboxID')
echo $sandboxID
```

Check container rootfs 
```
cd /run/kata-containers/shared/sandboxes/$sandboxID/shared
find . -name rootfs
```

For confidential containers you'll find rootfs of only the `pause` container.
For regular Kata containers you'll find rootfs of all the containers. 
