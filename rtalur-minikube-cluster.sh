#!/bin/bash

PROFILE="${PROFILE:-minicluster1}"
echo PROFILE is $PROFILE

if [[ $1 == "destroy" ]]
then
	minikube --profile="${PROFILE}" stop
	minikube --profile="${PROFILE}" delete
	sudo rm -f /var/lib/libvirt/images/minikube-box2-vm-disk-"${PROFILE}"-50G
        virsh pool-refresh default
        exit 0
fi

minikube start -b kubeadm --kubernetes-version="v1.19.2" --feature-gates="BlockVolume=true,CSIBlockVolume=true,VolumeSnapshotDataSource=true,ExpandCSIVolumes=true" --profile="${PROFILE}"
minikube ssh "sudo mkdir -p /mnt/vda1/var/lib/rook" --profile="${PROFILE}"
minikube ssh "sudo ln -s /mnt/vda1/var/lib/rook /var/lib/rook" --profile="${PROFILE}"
sudo qemu-img create -f raw /var/lib/libvirt/images/minikube-box2-vm-disk-"${PROFILE}"-50G 50G
virsh -c qemu:///system attach-disk "${PROFILE}" --source /var/lib/libvirt/images/minikube-box2-vm-disk-"${PROFILE}"-50G --target vdb --cache none --persistent
minikube --profile="${PROFILE}" stop
minikube --profile="${PROFILE}" start
kubectl create -f ~/Code/go/src/github.com/rook/rook/cluster/examples/kubernetes/ceph/common.yaml --context=${PROFILE}
kubectl create -f ~/Code/go/src/github.com/rook/rook/cluster/examples/kubernetes/ceph/crds.yaml --context=${PROFILE}
kubectl create -f ~/Code/go/src/github.com/rook/rook/cluster/examples/kubernetes/ceph/operator.yaml --context=${PROFILE}
cat <<EOF | kubectl --context=${PROFILE} apply -f -
kind: ConfigMap
apiVersion: v1
metadata:
  name: rook-config-override
  namespace: rook-ceph
data:
  config: |
    [global]
    osd_pool_default_size = 1
    mon_warn_on_pool_no_redundancy = false
---
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: my-cluster
  namespace: rook-ceph
spec:
  dataDirHostPath: /var/lib/rook
  cephVersion:
    image: ceph/ceph:v16
    allowUnsupported: true
  mon:
    count: 1
    allowMultiplePerNode: true
  dashboard:
    enabled: true
  crashCollector:
    disable: true
  storage:
    useAllNodes: true
    useAllDevices: true
  network:
    provider: host
  healthCheck:
    daemonHealth:
      mon:
        interval: 45s
        timeout: 600s
EOF
kubectl create -f ~/Code/go/src/github.com/rook/rook/cluster/examples/kubernetes/ceph/toolbox.yaml --context=${PROFILE}
sleep 10
cat <<EOF | kubectl --context=${PROFILE} apply -f -
apiVersion: ceph.rook.io/v1
kind: CephBlockPool
metadata:
  name: replicapool
  namespace: rook-ceph
spec:
  replicated:
    size: 1
  mirroring:
    enabled: true
    mode: image
    # schedule(s) of snapshot
    snapshotSchedules:
      - interval: 24h # daily snapshots
        startTime: 14:00:00-05:00
EOF
