# hashize - 개발 히스토리

## 프로젝트 개요
**프로젝트명:** hashize  
**버전:** 1.0.7  
**작성자:** domuji6@gmail.com  
**목적:** 파일/디렉토리 크기를 트리 구조로 시각화

## 파일 위치
- 소스 코드: `/mnt/data5/script/df/hashize.sh`
- 바이너리: `/mnt/data5/script/df/hashize`

## 주요 기능

### 옵션
- `-s` : 크기순 정렬 (기본값)
- `-n` : 이름순 정렬
- `-t` : 날짜순 정렬 (날짜 표시)
- `-f` : 파일만 표시
- `-d` : 디렉토리만 표시
- `-D NUM` : 디렉토리 N개만 표시
- `-L NUM` : 파일 N개만 표시
- `-c, --no-color` : 색상 비활성화
- `-h, --help` : 도움말
- `-v, --version` : 버전

### 표시
- 파란색: 디렉토리 (`/` 접미사)
- 초록색: 파일
- 회색: 숨겨진 항목 (`more directory(+N)`)
- 기본 깊이: 2 (변경 가능)

## 버전 히스토리

### v1.0.7 (2025-10-30)
SIGPIPE 처리 완료:
- `printf -v line` 로 변수에 저장
- `if ! printf "%s" "$line" 2>/dev/null` 로 실패 감지
- 실패 시 임시 파일 정리 후 return
- stderr 리다이렉트로 "Broken pipe" 제거

임시 파일 관리:
- `remove_temp_file()` 함수 추가
- cleanup 트랩으로 종료 시 정리

### v1.0.6 (2025-10-30)
- SIGPIPE 처리 시도 (불완전)
- stderr에 "Broken pipe" 반복 출력

### v1.0.5 (2025-10-30)
- trap 메모리 누수 수정
- du/stat/numfmt 실패 처리 추가
- `--no-color` 옵션 추가

### v1.0.4 (2025-10-30)
- 고정폭 포맷 제거
- 날짜 포맷 최적화

### v1.0.3 (2025-10-30)
- 날짜순 정렬 시 날짜 표시

### v1.0.2 (2025-10-30)
- `-t` 옵션 추가

### v1.0.1 (2025-10-29)
- 구분자를 파이프에서 탭으로 변경
- `du -sb` 사용으로 정렬 정확도 개선

### v1.0.0 (2025-10-29)
- 최초 릴리즈

## 기술 세부사항

### 의존성
- GNU coreutils (du, stat, numfmt)
- Linux (stat -c 형식)
- bash 4.0+

### 핵심 구현

**SIGPIPE 처리:**
```bash
trap "cleanup; exit 0" PIPE
printf -v line "format" args...
if ! printf "%s" "$line" 2>/dev/null; then
    remove_temp_file "$temp_file"
    return 0
fi
```

**임시 파일:**
```bash
TEMP_FILES=()
cleanup() {
    for f in "${TEMP_FILES[@]}"; do
        rm -f "$f" 2>/dev/null
    done
}
```

**크기 계산:**
- 정렬: `du -sb`
- 표시: `numfmt --to=iec-i --suffix=B`

**날짜 처리:**
- 정렬: `stat -c %Y`
- 표시: `stat -c "%y" | cut -d. -f1`

### 컴파일
```bash
shc -r -f hashize.sh
gcc hashize.sh.x.c -o hashize
strip hashize
```
크기: ~28KB

## 제한사항
- 성능: 대형 디렉토리에서 `du -sb` 개별 호출로 느림 (v1.0.10에서 해결)
- 플랫폼: Linux 전용
- 의존성: GNU coreutils 필요

## 코드 리뷰 반영 내역

v1.0.7:
- SIGPIPE "Broken pipe" 제거
- printf 실패 즉시 복귀
- stderr 리다이렉트

v1.0.5:
- trap 메모리 누수 수정
- 명령어 실패 처리
- no-color 옵션

v1.0.1:
- 파이프 구분자 이슈 수정
- 크기 정렬 정확도 개선

