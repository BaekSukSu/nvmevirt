#!/bin/bash

# 1. 마운트 해제
sudo umount /dev/nvme0n1

# 2. 커널 모듈 제거 
sudo rmmod nvmev