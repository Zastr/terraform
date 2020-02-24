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
ansible-playbook ansible/playbooks/provision_docker_hosts.yml -i inventory/  --key-file ~/.ssh/google_compute_engine

#rke up 
echo -e "${PURPLE}RKE Cluster Deploying... \n"
rke up --config rke/rancher-cluster.yaml