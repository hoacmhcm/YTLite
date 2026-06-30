# YTLite / YouTube Plus IPA Build Notes

Ghi chú này tóm tắt quy trình đang dùng trong fork này để build file `.ipa`, các lỗi đã gặp, và patch đang dùng cho nút download của YTPlus `5.2b4`.

## Mục tiêu

- Build một file `YouTubePlus_5.2b4.ipa` từ YouTube IPA đã decrypted.
- Inject YTPlus `5.2b4` và các tweak phụ qua GitHub Actions.
- Patch nút download vì YouTube mới đổi identifier UI, làm YTPlus `5.2b4` không bắt đúng button cũ.

## File đầu vào cần có

Workflow không decrypt IPA. Trước khi chạy Actions cần có:

- YouTube IPA đã decrypted, ví dụ: `com.google.ios.youtube-21.26.4-Decrypted.ipa`
- Direct HTTPS download URL tới file đó.
- Tweak version: dùng `5.2b4` cho bản free/patched trong fork này.

Không đưa file `.ipa` lên repo Git. File IPA local đang được ignore qua `.git/info/exclude`.

## Upload IPA ở đâu

Các host đã test ổn:

### Filebin

Dùng link trực tiếp tới file, không dùng link folder.

Đúng:

```text
https://filebin.net/<bin-id>/<filename>.ipa
```

Ví dụ:

```text
https://filebin.net/aecsqbxp2g8jvc0l/com.google.ios.youtube-21.26.4-Decrypted.ipa
```

Sai:

```text
https://filebin.net/aecsqbxp2g8jvc0l
```

Link folder trả về HTML page, workflow `wget` không dùng được để download IPA.

### Dropbox

Dùng shared link nhưng đổi cuối URL sang direct download:

```text
?dl=1
```

Ví dụ format đúng:

```text
https://www.dropbox.com/s/<id>/<filename>.ipa?dl=1
```

Không dùng `?dl=0` vì đó thường là link preview/web page.

## Cách test URL trước khi điền vào Actions

Test bằng `curl` hoặc `wget`. File IPA thực chất là ZIP, nên MIME hợp lệ thường là `application/zip`.

```bash
curl -L --range 0-1023 -o /tmp/youtube-head.ipa "<IPA_DIRECT_URL>"
file --mime-type /tmp/youtube-head.ipa
```

Kết quả ổn:

```text
application/zip
```

Nếu trả về `text/html`, link không phải direct file.

## Chạy GitHub Actions

Workflow chính để ra file `.ipa`:

```text
Actions -> Create YouTube Plus app -> Run workflow
```

Field cần chú ý:

- `Direct https:// download URL to the decrypted YouTube IPA file`: điền direct link IPA từ Filebin/Dropbox.
- `The version of the tweak to use`: điền `5.2b4`.
- `BundleID`: thường để `com.google.ios.youtube`.
- `App Name`: thường để `YouTube`.

Workflow `Generate TrollFools/Cyan files` chỉ tạo `.cyan` hoặc TrollFools zip, không phải file IPA cuối.

## Các fix đã thêm vào fork

### Validate IPA URL

File:

```text
.github/workflows/main.yml
.github/workflows/ytp_beta.yml
```

Đã thêm job `Validate Inputs` để bắt lỗi khi nhập nhầm field, ví dụ nhập `5.2b5` vào ô IPA URL. URL IPA phải bắt đầu bằng `http://` hoặc `https://`.

### Homebrew tap trust trên macOS runner

File:

```text
.github/workflows/_build_tweaks.yml
.github/workflows/cyan_ts.yml
```

Đã thêm:

```bash
brew untap aws/tap || true
```

Lý do: GitHub macOS runner báo tap `aws/tap` không trusted, làm `brew install` fail.

### Patch download button identifier cho YTPlus 5.2b4

File chính:

```text
scripts/patch-ytplus-download-id.sh
```

Workflow patch trực tiếp file IPA sau khi `cyan` inject xong:

```text
.github/workflows/main.yml
.github/workflows/ytp_beta.yml
```

Step:

```text
Patch injected YouTube Plus download button identifier
```

Lý do: để `cyan` xử lý `.deb` gốc trước, sau đó mới patch `Payload/YouTube.app/Frameworks/YTLite.dylib` trong IPA. Cách này tránh rủi ro repack `.deb` làm `cyan` không inject đủ file.

