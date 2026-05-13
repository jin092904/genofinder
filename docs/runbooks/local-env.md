# Local Dev Environment — Runbook

> 본 문서는 사용자의 로컬 환경 (WSL2 Ubuntu + Windows 호스트) 의 검증 결과를 기록한다.
> 환경이 바뀌면 본 문서를 갱신하고 PR 의 Reviewer 가 재검토한다.

## 검증 일자: 2026-05-06

| 항목 | 값 | 출처 |
|---|---|---|
| OS | Linux 6.6.87.2-microsoft-standard-WSL2 | `uname -a` |
| systemd | 활성화 (`/etc/wsl.conf` 에 `[boot] systemd=true`, PID 366 running) | `pidof systemd` |
| sudo | 패스워드 필요 (passwordless 미설정) | `sudo -n true` 실패 |
| Python | 3.12.3 | `python3 --version` |
| `uv` | 0.10.9 | `uv --version` (전역 룰: pip 대신 uv) |
| Node | 20.20.2 | `node --version` |
| pnpm | 9.15.9 | corepack 활성화 후 `pnpm --version` |
| Docker | **미설치** | `docker --version` → not found |
| GPU / VRAM | **없음** — `nvidia-smi` 명령 자체 미존재. Ollama 는 CPU-only 운영 | (검증 2026-05-06) |
| RAM | 7.5 GiB total, 5.8 GiB available | `free -h` |
| Disk free | / 파티션 927 GB free (전체 1007 GB) | `df -h /` |

### Ollama 모델 크기 가이드 (CPU-only, 7.5 GB RAM)

GPU 가 없으므로 ADR 0004 (Week 3) 의 모델 후보를 다음 순서로 좁힌다:

| 모델 | RAM 필요 (Q4_K_M) | CPU 추정 throughput | 적합도 |
|---|---|---|---|
| Phi-4 mini (3.8B) | ~3 GB | 8-15 tok/s | ✓ 우선 후보 — 구조화 추출용 |
| Llama 3.1 8B Q4 | ~5 GB | 4-8 tok/s | ✓ Backup — 정확도 우선시 |
| Qwen 2.5 14B Q4 | ~9 GB | 1-3 tok/s | ✗ 메모리 한계 — 동시 컨테이너 고려 시 부적합 |
| nomic-embed-text (137M) | ~0.5 GB | 매우 빠름 | ✓ 임베딩용 |

→ ADR 0004 에서 **Phi-4 mini + nomic-embed-text** 조합을 1차 후보로 제안할 것.

## Docker 설치 (다음 단계)

WSL2 에 Docker Engine 을 직접 설치하는 방법:

```bash
# 1. 공식 설치 스크립트
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# 2. 사용자를 docker 그룹에 추가 (sudo 없이 docker 실행)
sudo usermod -aG docker $USER
newgrp docker

# 3. 테스트
docker --version
docker compose version
docker run --rm hello-world
```

대안: Windows 호스트에서 Docker Desktop 설치 후 WSL integration 활성화.

## GPU 확인 (Ollama 모델 선택 입력값)

```bash
nvidia-smi    # VRAM 확인
# < 8GB:  Llama 3.1 8B Q4 또는 Phi-4 mini
# 8-16GB: Llama 3.1 8B Instruct (Q8) 또는 Qwen 2.5 7B
# > 16GB: Qwen 2.5 14B / Llama 3.1 70B Q4
```

위 표는 ADR 0004 (모델 선택, Week 3) 의 입력으로 사용된다.

## `make dev` 기동 점검 (Docker 설치 후)

```bash
cd genofinder
cp .env.example .env       # 비밀번호 변경
make dev
make ps                    # 모든 컨테이너 healthy 확인
curl http://localhost:8000/api/v1/health   # FastAPI placeholder
curl http://localhost:3000                  # Next.js placeholder
# Ollama 는 host port 미공개 — workers/api 컨테이너에서만 접근
```