## 사용 예제

```bash
# 기본
hashize /var/www

# 날짜순
hashize -t -D 5 /var/log 3

# 파일만
hashize -f -n /tmp

# 파이프
hashize /var/log | head -20
hashize /tmp | less
```

## 설치
```bash
sudo cp /mnt/data5/script/df/hashize /usr/local/bin/
```

## 테스트 검증

SIGPIPE:
- `hashize . 1 | head` - 에러 없음
- `hashize /tmp 3 | head -5` - 정상

임시 파일:
- 정상 종료 시 정리
- Ctrl+C 종료 시 정리
- SIGPIPE 종료 시 정리

## 개발 노트

SIGPIPE 해결 과정:
1. `trap '' PIPE` - bash printf stderr 출력 지속
2. `trap 'exit 0' PIPE` - 에러 메시지 반복
3. printf 분리 + 실패 감지 + stderr 리다이렉트 - 해결

핵심:
- bash 내장 printf는 SIGPIPE 시 stderr 출력
- `2>/dev/null` 리다이렉트 필수
- 실패 감지 후 즉시 정리 필요

---
최종 업데이트: 2025-10-30  
관리자: domuji6@gmail.com  
버전: 1.0.7

### v1.0.8 (2025-10-31)
Ctrl+C 취소 기능 추가:
- `CANCELLED` 플래그 추가로 실행 중단 상태 추적
- `handle_sigint()` 함수로 SIGINT(Ctrl+C) 즉시 처리
- 재귀 함수 여러 지점에 취소 체크포인트 추가:
  - 재귀 함수 시작 시
  - 파일 루프 중
  - `du` 명령 실행 후
  - 출력 루프 중
  - 재귀 호출 후
- 취소 시 "Operation cancelled by user." 메시지 출력
- 종료 코드 130 (SIGINT 표준) 반환
- 임시 파일 정리 보장

변경 내용:
```bash
CANCELLED=false

handle_sigint() {
    CANCELLED=true
    echo -e "\n\nOperation cancelled by user." >&2
    cleanup
    exit 130
}

trap handle_sigint INT

# 각 주요 지점에서 체크
if [ "$CANCELLED" = true ]; then
    remove_temp_file "$temp_file"
    return 1
fi
```

효과:
- 대용량 디렉토리 처리 중 Ctrl+C로 즉시 중단 가능
- 잘못된 경로로 실행해도 빠르게 취소 가능
- 리소스 누수 없이 깔끔하게 종료

---
최종 업데이트: 2025-10-31  
관리자: domuji6@gmail.com  
버전: 1.0.8

### v1.0.8 (2025-10-31)
Ctrl+C 취소 기능 추가:
- `CANCELLED` 플래그 추가로 실행 중단 상태 추적
- `handle_sigint()` 함수로 SIGINT(Ctrl+C) 즉시 처리
- 재귀 함수 여러 지점에 취소 체크포인트 추가:
  - 재귀 함수 시작 시
  - 파일 루프 중
  - `du` 명령 실행 후
  - 출력 루프 중
  - 재귀 호출 후
- 취소 시 "Operation cancelled by user." 메시지 출력
- 종료 코드 130 (SIGINT 표준) 반환
- 임시 파일 정리 보장

변경 내용:
```bash
CANCELLED=false

handle_sigint() {
    CANCELLED=true
    echo -e "\n\nOperation cancelled by user." >&2
    cleanup
    exit 130
}

trap handle_sigint INT

# 각 주요 지점에서 체크
if [ "$CANCELLED" = true ]; then
    remove_temp_file "$temp_file"
    return 1
fi
```

효과:
- 대용량 디렉토리 처리 중 Ctrl+C로 즉시 중단 가능
- 잘못된 경로로 실행해도 빠르게 취소 가능
- 리소스 누수 없이 깔끔하게 종료

---
최종 업데이트: 2025-10-31  
관리자: domuji6@gmail.com  
버전: 1.0.8

