# Yujin OS (Grok Bot OS 포크)

원본: [head77x/grokbotos](https://github.com/head77x/grokbotos) (커밋 df02827). 설계: 「유진 OS v0 설계서」.

## 원본과 다른 점 (v0)
| 영역 | 원본 | Yujin OS |
|---|---|---|
| 부팅 화면 | 비공개 Grok Bot 앱 | 로컬 모델 채팅 화면 `http://127.0.0.1:8080` (`GROKBOT_DISABLE_BUNDLED_APP=1`) |
| 모델 | 없음(클라우드) | `yujin-llm` 서비스: llama.cpp `llama-server`(Vulkan) 컨테이너, `/var/models/current.gguf` |
| 모델 관리 | — | `yujin-model list · get · use · status` (Ollama 안 씀) |

에이전트는 OpenAI 호환 주소 `http://127.0.0.1:8080/v1` 하나로만 말한다. 모델을 바꿔도 OS·에이전트는 그대로다.

## 처음 켠 뒤
```
yujin-model get meta-models/Muse-Glimmer-30B-GGUF <파일이름>.gguf   # Hugging Face 페이지에서 파일 이름 확인
yujin-model use <파일이름>.gguf
yujin-model status
```
모델이 없으면 서버는 켜지지 않고(ConditionPathExists), 부팅 화면은 연결 실패로 보인다. 모델을 받은 뒤 다시 확인한다.

## 아직 안 한 것 (v1 이후)
- **로컬 에이전트 전용 권한 (11.20. 함):** `/etc/grokbot/api-permissions.json`의 `agents`에 적힌 systemd 서비스(`yujin-agent.service`)는 유진님 본인 프로그램으로 보지 않는다. 적힌 권한만 받고(읽기 포함) 나머지는 묻지도 않고 거부한다. 지금은 system·notifications 허용, files·files-write·apps 물어봄. `local` 기본값은 원본 그대로라 독·런처 동작은 바뀌지 않는다. 시험: `tests/grokbotd/test_agents.py`
- 바깥 연결 허용 목록(방화벽) — 지금은 제한 없음
- 로컬 에이전트 앱(지금은 llama-server 기본 채팅 화면)과 grokbotd MCP 연결
- 업데이트 서명 키를 이 포크 것으로 바꾸기(`policy.json`, `grokbotos.pub`, 저장소 비밀값 `SIGNING_SECRET`)
- 실기기·SELinux enforcing 검증
- ~~`llama.cpp` 이미지 태그를 digest로 고정~~ (11.20. 고정함)
