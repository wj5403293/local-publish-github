#!/usr/bin/env bash
# 通用一键发布：预检 → 附件校验 → 提交 → 推送(快进) → tag(只建不改) → Release → 上传 → 校验
# 用法: publish.sh --dir DIR --version V [--repo owner/name] [--assets "a.zip b.zip"]
#        [--display-name 名称] [--notes-file CHANGELOG.md] [--notes-reviewed] [--confirmed|--dry-run]
#        [--create-repo --public] [--allow-overwrite] [--resume]
# 配置: 项目下 .publish.json 只作为「默认值」，命令行优先级更高。
set -uo pipefail
API="https://api.github.com"
UPLOADS="https://uploads.github.com"
TOKEN_FILE="${GITHUB_TOKEN_FILE:-$HOME/.config/dsh-go/github-token}"
DRY=0; CONFIRMED=0; NOTES_REVIEWED=0; CREATE=0; PUBLIC=0; ALLOW_OVERWRITE=0; RESUME=0; DRAFT=0; PRERELEASE=0; GEN_NOTES=0; OVERWRITE_FILES=0; JSON_OUT=0
DIR=""; REPO=""; V=""; DISPLAY=""; ASSETS=""; NOTES_FILE=""; NOTES=""; TAGPREFIX="v"
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="$2"; shift 2;;
    --repo) REPO="$2"; shift 2;;
    --version) V="$2"; shift 2;;
    --display-name) DISPLAY="$2"; shift 2;;
    --assets) ASSETS="$2"; shift 2;;
    --notes-file) NOTES_FILE="$2"; shift 2;;
    --notes) NOTES="$2"; shift 2;;
    --tag-prefix) TAGPREFIX="$2"; shift 2;;
    --dry-run) DRY=1; shift;;
    --notes-reviewed) NOTES_REVIEWED=1; shift;;
    --confirmed) CONFIRMED=1; shift;;
    --create-repo) CREATE=1; shift;;
    --public) PUBLIC=1; shift;;
    --allow-overwrite) ALLOW_OVERWRITE=1; shift;;
    --resume) RESUME=1; shift;;
    --draft) DRAFT=1; shift;;
    --prerelease) PRERELEASE=1; shift;;
    --generate-notes) GEN_NOTES=1; shift;;
    --overwrite-files) OVERWRITE_FILES=1; shift;;
    --json) JSON_OUT=1; shift;;
    *) echo "未知参数: $1"; exit 64;;
  esac
done
[ -n "$DIR" ] && [ -d "$DIR" ] || { echo "✗ --dir 无效: ${DIR:-<空>}"; exit 1; }
cd "$DIR" || exit 1
SLUG=$(basename "$DIR" | sed 's/[^A-Za-z0-9._-]/_/g')
STATUS="/tmp/gh-publish.$SLUG.status"
LOG="/tmp/gh-publish.log"
: > "$STATUS"
write(){ echo "$*" >> "$STATUS"; }
step(){ write "STEP=$*"; echo "== $* =="; }
fail(){ write "STATE=fail"; write "ERROR=$*"; echo "✗ $*"; exit 1; }
warn(){ write "WARN=$*"; echo "⚠ $*"; }

# 配置：只填未由命令行指定的值
if [ -f "$DIR/.publish.json" ]; then
  eval "$(python3 - "$DIR/.publish.json" "$REPO" "$DISPLAY" "$ASSETS" "$NOTES_FILE" <<'PY'
import json,sys,shlex
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
cur=dict(repo=sys.argv[2],display_name=sys.argv[3],assets=sys.argv[4],notes_file=sys.argv[5])
m={'repo':'REPO','display_name':'DISPLAY','assets':'ASSETS','notes_file':'NOTES_FILE'}
for k,var in m.items():
    if cur[k]: continue                      # 命令行优先
    v=d.get(k)
    if isinstance(v,list): v='\n'.join(v)
    if v: print(f'{var}={shlex.quote(str(v))}')