### v1.0.8 (2025-10-31)
Ctrl+C 취소 기능 추가:
- CANCELLED 플래그 추가로 실행 중단 상태 추적
- handle_sigint() 함수로 SIGINT(Ctrl+C) 즉시 처리
- 재귀 함수 여러 지점에 취소 체크포인트 추가
- 취소 시 "Operation cancelled by user." 메시지 출력
- 종료 코드 130 반환
- 임시 파일 정리 보장

효과:
- 대용량 디렉토리 처리 중 Ctrl+C로 즉시 중단 가능
- 잘못된 경로로 실행해도 빠르게 취소 가능
- 리소스 누수 없이 깔끔하게 종료

---
최종 업데이트: 2025-10-31
관리자: domuji6@gmail.com
버전: 1.0.8

### 추가 개선 사항 (v1.0.8)
입력 검증 및 에러 처리 강화:
- `usage()` 함수가 종료 코드를 인자로 받도록 개선
  - 정상적인 help 호출: exit 0
  - 오류 상황: exit 1 (스크립트 체이닝 지원)
- max_depth 인자 검증 추가
  - 숫자가 아닌 값 입력 시 명확한 에러 메시지
  - 예: `hashize /tmp foo` → "Error: max_depth must be a non-negative integer"
- 모든 에러 메시지를 stderr(>&2)로 리다이렉션하여 로깅 친화적
- 잘못된 옵션 처리 개선

사용 예시:
```bash
# 에러 시 exit 1 반환
hashize || echo "Failed"
hashize /tmp abc && echo "Success"  # max_depth 검증 실패로 실행 안됨

# 정상적인 help는 exit 0
hashize -h && echo "Help OK"
```

### v1.0.9 (2026-09-09)
코드 품질 및 성능 개선:
- SIGINT 처리 시 정리 작업이 EXIT 트랩을 통해 한 번만 실행되도록 중복 호출 제거
- 취소 메시지를 `echo -e` 대신 `printf`로 출력
- ANSI 색상 코드를 Bash escape 문자열로 명확하게 정의
- `max_depth` 인자를 `MAX_DEPTH_ARG` 변수로 분리해 검증 로직 명확화
- 항목별 수정 시간 조회를 `stat` 2회에서 1회로 줄여 외부 명령 호출 감소
- 옵션 충돌 경고와 숫자 인자 오류를 stderr로 일관되게 출력
- 재귀 함수의 지역 변수명을 구체화해 가독성 개선

빌드 및 검증:
- `shc`와 `gcc`로 동적 실행 파일(`hashize`) 및 정적 실행 파일(`hashize_static`) 재빌드
- 동적/정적 바이너리와 `hashize.sh.x`에서 `hashize version 1.0.9` 출력 확인
- 문법 검사, 정렬, 출력 제한, 잘못된 인자 처리, SIGPIPE, SIGINT 종료 코드 130을 검증

---
최종 업데이트: 2026-09-09  
관리자: domuji6@gmail.com  
버전: 1.0.9

### v1.0.10 (2026-09-26)
성능 개선 (단일 탐색 구조):
- 항목마다 `du -sb`를 실행하던 구조를 제거하고, 시작 시 `du` 1회 + `find` 1회로 전체 메타데이터를 수집
  - 디렉토리 합계: `du -b -l -0 --max-depth=N`
  - 타입/파일 크기/자체 mtime: `find -printf` (NUL 구분)
  - 결과를 Bash 배열/연관 배열에 저장하고 트리 출력 시 조회
- 크기 변환을 `numfmt` 1회 호출로 일괄 처리, 항목별 `basename`/`stat`/`cut` 및 서브셸 제거
- 측정 (디렉토리 330개, 항목 6,630개): depth 2 3.20s → 0.16s, depth 3 36.71s → 1.96s, 출력 동일

