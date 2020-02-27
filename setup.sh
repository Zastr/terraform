PURPLE='\033[0;35m'

# create infrastructure
echo -e "${PURPLE}Deploying infrastructure! \n"
terraform init gce/
terraform apply gce/

# get hosts file
echo -e "${PURPLE}Getting hosts...\n"
terraform output | grep public | cut -d '=' -f 2 | sed 's/^ *//g' > ansible/inventory/hosts.yaml

# add ssh key w/ gcloud
echo -e "${PURPLE}Setting up SSH keys...\n"
gcloud compute config-ssh --ssh-key-file=~/.ssh/id_rsa

# ansible run
echo -e "${PURPLE}Baselining nodes... \n"
ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook ansible/playbooks/provision_docker_hosts.yml -i ansible/inventory/  

#rke up 
echo -e "${PURPLE}RKE Cluster Deploying... \n"

PUBLIC_IPS=($(terraform output | grep public | cut -d '=' -f 2 | sed 's/^ *//g' | tr '\n' ' '))
PRIVATE_IPS=($(terraform output | grep private | cut -d '=' -f 2 | sed 's/^ *//g' | tr '\n' ' '))

cat <<EOF | tee rke/rancher-cluster.yaml
nodes:
  - address: ${PUBLIC_IPS[0]}
    internal_address: ${PRIVATE_IPS[0]}
    user: ${USER}
    role: [controlplane, worker, etcd]
  - address: ${PUBLIC_IPS[1]}
    internal_address: ${PRIVATE_IPS[1]}
    user: ${USER}
    role: [controlplane, worker, etcd]

services:
  etcd:
    snapshot: true
    creation: 6h
    retention: 24h

ingress:
  provider: nginx
  options:
    use-forwarded-headers: "true"
EOF
rke up --config rke/rancher-cluster.yaml

export KUBECONFIG="$PWD/rke/kube_config_rancher-cluster.yaml"

# install rancher (from rancher's docs)

echo -e "${PURPLE}Installing Rancher... \n"
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
kubectl create namespace cattle-system

kubectl apply -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.12/deploy/manifests/00-crds.yaml
kubectl create namespace cert-manager



helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v0.12.0

kubectl -n cert-manager wait --for=condition=available deployment/cert-manager --timeout 3m

helm install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --set hostname=rke.cluster

kubectl -n cattle-system wait --for=condition=available deployment/rancher --timeout 3m

# linkerd install
echo -e "${PURPLE}LinkerD... \n"

linkerd install | kubectl apply -f -

echo -e "${PURPLE}Done!"
echo -e "${PURPLE}Edit your hosts file to point rke.cluster to $(terraform output | grep loadbalancer | cut -d '=' -f 2 | sed 's/^ *//g')"

echo -e "${PURPLE}Verify Linkerd install by running 'linkerd dashboard &'"