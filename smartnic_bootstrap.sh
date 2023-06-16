#!/bin/bash
set -x

{
sudo echo -e "\n\n ============ INSTALLATION IS IN PROGRESS =========== " | sudo tee /etc/motd
sudo date | sudo tee -a /etc/motd

cat /local/repository/source/bashrc_template | sudo tee /root/.bashrc

DEBIAN_FRONTEND=noninteractive sudo apt-get update -y

sudo echo -e "\nInstalling xfce and vnc server..."
DEPS="tightvncserver lightdm lxde xfonts-base libnss3-dev firefox"
DEBIAN_FRONTEND=noninteractive sudo apt-get install -y --no-install-recommends $DEPS

sudo echo -e "\nInstalling DOCA SDKMANAGER dependencies..."
DOCA_SDK_MAN_DEP="gconf-service gconf-service-backend gconf2-common libcanberra-gtk-module libcanberra-gtk0 libgconf-2-4"
DEBIAN_FRONTEND=noninteractive sudo apt-get install -y --no-install-recommends $DOCA_SDK_MAN_DEP

#setting up extra storage
sudo echo -e "\nSet permissions for /mydata"
sudo chmod -R 777 /mydata

sudo echo -e "\nInstalling DOCKER and its dependencies..."
#install dependencies for docker
DOCKER_DEP="apt-transport-https ca-certificates curl gnupg lsb-release"
DEBIAN_FRONTEND=noninteractive sudo apt-get install -y --no-install-recommends $DOCKER_DEP
#install certificate for docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
#install docker
DOCKER="docker-ce docker-ce-cli containerd.io"
DEBIAN_FRONTEND=noninteractive sudo apt-get install -y --no-install-recommends $DOCKER

#dpdk dependencies
DPDK_DEP="libc6-dev libpcap0.8 libpcap0.8-dev libpcap-dev meson ninja-build libnuma-dev python3-pyelftools"
DEBIAN_FRONTEND=noninteractive sudo apt-get install -y --no-install-recommends $DPDK_DEP

sudo echo -e "\nStopping docker daemon and update location for downloading sources..."
sudo /etc/init.d/docker stop
#define new location in docker daemon.json
sudo echo -e "{\n\t\"data-root\":\"/mydata/docker\"\n}" | sudo tee /etc/docker/daemon.json
#rsync old docker files to new locations
rsync -aP /var/lib/docker/ /mydata/docker
#restart docker
/etc/init.d/docker restart


sudo echo -e "\nInstalling MLNX driver..."
#sudo echo -e "\nCopy to /opt..."
cd /opt
sudo echo -e "\nDownloading driver to /opt..."
sudo wget  http://www.mellanox.com/downloads/ofed/MLNX_OFED-5.3-1.0.0.1/MLNX_OFED_LINUX-5.3-1.0.0.1-ubuntu20.04-x86_64.tgz
#sudo cp /local/repository/source/MLNX_OFED_LINUX-5.3-1.0.0.1-ubuntu20.04-x86_64.tgz /opt
#sudo cd /opt
sudo echo -e "\nUncompress..."
sudo tar -xzvf MLNX_OFED_LINUX-5.3-1.0.0.1-ubuntu20.04-x86_64.tgz

cd /opt/MLNX_OFED_LINUX-5.3-1.0.0.1-ubuntu20.04-x86_64/
sudo echo -e "\nInstall driver..."
sudo ./mlnxofedinstall --auto-add-kernel-support --without-fw-update --force
cd ..

sudo echo -e "\nEnable openibd"
sudo /etc/init.d/openibd restart

sudo echo -e "\nEnable rshim"
sudo systemctl enable rshim
sudo systemctl start rshim
sudo systemctl status rshim


sudo echo "DISPLAY_LEVEL 1" | sudo tee /dev/rshim0/misc

sudo echo -e "\nUpdate netplan to assign IP to tmfifo_net0..."
sudo cp /local/repository/source/01-netcfg.yaml /etc/netplan/
sudo systemctl restart systemd-networkd
sudo netplan apply

sudo ifconfig tmfifo_net0

sudo echo -e "\nEnable IP forwarding for the SmartNIC"
sudo echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward
sudo iptables -t nat -A POSTROUTING -o eno1 -j MASQUERADE
sudo iptables -A FORWARD -o eno1 -j ACCEPT
sudo iptables -A FORWARD -m state --state ESTABLISHED,RELATED -i eno1 -j ACCEPT

sudo mst start
for i in $(sudo mst status -v|grep BlueField|awk '{print $2}')
do
  echo "dev: ${i}"
  sudo mlxconfig -d $i q | grep -i internal_cpu
done
echo -e "\n\nTo change mode: mlxconfig -d /dev/mst/mt41686_pciconf0 s INTERNAL_CPU_MODEL=1"


sudo echo -e "\nInstalling DPDK..."
cd /opt
sudo wget https://fast.dpdk.org/rel/dpdk-22.11.2.tar.xz
sudo tar -xJvf dpdk-22.11.2.tar.xz
cd dpdk-stable-22.11.2
export RTE_SDK=/opt/dpdk-stable-22.11.2
export RTE_TARGET=x86_64-native-linuxapp-gcc
sudo meson -Dexamples=all build
sudo ninja -C build
sudo ninja -C build install

sudo echo -e "\nInstalling pktgen..."
cd /opt

sudo wget https://git.dpdk.org/apps/pktgen-dpdk/snapshot/pktgen-dpdk-pktgen-23.06.1.tar.xz
sudo tar -xJvf pktgen-dpdk-pktgen-23.06.1.tar.xz
cd pktgen-dpdk-pktgen-23.06.1/
sudo make
sudo ldconfig

cd Builddir/
sudo ninja install

sudo echo -e "\nEnabling hugepages..."
sudo echo 1024 | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
mountpoint -q /dev/hugepages || mount -t hugetlbfs nodev /dev/hugepages

# FORBIDDEN - HAVE TO BE LOGGED IN :(
# cd ..
# sudo echo -e "\nInstall mlnx-dpdk..."
# wget https://developer.nvidia.com/networking/secure/doca-sdk/DOCA_1.0/DOCA_10_b163/ubuntu2004/mlnx-dpdk_20.11-1mlnx1_amd64.deb
# wget https://developer.nvidia.com/networking/secure/doca-sdk/DOCA_1.0/DOCA_10_b163/ubuntu2004/mlnx-dpdk-dev_20.11-1mlnx1_amd64.deb
# DEBIAN_FRONTEND=noninteractive dpkg --force -i mlnx-dpdk_20.11-1mlnx1_amd64.deb

# sudo echo -e "\nInstall rxptools and dpi tools..."
# wget https://developer.nvidia.com/networking/secure/doca-sdk/DOCA_1.0/DOCA_10_b163/ubuntu1804_ubuntu2004/rxp-compiler_21.02.3_amd64.deb
# wget https://developer.nvidia.com/networking/secure/doca-sdk/DOCA_1.0/DOCA_10_b163/ubuntu2004/rxpbench_21.03_20210401_0_ubuntu_20_amd64.deb
# wget https://developer.nvidia.com/networking/secure/doca-sdk/DOCA_1.0/DOCA_10_b163/ubuntu2004/doca-dpi-tools_21.03.038-1_amd64.deb

sudo echo -e "\n\n ============ DONE =========== "
sudo echo -e "\n\n ============ INSTALLATION FINISHED =========== "
sudo date | sudo tee -a /etc/motd

} 2>&1 | sudo tee /opt/install_log
