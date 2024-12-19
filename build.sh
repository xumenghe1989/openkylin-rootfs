#!/bin/bash

set -e -u

sudo apt update

# 不进行交互安装
export DEBIAN_FRONTEND=noninteractive
ROOTFS=`mktemp -d`
dist_version="nile"
dist_name="openkylin"
readarray -t REPOS < ./config/apt/sources.list
PACKAGES=`cat ./config/packages.list/packages.list | grep -v "^-" | xargs | sed -e 's/ /,/g'`
OUT_DIR=$(dirname "$(realpath "$0")")/rootfs

mkdir -p $OUT_DIR
sudo apt install -y curl git mmdebstrap qemu-user-static usrmerge usr-is-merged binfmt-support systemd-container
# 开启异架构支持 
sudo systemctl start systemd-binfmt

# 安装软件包签名公钥 
curl http://archive.build.openkylin.top/openkylin/pool/main/o/openkylin-keyring/openkylin-keyring_2022.05.12-ok1_all.deb --output openkylin-keyring.deb
sudo apt install ./openkylin-keyring.deb && rm ./openkylin-keyring.deb

curl http://archive.build.openkylin.top/openkylin/pool/main/o/openkylin-archive-anything/openkylin-archive-anything_2023.02.06-ok4_all.deb --output openkylin-archive-anything.deb
sudo apt install ./openkylin-archive-anything.deb && rm ./openkylin-archive-anything.deb

for arch in amd64 arm64; do
    sudo mmdebstrap \
        --hook-dir=/usr/share/mmdebstrap/hooks/merged-usr \
        --include=$PACKAGES \
        --components="main,cross,pty" \
        --variant=minbase \
        --architectures=${arch} \
        --customize=./config/hooks.chroot/second-stage \
        $dist_version \
        $ROOTFS \
        "${REPOS[@]}"

    # 创建一个空的磁盘镜像文件
    IMG_FILE=$OUT_DIR/$dist_name-rootfs-$arch.img
    IMG_SIZE=4G  # 设置镜像文件的大小，你可以根据需要调整大小

    # 创建一个空的磁盘镜像文件
    dd if=/dev/zero of=$IMG_FILE bs=1M count=0 seek=$IMG_SIZE

    # 格式化该磁盘镜像为 ext4 文件系统
    sudo mkfs.ext4 $IMG_FILE

    # 挂载镜像文件
    MOUNT_DIR=$(mktemp -d)
    sudo mount -o loop $IMG_FILE $MOUNT_DIR

    # 将根文件系统内容从临时目录复制到镜像文件中
    sudo rsync -a $ROOTFS/ $MOUNT_DIR/

    # 卸载镜像文件
    sudo umount $MOUNT_DIR
    sudo rmdir $MOUNT_DIR

    # 删除临时文件夹
    sudo rm -rf  $ROOTFS

    # 打包成 .img 文件（已经是镜像文件，不需要额外压缩）
    echo "Generated: $IMG_FILE"
done
