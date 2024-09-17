#!/bin/bash

# Script de instalação do kubeadm, kubelet e kubectl
# Para uso em sistemas baseados em Ubuntu/Debian
# Script deve rodar ate o Step 6 em (all nodes)

# Função para exibir mensagens de status
print_status() {
    echo ">>> $1"
}

# Verificar se o script está sendo executado como root
if [[ $EUID -ne 0 ]]; then
   echo "Este script deve ser executado como root (use sudo)" 
   exit 1
fi

# Step 1: Atualizar o sistema
print_status "Atualizando o sistema..."
sudo apt update && sudo apt upgrade -y

# Step 2: Desabilite o swap e defina parâmetros essenciais do kernel 
print_status "Desabilitando o Swap"
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Etapa 3: Carregue os módulos do kernel necessários em todos os nós
print_status "Adicionar parâmetros do kernel"
sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# Configure os parâmetros críticos do kernel para o Kubernetes
sudo tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

# Em seguida, recarregue as alterações
sudo sysctl --system

# Etapa 4: instalar o Containerd Runtime
print_status "Instalando dependências..."
sudo apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates

# Habilite o repositório Docker
print_status "Habilite o repositório Docker"
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/docker.gpg
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# Atualize a lista de pacotes e instale o containerd
print_status "Atualize a lista de pacotes e instale o containerd"
sudo apt update
sudo apt install -y containerd.io

# Configure o containerd para começar a usar o systemd como cgroup
print_status "Configure o containerd para começar a usar o systemd como cgroup"
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

# Reinicie e habilite o serviço containerd
print_status "Reinicie e habilite o serviço containerd"
sudo systemctl restart containerd
sudo systemctl enable containerd

# Etapa 5: Adicionar repositório Apt para Kubernetes
print_status "Etapa 5: Adicionando o repositório do Kubernetes..."
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Etapa 6: instalar Kubectl, Kubeadm e Kubelet
sudo apt update
print_status "Instalando kubeadm, kubelet e kubectl..."
sudo apt install -y kubelet kubeadm kubectl
# Marcar os pacotes para não serem atualizados automaticamente
sudo apt-mark hold kubelet kubeadm kubectl