PY
)"
fi
[ -n "$REPO" ] || fail "缺少 --repo owner/name（或在 .publish.json 里配置）"
[ -n "$DISPLAY" ] || DISPLAY="$(basename "$DIR")"
[ -n "$V" ] || fail "缺少 --version（版本号必须由人确定）"
echo "$V" | grep -Eq '^[0-9A-Za-z][0-9A-Za-z._-]*$' || fail "版本号非法: $V"
echo "$TAGPREFIX" | grep -Eq '^[A-Za-z0-9._-]*$' || fail "tag 前缀非法"
TAG="$TAGPREFIX$V"
[ "$DRY" = "1" ] || [ "$CONFIRMED" = "1" ] || fail "拒绝发布：先把「版本号 + 本版更新内容」给用户确认，再加 --confirmed"
[ "$DRY" = "1" ] || [ "$NOTES_REVIEWED" = "1" ] || fail "拒绝发布：发布公告必须先给用户审核原文，审核通过后加 --notes-reviewed 再发布（禁止未经审核直接发）"
[ -f "$TOKEN_FILE" ] || fail "没有令牌（先点「存令牌」）"
PERM=$(stat -c '%a' "$TOKEN_FILE" 2>/dev/null || echo '')
[ "$PERM" = "600" ] || fail "令牌文件权限不是 600（现在 $PERM），先修权限"
TOKEN=$(cat "$TOKEN_FILE")
[ -n "$TOKEN" ] || fail "令牌文件是空的"
gh(){ # gh METHOD PATH [BODY_FILE]  —— 令牌走 stdin config，不进 argv
  local m="$1" p="$2" b="${3:-}"
  local args=(-sS --max-time 60 --config - -X "$m" -H 'Accept: application/vnd.github+json' -H 'Content-Type: application/json')
  [ -n "$b" ] && args+=(--data-binary "@$b")
  printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" | curl "${args[@]}" "$API$p"
}
write "STATE=running"; write "VERSION=$V"; write "TAG=$TAG"; write "REPO=$REPO"; write "PROJECT=$DIR"
echo "项目：$DIR"; echo "仓库：$REPO"; echo "版本：$V（tag $TAG）"

step "预检"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "不是 git 仓库"
BRANCH=$(git rev-parse --abbrev-ref HEAD)
[ -n "$BRANCH" ] && [ "$BRANCH" != "HEAD" ] || fail "当前不在分支上（detached HEAD），先切到分支"
git rev-parse HEAD >/dev/null 2>&1 || fail "仓库还没有提交"
# 令牌与仓库可达性
ME=$(gh GET /user | python3 -c "import json,sys;print(json.load(sys.stdin).get('login',''))" 2>/dev/null)
[ -n "$ME" ] || fail "GitHub 认证失败（令牌无效/无权限/网络不通）"
REPO_EXISTS=1
gh GET "/repos/$REPO" >/dev/null 2>&1 || REPO_EXISTS=0
if [ "$REPO_EXISTS" = "0" ]; then
  [ "$CREATE" = "1" ] || fail "仓库 $REPO 不存在：确认后加 --create-repo 建仓（默认私有，公开需再加 --public）"
fi
# tag 预检：只查 ref，不只看 Release
TAG_EXISTS=$(gh GET "/repos/$REPO/git/ref/tags/$TAG" 2>/dev/null | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('ref',''))" 2>/dev/null)
[ -z "$TAG_EXISTS" ] || fail "tag $TAG 已存在：改版本号再发（脚本不会移动已有 tag）"
# 远端 head 与本地 base
REMOTE_HEAD=$(gh GET "/repos/$REPO/git/ref/heads/$BRANCH" 2>/dev/null | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('object',{}).get('sha',''))" 2>/dev/null)
if [ -n "$REMOTE_HEAD" ]; then
  if ! git cat-file -e "$REMOTE_HEAD" 2>/dev/null; then
    [ "$ALLOW_OVERWRITE" = "1" ] || fail "远端 $BRANCH 有本地没有的提交（$REMOTE_HEAD）：先同步，或确认后加 --allow-overwrite"
  fi
fi

step "隐私/密钥扫描"
BAD=$(grep -rIlE "ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----" --exclude-dir=.git . 2>/dev/null | head -5)
[ -z "$BAD" ] || fail "疑似密钥文件：$BAD"
[ -f .env ] && warn "存在 .env 文件，确认不要公开"
case "$(git ls-files | wc -l)" in 0) fail "没有可提交文件";; esac

