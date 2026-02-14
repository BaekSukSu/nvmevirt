#!/bin/bash

# 커널 모듈 적재
sudo insmod ./nvmev.ko gc_policy=1 memmap_start=4G memmap_size=2G cpus=1,2,3,4

sleep 0.5

# 파일 시스템 생성 (전체 장치 강제 포맷)
sudo mkfs.ext4 -F /dev/nvme1n1

# 마운트 포인트 생성 및 연결
mkdir -p /home/inho/mnt
sudo mount /dev/nvme1n1 /home/inho/mnt

# 소유권 변경 (현재 사용자에게 권한 부여)
sudo chown inho:inho /home/inho/mnt