동작 변경:
- 숨김(dot) 파일/디렉토리 표시 (기존 `"$dir"/*` 글롭에서 누락되던 문제)
- 탭/줄바꿈이 포함된 파일명 처리 (NUL 구분 레코드 사용)
- 심볼릭 링크는 따라가지 않고 파일로 표시 (끊어진 링크 포함)
- 하드링크는 `-l`로 링크마다 집계: 디렉토리 합계가 탐색 순서와 무관하게 하위 항목 합과 일치
- `-D`/`-L`로 항목이 숨겨질 때 마지막 표시 항목에 `└──` 대신 `├──` 사용 (요약 줄과 중복 방지)
- 임시 파일을 사용하지 않도록 변경, SIGTERM 수신 시 종료 코드 143으로 종료
- 이름순 정렬 키를 이름 필드로 한정 (`sort -k1,1`), 로케일에 따라 순서가 흔들리지 않도록 함
- `max_depth`에 `08`처럼 0으로 시작하는 값을 넣으면 8진수 오류가 나던 문제 수정 (v1.0.9부터 있던 버그)

요구사항:
- GNU findutils (`find -printf`) 추가, `stat` 불필요
- `hashize_static` 바이너리는 아직 v1.0.9 (재빌드 필요)

### v1.0.11 (2026-09-26)
`-f` 재귀 동작 수정:
- 기존: 디렉토리를 먼저 제외해서 하위로 내려가지 못함 (`hashize -f /data 3`도 최상위 파일만 표시)
- 변경: `max_depth`까지 모든 파일을 하나의 목록으로 표시하고, 이름 대신 상대 경로로 표기
- `-L N`은 전체 단계에서 상위 N개 파일 (예: `hashize -f -L 10 /var 3`)
- depth 1에서는 기존과 출력 동일, `-d` 동작은 변경 없음

대규모 디렉토리 메모리/성능 검증:
- 원인 확인: Bash 인덱스 배열은 연결 리스트라 무작위 조회가 O(N), 한 키에 반복 `+=`는 제곱 시간
  - 파일 10만 개가 한 디렉토리에 있으면 v1.0.10에서 118초 소요
- 수정: `find` 레코드를 (부모 디렉토리 ID, 정렬 키) 기준으로 `sort` 1회 정렬 후 위치를 키로 하는 연관 배열에 저장
  - 디렉토리마다 실행하던 `sort` 제거, `numfmt`도 같은 파이프라인에서 1회
  - `du` 1회 + `find` 1회 탐색 구조는 그대로 유지

측정 (실행 시간 / 가장 큰 프로세스의 peak RSS):

| 트리 | v1.0.10 | v1.0.11 |
|---|---|---|
| 10만 항목, depth 3 | 30.5s / 69MiB | 22.8s / 17MiB |
| 한 디렉토리에 파일 10만 개, depth 1 | 118.3s / 99MiB | 21.3s / 42MiB |
| 100만 항목, depth 1 | 2.1s / 10MiB | 2.0s / 10MiB |
| 100만 항목, depth 3 | 937.7s / 664MiB | 225.2s / 148MiB |
| 100만 항목, depth 3, `-f` | - | 217.6s / 403MiB |
| 100만 항목, depth 3, `-d` | - | 64.8s / 10MiB |

빌드 및 검증:
- `shc 4.0.3` + `gcc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0`로 정적 실행 파일(`hashize_static`) 재빌드 (`shc -r -f`, `gcc -static -O2`, `strip`)
- `hashize_static -v` → `hashize version 1.0.11`
- 바이너리와 스크립트 출력 비교 145개 조합 일치, 도움말/인자 오류/SIGPIPE(0)/SIGINT(130) 확인
- 스크립트 회귀 테스트 131개 통과 (v1.0.9·v1.0.10 출력 호환, `-f`/`-d`, `-D`/`-L`, depth 0/1/3/08, 숨김 파일, TAB/줄바꿈 파일명, 심볼릭/하드 링크, 시그널)
- SHA256: `105c33f43d1e02b851deeb7ed5b8208ea0300cf2e0056d385b101f4e092d09af`

---
최종 업데이트: 2026-09-26  
관리자: domuji6@gmail.com  
버전: 1.0.11
