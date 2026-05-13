# A100 서버 실행 가이드

ADR 0006 + migration_v2.md 의 batch 측 실행 절차. T1000 서버 의존성 없이 A100 단일 서버로 batch + serving 모두 운영.

## 사전 준비 (한 번만)

### 1. SSH 접속 + 코드 clone
```bash
# 사용자 노트북에서
ssh sosa8770@a100-server.example.org   # 또는 실제 호스트명
```

```bash
# A100 서버에서 (NFS home)
cd /home/sosa8770
git clone <repository_url> genofinder
cd genofinder
```

### 2. podman-compose 설치 (sudo 불필요)
```bash
pip install --user podman-compose
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
podman-compose --version  # 0.1.x 정도 나오면 OK
```

### 3. uv 설치 (Python 패키지 관리)
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env
uv --version
```

### 4. .env 작성
```bash
cp .env.a100.example .env
nano .env  # NVIDIA_GPU_DEVICE_ID 등 채우기
```

### 5. GPU 가용성 확인
```bash
nvidia-smi  # 6장 다 보임. 비어있는 번호 확인 (현재 3/4/5)
```

## 실행

### Phase 1 — Bootstrap (한 번만, ~30-60분, 모델 다운로드 위주)
```bash
cd ~/genofinder
bash scripts/a100-bootstrap.sh
```

이 스크립트가 수행:
1. NFS 디렉터리 생성 (`$GENOFINDER_DATA_ROOT/{ollama-models,postgres-data,...}`)
2. podman-compose 로 stack 기동 (postgres / redis / qdrant / opensearch / ollama / kms)
3. Alembic 마이그레이션 0001~0004 적용
4. Ollama 모델 pull:
   - `gemma3:27b-it-bf16` (~54GB)
   - `qwen3-embedding:8b` (~16GB)
   - Qwen3-Reranker-0.6B 은 sentence-transformers 가 첫 호출 시 자동 다운로드

⚠️ 모델 다운로드 시간은 NFS 쓰기 속도에 따라 다름. 보통 10-30분.

### Phase 2 — Batch pipeline (6-10시간, 야간 권장)
```bash
# tmux / screen 으로 길게 돌릴 것
tmux new -s genofinder-batch
bash scripts/a100-batch-pipeline.sh 10000 500
# 인자: GEO_LIMIT TRANSLATE_TOP_N
# Ctrl-B D 로 detach. 나중에 'tmux a -t genofinder-batch' 로 재접속
```

이 스크립트가 수행:
1. Harvest (GEO + HCA + GDC + SRA) — 1-2시간
2. LLM 추출 (modality + ontology + cohort, Gemma 3 27B BF16) — 2-3시간
3. Sample-level metadata backfill (GEO Series Matrix) — 1-2시간
4. Embedding 인덱싱 (Qwen3-8B → 1024d Matryoshka) — 1-2시간
5. Translate cache 사전 채우기 (top 500 데이터셋, 한국어) — 1-2시간
6. Dump 생성 (`$DATA_ROOT/dumps/<timestamp>.tar.gz`)

### Phase 3 — Serving (검증 / 데모)
```bash
cd ~/genofinder
podman-compose --env-file .env \
               -f infra/compose/docker-compose.dev.yml \
               -f infra/compose/docker-compose.a100.yml \
               up -d api web

# 확인
curl http://localhost:8000/api/v1/health
curl http://localhost:8000/api/v1/stats  # GEO/HCA/GDC/SRA 카운트
```

웹: `http://<A100_HOST_IP>:3000` — 외부 노출 시 reverse proxy (Caddy / nginx) 권장.

논문 데모용 screenshot 은 localhost 또는 SSH X11 forwarding 으로 충분.

## 모니터링

```bash
# 컨테이너 상태
podman ps

# GPU 사용량 (Gemma 27B BF16 점유 시 ~54GB)
nvidia-smi --id=3

# Ollama 모델 로드 상태
podman exec genofinder-dev-ollama ollama ps

# 디스크
du -sh $GENOFINDER_DATA_ROOT/*

# API 로그
podman logs -f genofinder-dev-api

# Workers 로그 (harvest / extraction 진행)
podman logs -f genofinder-dev-workers
```

## 트러블슈팅

### Q: podman-compose 가 `nvidia.com/gpu=N` device 못 찾음
A: `nvidia-container-toolkit` 의 CDI spec 등록 확인:
```bash
nvidia-ctk cdi list
# 'nvidia.com/gpu=3' 등이 보여야 함
```
없으면 admin 에게 `nvidia-ctk cdi generate` 실행 부탁.

### Q: 모델 다운로드가 NFS 쓰기 속도로 느림
A: 로컬 SSD 의 `/dev/shm` 으로 임시 다운로드 후 NFS 로 mv:
```bash
# Option: 모델은 임시 ramdisk 에 두면 빠르지만 휘발성. 처음 한 번만 NFS 다운로드 권장.
```

### Q: A100 GPU 3 가 다른 사용자에 의해 점유됨
A: `nvidia-smi` 로 확인 후 비어있는 다른 GPU 로:
```bash
# .env 의 NVIDIA_GPU_DEVICE_ID 변경 + podman-compose down + up
```

### Q: Gemma 3 27B 가 BF16 으로 OOM
A: Q4 로 다운그레이드:
```bash
# .env 또는 docker-compose.a100.yml 의 OLLAMA_MODEL_EXTRACTION 변경
OLLAMA_MODEL_EXTRACTION=gemma3:27b-it-q4_K_M  # ~14GB
```

## 다른 서버 (예: T1000) 로 이주

A100 의 dump bundle 을 다른 서버로:
```bash
# A100 측
scp $DATA_ROOT/dumps/<timestamp>.tar.gz user@other-host:/tmp/

# Other 측 — migration_v2.md §4 의 restore 절차 따름
```
