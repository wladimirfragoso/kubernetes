#!/bin/bash

# Função para exibir mensagens de status
print_status() {
    echo ">>> $1"
}

# Verificar se o script está sendo executado como root
if [[ $EUID -ne 0 ]]; then
   echo "Este script deve ser executado como root (use sudo)" 
   exit 1
fi

# Step 1: Atualizar o sistema sem interação
print_status "Atualizando o sistema..."

# Configurar para não haver interação e aceitar reiniciar serviços automaticamente
export DEBIAN_FRONTEND=noninteractive

# Configurar opções do dpkg para evitar prompts interativos
sudo apt-get -y install debconf-utils
sudo debconf-set-selections <<< "libc6 libraries/restart-without-asking boolean true"
sudo debconf-set-selections <<< "postfix postfix/main_mailer_type select No configuration"

# Executar atualização com parâmetros para reinicializar serviços automaticamente
sudo apt-get -o Dpkg::Options::="--force-confnew" \
             -o Dpkg::Options::="--force-confdef" \
             --allow-downgrades --allow-remove-essential --allow-change-held-packages \
             update && sudo apt-get upgrade -yq

# Step 2: Desabilitar o swap e definir parâmetros essenciais do kernel 
print_status "Desabilitando o Swap"
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Etapa 3: Carregar os módulos do kernel necessários
print_status "Carregando módulos do kernel"
sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# Configurar parâmetros críticos do kernel para Kubernetes
sudo tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

# Recarregar as alterações
sudo sysctl --system

# Etapa 4: Instalar Containerd Runtime
print_status "Instalando dependências..."
sudo apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates

# Habilitar repositório Docker
print_status "Habilitando repositório Docker para Ubuntu 22.04"
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/docker.gpg
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu jammy stable"

# Atualizar a lista de pacotes e instalar containerd
print_status "Atualizando lista de pacotes e instalando containerd"
sudo apt update
sudo apt install -y containerd.io

# Configurar containerd para usar systemd como cgroup
print_status "Configurando containerd para usar systemd como cgroup"
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Reiniciar e habilitar o serviço containerd
print_status "Reiniciando e habilitando containerd"
sudo systemctl restart containerd
sudo systemctl enable containerd

# Etapa 5: Adicionar repositório Apt para Kubernetes
print_status "Adicionando repositório Kubernetes para Ubuntu 22.04"
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Etapa 6: Instalar Kubectl, Kubeadm e Kubelet
sudo apt update
print_status "Instalando kubeadm, kubelet e kubectl"
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Habilitando o serviço do kubelet
# Por fim, vamos habilitar o serviço do kubelet para que ele inicie automaticamente com o sistema:
sudo systemctl enable --now kubelet
