#!/bin/bash

# === 환경 설정 ===
MOUNT="/home/inho/mnt"
FILE="${MOUNT}/testfile.dat"
# 2GB storage, OP 7%, ext4 overhead ~5%  → 안전하게 1.5G 단일 파일 사용
TOTAL_SIZE="1536M"
HOT_SIZE="150M"                    # Honey Pot 구역 크기 (약 10%)
IO_PER_PHASE="1024M"               # 각 페이즈당 쏟아부을 I/O 양 (GC 유발용)

echo "기존 테스트 데이터 파일을 정리합니다..."
rm -f ${MOUNT}/testfile.dat ${MOUNT}/base_fill* ${MOUNT}/honeypot.dat
echo "정리 완료."

# 1. 기초 다지기 (Cold Baseline)
# 단일 파일로 전체 영역을 순차적으로 채워 모든 블록을 Valid Page로 가득 채웁니다.
echo "Step 1: Sequential Fill (${TOTAL_SIZE})..."
fio --name=base_fill --filename=${FILE} --direct=1 --ioengine=libaio \
    --rw=write --bs=128k --size=${TOTAL_SIZE} --numjobs=1 --group_reporting

if [ $? -ne 0 ]; then
    echo "Error: Fill phase failed."
    exit 1
fi

# 2. 첫 번째 Honey Pot 생성 (Region A: 0~150M)
# 같은 파일의 0~150M 구역에 쓰기를 집중합니다.
# 이 구역의 블록들은 '최근에 쓰인 Hot + 낮은 VPC' 상태가 됩니다.
echo "Step 2: Making Honey Pot A (0 ~ ${HOT_SIZE})..."
fio --filename=${FILE} --direct=1 --ioengine=libaio \
    --rw=randwrite --bs=4k --size=${HOT_SIZE} --offset=0 \
    --random_distribution=zipf:1.2 --io_size=${IO_PER_PHASE} \
    --name=hot_a --group_reporting --allow_file_create=0

echo "Step 2 완료. Region A aging을 위해 5초 대기..."
sleep 5

# 3. 쓰기 지점 이동 (Region B: 150M~300M)
# 이제 Region A는 방치됩니다. 시간이 흐르며 Region A의 Age는 올라갑니다 (Honey Pot 완성).
# Greedy는 VPC가 낮은 line을 우선하고, C-B는 Age가 높은 line을 더 선호합니다.
echo "Step 3: Moving Hot Spot to Region B (${HOT_SIZE} ~ 300M)..."
fio --filename=${FILE} --direct=1 --ioengine=libaio \
    --rw=randwrite --bs=4k --size=${HOT_SIZE} --offset=${HOT_SIZE} \
    --random_distribution=zipf:1.2 --io_size=${IO_PER_PHASE} \
    --name=hot_b --group_reporting --allow_file_create=0

echo "Step 3 완료. Region B aging을 위해 5초 대기..."
sleep 5

# 4. 최종 혼합 워크로드 (성능 측정 구간)
# 전체 영역에 대해 쓰기를 수행하며 GC 정책간의 WAF 차이를 극명하게 확인합니다.
echo "Step 4: Final Stress Test (Full Range)..."
fio --filename=${FILE} --direct=1 --ioengine=libaio \
    --rw=randwrite --bs=4k --size=${TOTAL_SIZE} \
    --random_distribution=zipf:1.1 --io_size=2G \
    --name=final_stress --group_reporting --allow_file_create=0

echo "테스트 완료!"