step "附件"
ASSETS_FILE=/tmp/gh-assets.$SLUG
: > "$ASSETS_FILE"
if [ -n "$ASSETS" ]; then
  shopt -s nullglob
  printf '%s\n' "$ASSETS" | while IFS= read -r line; do
    [ -n "$line" ] || continue
    line="${line//\{version\}/$V}"
    matches=($line)
    if [ ${#matches[@]} -eq 0 ]; then printf '%s\n' "$line"; else printf '%s\n' "${matches[@]}"; fi
  done > "$ASSETS_FILE"
fi
SHA_FILE=/tmp/SHA256SUMS.$SLUG
: > "$SHA_FILE"
N_ASSET=0; H=""
if [ -s "$ASSETS_FILE" ]; then
  while IFS= read -r f; do
    [ -f "$f" ] || fail "附件不存在: $f"
    sha=$(sha256sum "$f" | awk '{print $1}')
    printf '%s  %s\n' "$sha" "$(basename "$f")" >> "$SHA_FILE"
    echo "  $(basename "$f")  sha256=$sha"
    H="$sha"; N_ASSET=$((N_ASSET+1))
  done < "$ASSETS_FILE"
  cp "$SHA_FILE" /tmp/SHA256SUMS.$SLUG.tmp
fi
EXPECTED=$N_ASSET
if [ "$N_ASSET" -gt 0 ]; then
  cp "$SHA_FILE" /tmp/SHA256SUMS
  echo "/tmp/SHA256SUMS" >> "$ASSETS_FILE"
  EXPECTED=$((N_ASSET+1))
fi
if [ "$DRY" = "1" ]; then
  if [ -n "$REMOTE_HEAD" ] && [ "$REPO_EXISTS" = "1" ]; then
    echo "  远端 $BRANCH head: ${REMOTE_HEAD:0:10}"
  fi
  write "STATE=dry-run"; write "LINK=(dry-run)"
  echo "✓ dry-run 通过：版本 $V，仓库 $REPO，附件 $N_ASSET 个 + SHA256SUMS（未推送、未上传）"
  exit 0
fi

step "提交"
git add -A
if ! git diff --cached --quiet 2>/dev/null; then
  git -c user.name=release-bot -c user.email=release-bot@users.noreply.github.com commit -m "release: $TAG" >>"$LOG" 2>&1 || fail "提交失败"
fi
HEAD_SHA=$(git rev-parse HEAD)

step "推送"
GH_TOKEN="$TOKEN" python3 - "$REPO" "$BRANCH" "$TAG" "$HEAD_SHA" "$CREATE" "$PUBLIC" <<'PY' >>"$LOG" 2>&1
import base64,json,os,subprocess,sys,time,urllib.error,urllib.request
repo,branch,tag,head_s,create,public=sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4],sys.argv[5],sys.argv[6]
tok=os.environ['GH_TOKEN']; API='https://api.github.com'
def call(m,p,b=None):
    data=json.dumps(b).encode() if b is not None else None
    req=urllib.request.Request(API+p,data=data,method=m,headers={'Authorization':f'Bearer {tok}','Accept':'application/vnd.github+json','Content-Type':'application/json','User-Agent':'dsh-publish'})
    with urllib.request.urlopen(req,timeout=120) as r: return json.loads(r.read().decode() or '{}')
def retry(fn,tries=4):
    last=None
    for i in range(tries):
        try: return fn()
        except urllib.error.HTTPError: raise
        except Exception as e:
            last=e; time.sleep(2*(i+1))
    raise last
if create=='1':
    try: call('GET',f'/repos/{repo}')
    except urllib.error.HTTPError:
        owner,name=repo.split('/')
        call('POST','/user/repos',{'name':name,'private':public!='1','description':name})
out=subprocess.run(['git','ls-files','-s','-z'],capture_output=True,check=True).stdout.decode()
tree=[]
for rec in out.split('\x00'):
    if not rec.strip(): continue
    meta,path=rec.split('\t',1); parts=meta.split()
    mode,sha=parts[0],parts[1]
    if mode not in ('100644','100755'):
        raise SystemExit(f'不支持的 git 模式 {mode}: {path}（子模块/符号链接不支持）')
    data=subprocess.run(['git','cat-file','-p',sha],capture_output=True).stdout
    blob=retry(lambda: call('POST',f'/repos/{repo}/git/blobs',{'content':base64.b64encode(data).decode(),'encoding':'base64'}))
    tree.append({'path':path,'mode':mode,'type':'blob','sha':blob['sha']})
t=call('POST',f'/repos/{repo}/git/trees',{'tree':tree})
parents=[]
try: parents=[call('GET',f'/repos/{repo}/git/ref/heads/{branch}')['object']['sha']]
except urllib.error.HTTPError: pass
body={'message':f'release: {tag}','tree':t['sha']}
if parents: body['parents']=parents
c=call('POST',f'/repos/{repo}/git/commits',body)
try:
    call('POST',f'/repos/{repo}/git/refs',{'ref':f'refs/heads/{branch}','sha':c['sha']})
except urllib.error.HTTPError as e:
    if e.code in (422,409):
        raise SystemExit('分支更新被拒（非快进）：先同步远端再发布')
    raise
call('POST',f'/repos/{repo}/git/refs',{'ref':f'refs/tags/{tag}','sha':c['sha']})
print('REMOTE_COMMIT',c['sha'])
PY
RC=$?
[ "$RC" = "0" ] || fail "推送失败（见 $LOG）"
NEW_SHA=$(grep '^REMOTE_COMMIT' "$LOG" | tail -1 | awk '{print $2}')
[ -n "$NEW_SHA" ] || fail "推送结果没有 commit sha"
git update-ref "refs/heads/$BRANCH" "$NEW_SHA" 2>/dev/null || true
git tag -f "$TAG" "$NEW_SHA" >/dev/null 2>&1 || true

# 未指定 notes 时默认读项目 CHANGELOG.md（否则 Release 正文会只剩「见仓库 CHANGELOG」）
if [ -z "$NOTES" ] && [ -z "$NOTES_FILE" ] && [ -f "CHANGELOG.md" ]; then
  NOTES_FILE="CHANGELOG.md"
fi
step "Release"
NOTES_TEXT="$NOTES"
if [ -z "$NOTES_TEXT" ] && [ -n "$NOTES_FILE" ] && [ -f "$NOTES_FILE" ]; then
  NOTES_TEXT=$(python3 - "$NOTES_FILE" <<'PY'
import sys,re
t=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
m=re.search(r'^##\s*\[?v?[0-9][^\n]*\n([\s\S]*?)(?=^##\s|\Z)',t,re.M)
print((m.group(1).strip() if m else t[:3000]))
PY
)
fi
BODY_JSON=/tmp/gh-rel.$SLUG.json
python3 - "$BODY_JSON" "$TAG" "$DISPLAY" "$V" "$NOTES_TEXT" "$SHA_FILE" <<'PY'
import json,sys
out,tag,display,v,notes,shafile=sys.argv[1:7]
lines=open(shafile,encoding='utf-8').read().strip().splitlines() if shafile else []
table='\n'.join(f'| `{l.split()[1]}` | `{l.split()[0]}` |' for l in lines if len(l.split())==2) or '| — | — |'
body=f"""**{display} {v}**

## 本版更新
{notes or '- 见仓库 CHANGELOG'}

## 附件与 SHA256
| 文件 | SHA256 |
|---|---|
{table}
"""
json.dump({'tag_name':tag,'name':f'{display} {v}','body':body},open(out,'w',encoding='utf-8'),ensure_ascii=False)
PY
RID=$(gh GET "/repos/$REPO/releases/tags/$TAG" 2>/dev/null | python3 -c "import json,sys;print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
if [ "$GEN_NOTES" = "1" ]; then
  PREV=$(gh GET "/repos/$REPO/releases?per_page=1" 2>/dev/null | python3 -c "import json,sys;a=json.load(sys.stdin);print(a[0]['tag_name'] if a else '')" 2>/dev/null)
  python3 - "$TAG" "$PREV" > /tmp/gh-gn.$SLUG.json <<'PYN'
import json,sys
print(json.dumps({'tag_name':sys.argv[1],'previous_tag_name':sys.argv[2]}))
PYN
  GN=$(gh POST "/repos/$REPO/releases/generate-notes" "/tmp/gh-gn.$SLUG.json" | python3 -c "import json,sys;print(json.load(sys.stdin).get('body',''))" 2>/dev/null || true)
  if [ -n "$GN" ]; then
    python3 - "$BODY_JSON" "$GN" <<'PYN'
import json,sys
p,notes=sys.argv[1],sys.argv[2]
d=json.load(open(p)); d['body']=(d.get('body','')+'\n\n## 自动生成的变更汇总（English / auto-generated）\n'+notes)[:60000]
json.dump(d,open(p,'w',encoding='utf-8'),ensure_ascii=False)
PYN
  fi
fi
python3 - "$BODY_JSON" "$DRAFT" "$PRERELEASE" <<'PYN'
import json,sys
p,d,pre=sys.argv[1],sys.argv[2],sys.argv[3]
j=json.load(open(p)); j['draft']=(d=='1'); j['prerelease']=(pre=='1')
json.dump(j,open(p,'w',encoding='utf-8'),ensure_ascii=False)
PYN
if [ -n "$RID" ]; then
  AC=$(gh GET "/repos/$REPO/releases/$RID/assets" 2>/dev/null | python3 -c "import json,sys;print(len(json.load(sys.stdin) or []))" 2>/dev/null)
  if { [ "$RESUME" = "1" ] || [ "$OVERWRITE_FILES" = "1" ]; } && [ "$AC" = "0" ]; then
    warn "续传：复用已存在的空 Release $TAG"
  elif [ "$OVERWRITE_FILES" = "1" ]; then
    warn "覆盖模式：删除 Release $TAG 已有附件后重传"
    gh GET "/repos/$REPO/releases/$RID/assets" | python3 -c "import json,sys;[print(a['id']) for a in json.load(sys.stdin)]" | while read -r aid; do
      [ -n "$aid" ] && gh DELETE "/repos/$REPO/releases/assets/$aid" >/dev/null 2>&1
    done
  else
    fail "Release $TAG 已存在（附件 $AC 个）：不能重复发布（可加 --resume 或 --overwrite-files）"
  fi
else
  RID=$(gh POST "/repos/$REPO/releases" "$BODY_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
fi
[ -n "$RID" ] || fail "建 Release 失败"
write "RELEASE_ID=$RID"

step "上传附件"
if [ -s "$ASSETS_FILE" ]; then
  while IFS= read -r f; do
    name=$(basename "$f"); ok=0
    for ip in 20.205.243.161 140.82.112.6 140.82.114.6; do
      code=$(printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" | curl -sS -o /tmp/up.json -w '%{http_code}' --max-time 900 \
        --config - --resolve "uploads.github.com:443:$ip" -X POST -H 'Accept: application/vnd.github+json' \
        -H 'Content-Type: application/octet-stream' --data-binary @"$f" \
        "$UPLOADS/repos/$REPO/releases/$RID/assets?name=$name")
      [ "$code" = "201" ] && { ok=1; echo "  ✓ $name"; break; }
    done
    [ "$ok" = "1" ] || fail "附件上传失败: $name（可加 --resume 重跑）"
  done < "$ASSETS_FILE"
fi

step "校验附件"
REMOTE=$(gh GET "/repos/$REPO/releases/$RID/assets")
python3 - "$REMOTE" "$EXPECTED" <<'PY'
import json,sys
a=json.loads(sys.argv[1]) if sys.argv[1].strip() else []
exp=int(sys.argv[2])
print('远端附件',len(a),'预期',exp)
for x in a: print(' ',x['name'],x['size'],x.get('state'))
if len(a)!=exp: raise SystemExit('附件数量不一致')
if exp and any((x.get('size') or 0)<=0 for x in a): raise SystemExit('有空附件')
PY
[ $? -eq 0 ] || fail "附件校验未通过"
write "STATE=done"
write "LINK=https://github.com/$REPO/releases/tag/$TAG"
URL="https://github.com/$REPO/releases/tag/$TAG"
echo "✓ 发布完成 $TAG → $URL"
if [ "$JSON_OUT" = "1" ]; then
  printf '{"ok":true,"tag":"%s","version":"%s","repo":"%s","url":"%s","assets":%s}\n' "$TAG" "$V" "$REPO" "$URL" "$EXPECTED"
fi
