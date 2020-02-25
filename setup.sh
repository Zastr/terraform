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