### Fix corrupt ytplus.deb sau khi patch

Lỗi đã gặp:

```text
IndexError: list index out of range
data_tar = glob(f"{t2}/data.*")[0]
```

Nguyên nhân thực tế: trên `macos-26-arm64`, `ar -cr patched.deb ...` tạo archive kiểu static library có `__.SYMDEF SORTED`, làm `ytplus.deb` còn khoảng `96B` và mất `data.tar.*`. `cyan` extract deb nên không thấy `data.*`.

Fix trước đó: `scripts/patch-ytplus-download-id.sh` không dùng `ar -cr` để repack deb nữa, mà ghi ar archive chuẩn Debian bằng Python. Script cũng validate lại `patched.deb` phải có `data.*`.

Fix mới hơn: workflow không patch/repack `ytplus.deb` trước khi inject nữa. Package job inject `.deb` gốc bằng `cyan`, sau đó chạy:

```bash
scripts/patch-injected-ipa.sh YouTubePlus_5.2b4.ipa
```

Script này mở IPA, patch `Payload/YouTube.app/Frameworks/YTLite.dylib`, rồi zip lại IPA.

Ngoài ra `_build_tweaks.yml` có thêm step `Validate tweak artifacts` để fail sớm nếu `.deb` nào không còn `data.*`.

### Validate IPA đã inject thật sự có YTLite

File:

```text
.github/workflows/main.yml
.github/workflows/ytp_beta.yml
.github/workflows/_build_tweaks.yml
```

Đã thêm check để tránh trường hợp workflow vẫn tạo `.ipa` nhưng thực tế chỉ là YouTube gốc kèm Safari extension, không có YTPlus.

IPA build đúng phải có ít nhất:

```text
Payload/YouTube.app/Frameworks/YTLite.dylib
Payload/YouTube.app/Frameworks/CydiaSubstrate.framework/CydiaSubstrate
Payload/YouTube.app/YTLite.bundle/Info.plist
```

Và main executable phải load:

```text
@rpath/YTLite.dylib
```

Nếu thiếu một trong hai, Actions sẽ fail trước bước release.

## Patch nút download nằm ở đâu

Patch không nằm trong source Logos `.x` của repo này. Với YTPlus `5.2b4`, workflow tải prebuilt binary:

```text
ytplus.deb
```

Trong `.deb` có binary:

```text
Library/MobileSubstrate/DynamicLibraries/YTLite.dylib
```

Script `scripts/patch-ytplus-download-id.sh` extract `.deb`, mở `YTLite.dylib` dạng binary, rồi replace string:

```text
old: id.ui.add_to.offline.button
new: id.video.add_to.button
```

Đoạn chính trong script:

```python
old = b"id.ui.add_to.offline.button"
new = b"id.video.add_to.button"
```

Sau khi replace string, script cũng patch lại CFString length từ độ dài old sang độ dài new. Nếu chỉ đổi bytes mà không sửa length, binary có thể vẫn đọc sai chuỗi.

Lý do phải patch binary: source public/tag `5.2b4` không chứa đầy đủ implementation download manager đang nằm trong release `.deb`. Do đó không sửa trực tiếp bằng Logos source được; với bản `5.2b4` đang dùng, cách thực tế là patch `YTLite.dylib` trong `.deb`.

## Vì sao YouTube mới làm nút download hỏng

YTPlus `5.2b4` tìm action/button theo identifier cũ:

```text
id.ui.add_to.offline.button
```

YouTube mới đổi UI/action identifier sang:

```text
id.video.add_to.button
```

Khi identifier không khớp, hook/menu injection của YTPlus không gắn đúng vào button download mới. Patch hiện tại chỉ remap identifier cũ sang identifier mới trong binary `YTLite.dylib`.

Nếu YouTube tiếp tục đổi UI/id khác trong tương lai, cần lặp lại quy trình:

1. Lấy YouTube IPA decrypted bản mới.
2. Build/inject thử.
3. Nếu button/tính năng hỏng, tìm identifier mới trong app/binary.
4. Cập nhật `old/new` trong `scripts/patch-ytplus-download-id.sh` hoặc tạo patch mới tương ứng.

## Commits quan trọng

```text
2f3c117 Patch YTPlus download button identifier
a304b0e Fix Homebrew tap trust in Actions
c6dca64 Validate IPA URL workflow inputs
80045e9 Fix YTPlus deb repack for cyan injection
```
