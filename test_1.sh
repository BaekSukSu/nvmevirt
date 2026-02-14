#!/bin/bash

# 테스트 설정
DEV_NAME="nvme1n1"
MOUNT_POINT="/home/inho/mnt"
TEST_FILE="$MOUNT_POINT/test_file"
IO_SIZE="1536M"  # 장치 크기(~1.9GB)에 맞춰 1.5GB로 축소

mkdir -p $LOG_DIR

echo "기존 테스트 데이터 파일을 정리합니다..."
rm -f $TEST_FILE
echo "정리 완료"

# 1. Base Fill (Full Capacity with Cold Data)
echo "Step 1: Base Fill (Cold Data)..."
fio --name=base_fill --filename=$TEST_FILE --rw=write --bs=128k \
    --size=$IO_SIZE --ioengine=libaio --iodepth=1 --group_reporting

echo "Step 1 완료. 데이터 Aging을 위해 5초 대기..."
sleep 5

# 2. Make "Old but Slightly Dirty" Blocks (The Decoy)
# 전체 디스크에 드문드문 랜덤 쓰기를 수행하여,
# 많은 블록들이 "오래되었지만(Old) 약간의 무효 페이지(Invalid)"를 가지게 만듭니다.
# Cost-Benefit 정책은 '나이(Age)' 가중치 때문에 이 블록들을 선택할 가능성이 높습니다.
echo "Step 2: Scattering Invalidation (Creating Decoys)..."
fio --name=scatter_dirty --filename=$TEST_FILE --rw=randwrite --bs=4k \
    --size=$IO_SIZE --io_size=256M --random_distribution=random \
    --ioengine=libaio --iodepth=1 --group_reporting --allow_file_create=0

echo "Step 2 완료. Aging을 위해 5초 대기..."
sleep 5

# 3. Intensive Burst Update (The Target)
# 아주 좁은 영역(Hot Spot)에 집중적으로 덮어쓰기를 수행합니다.
# 이 영역의 블록들은 "매우 젊지만(Young) 거의 전부 무효(Highly Invalid)"가 됩니다.
# Greedy는 즉시 이 효율적인 블록(Invalid 90%+)을 청소하지만,
# Cost-Benefit은 나이가 어리다는 이유로 무시하고 Step 2의 Decoy(Invalid 20%, Old)를 청소하러 갈 수 있습니다.
# -> 결과적으로 Cost-Benefit은 유효 페이지 복사(Copy Overhead)가 급증하여 성능이 떨어집니다.
echo "Step 3: Extreme Hot Spot Update (Greedy Friendly)..."
# 파일의 앞부분 150MB만 집중 공략
fio --name=hot_burst --filename=$TEST_FILE --rw=randwrite --bs=4k \
    --size=$IO_SIZE --io_size=1024M \
    --random_distribution=zipf:50 \
    --ioengine=libaio --iodepth=1 \
    --group_reporting --allow_file_create=0

echo "테스트 완료!"
