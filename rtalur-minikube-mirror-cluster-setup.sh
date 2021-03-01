#!/bin/bash

if [[ $1 == "destroy" ]]
then
	PROFILE=minicluster1 rtalur-minikube-cluster.sh destroy
	PROFILE=minicluster2 rtalur-minikube-cluster.sh destroy
	exit 0
fi

PROFILE=minicluster1 rtalur-minikube-cluster.sh
PROFILE=minicluster2 rtalur-minikube-cluster.sh
PRIMARY_CLUSTER=minicluster1 SECONDARY_CLUSTER=minicluster2 rtalur-minikube-enable-mirroring.sh
PRIMARY_CLUSTER=minicluster2 SECONDARY_CLUSTER=minicluster1 rtalur-minikube-enable-mirroring.sh
