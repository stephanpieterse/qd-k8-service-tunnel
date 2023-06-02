#!/bin/bash
SELSERVICE=$1
LPORT=$3
RPORT=$2
MUID=$(dd if=/dev/urandom count=9 bs=1 | md5sum | cut -c1-16)
IMAGENAME=${IMAGENAME:-tools-kubectl:1.15-RELEASE}
BASENAME=serviceforwarder-$SELSERVICE
PODNAME=$BASENAME-$MUID
CMNAME=$BASENAME-$MUID
mkdir build

kubectl get svc $SELSERVICE -o yaml | yq -y '. | {metadata:{labels: .spec.selector}}' > _selector.yaml
ssh-keygen -f /tmp/${PODNAME} -N ""
sed -e 's/{PODNAME}/'$PODNAME'/g' -e 's/{CMNAME}/'$CMNAME'/g' -e 's|{IMAGENAME}|'$IMAGENAME'|g' pod.template > build/pod.yaml
SSHKEY="$(cat /tmp/${PODNAME}.pub)"
sed -e 's/{PODNAME}/'$PODNAME'/g' -e 's/{CMNAME}/'$CMNAME'/g' -e 's|{SSHKEY}|'"$SSHKEY"'|g' configmap.template > build/configmap.yaml
yq -y -s '.[0] * .[1]' build/pod.yaml _selector.yaml > build/final.yaml
rm _selector.yaml
rm build/pod.yaml

kubectl apply -f build/
while :;
do
	kubectl get pods $PODNAME | grep Running
  if [ "$?" -eq "0" ];
	then
		break
	fi
	sleep 1s;
done
kubectl port-forward $PODNAME 2222:22 &
PFPID=$!
echo $PFPID > .pfpid

sleep 3s;
#ssh root@localhost -p 2222 -i /tmp/${PODNAME} -R 0.0.0.0:$RPORT:127.0.0.1:$LPORT
sshuttle -e "ssh -i /tmp/${PODNAME} -R 0.0.0.0:$RPORT:127.0.0.1:$LPORT" --dns -r root@localhost:2222 172.16.0.0/12 100.0.0.0/8
kill $(cat .pfpid)

kubectl delete -f build/ --timeout=1s
rm /tmp/${PODNAME}
rm /tmp/${PODNAME}.pub
