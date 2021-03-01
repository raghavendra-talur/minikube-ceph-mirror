#!/bin/bash

PRIMARY_CLUSTER="${PRIMARY_CLUSTER:-minicluster1}"
SECONDARY_CLUSTER="${SECONDARY_CLUSTER:-minicluster2}"

STORAGECLASS_NAME="rook-ceph-block"
PVC_NAME="rbd-pvc"

cat <<EOF | kubectl --context="${PRIMARY_CLUSTER}" apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
   name: "${STORAGECLASS_NAME}"
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
    clusterID: rook-ceph
    pool: replicapool
    imageFormat: "2"
    imageFeatures: layering
    csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
    csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
    csi.storage.k8s.io/controller-expand-secret-name: rook-csi-rbd-provisioner
    csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
    csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
    csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
    csi.storage.k8s.io/fstype: ext4
reclaimPolicy: Retain
EOF

cat <<EOF | kubectl --context="${PRIMARY_CLUSTER}" apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: "${PVC_NAME}"
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: "${STORAGECLASS_NAME}"
EOF

if ! kubectl --context="${PRIMARY_CLUSTER}" get pvc/"${PVC_NAME}" | grep -q "Bound"
then
    echo "PVC isn't Bound"
    exit 1
fi

RBD_IMAGE_NAME=$(kubectl --context="${PRIMARY_CLUSTER}" get pv/$(kubectl --context="${PRIMARY_CLUSTER}" get pvc/"${PVC_NAME}" -o jsonpath='{.spec.volumeName}') -o jsonpath='{.spec.csi.volumeAttributes.imageName}')
echo RBD_IMAGE_NAME is ${RBD_IMAGE_NAME}

CEPH_TOOLBOX_POD=$(kubectl --context="${PRIMARY_CLUSTER}" -n rook-ceph get pods -l  app=rook-ceph-tools -o jsonpath='{.items[0].metadata.name}')
echo CEPH_TOOLBOX_POD on primary cluster is $CEPH_TOOLBOX_POD


kubectl --context="${PRIMARY_CLUSTER}" -n rook-ceph exec ${CEPH_TOOLBOX_POD} -- rbd info "${RBD_IMAGE_NAME}" --pool=replicapool

kubectl --context="${PRIMARY_CLUSTER}" -n rook-ceph exec ${CEPH_TOOLBOX_POD} -- rbd mirror image enable "${RBD_IMAGE_NAME}" snapshot --pool=replicapool

kubectl --context="${PRIMARY_CLUSTER}" -n rook-ceph exec ${CEPH_TOOLBOX_POD} -- rbd info "${RBD_IMAGE_NAME}" --pool=replicapool

CEPH_TOOLBOX_POD=$(kubectl --context="${SECONDARY_CLUSTER}" -n rook-ceph get pods -l  app=rook-ceph-tools -o jsonpath='{.items[0].metadata.name}')
echo CEPH_TOOLBOX_POD on secondary cluster is $CEPH_TOOLBOX_POD

kubectl --context="${SECONDARY_CLUSTER}" -n rook-ceph exec ${CEPH_TOOLBOX_POD} -- rbd info "${RBD_IMAGE_NAME}" --pool=replicapool


