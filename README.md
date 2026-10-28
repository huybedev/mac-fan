# MacFan

MacFan is a local macOS fan controller with a menu bar interface, manual RPM settings, and a configurable CPU temperature curve. Its interface supports Vietnamese, English, and Simplified Chinese; the language selector in the sidebar saves your choice. Fan control requires installation of its privileged helper through the app. Install the helper once and update it when replacing the app with a new build.

This version targets Apple Silicon and has been tested on Mac mini M4 (Mac16,10), macOS 26.5.1. The CPU/GPU sensor keys are specific to the M4 family; support for other models has not been established. macOS 14 or later and the Xcode Command Line Tools are required for building.

```sh
bash build.sh      # creates ../MacFan.app
bash test.sh       # behavioral tests; no fan writes
open ../MacFan.app
```

Choose **Install helper**, authenticate in the macOS prompt, then select **CPU temperature** or **Fixed RPM** and click **Apply**. Return control with **Return to macOS**. Closing the window keeps the app in the menu bar; quitting returns fan control. See the Vietnamese instructions below for the fan curve, safeguards, and removal procedure.

The SMC interface used here is not an Apple public fan-control API. Failure to read sensors, failure to write, disconnects, loss of heartbeat, and sleep cause the helper to attempt to return control to macOS; a recovery journal permits retries after a helper restart. At 90°C CPU/GPU the policy requests maximum fan speed. The application has not been tested under induced overheating or real sleep/wake conditions.

Ứng dụng SwiftUI dành cho Mac mini M4 (Mac16,10), macOS 14 trở lên, arm64. Đã đọc thực tế 1 quạt, 1.000–4.900 RPM, 12 cảm biến CPU và 8 cảm biến GPU trên macOS 26.5.1.

## Sử dụng

1. Mở `MacFan.app` (có thể đặt trong Applications).
2. Chọn **Cài bộ trợ giúp** và xác thực bằng hộp thoại quản trị macOS. Ứng dụng không lưu mật khẩu.
3. Chọn **Theo nhiệt độ CPU**, chỉnh các mốc hoặc chọn Êm/Cân bằng/Mát, rồi bấm **Áp dụng**.
4. Dùng **RPM cố định** để chỉnh tay; **Trả về macOS** để nhả điều khiển.

Chọn **Ngôn ngữ** ở thanh bên để chuyển giữa Tiếng Việt, English và 简体中文. Lựa chọn được lưu cho lần mở tiếp theo. Không cần cập nhật helper mỗi lần mở; chỉ cập nhật khi thay bản ứng dụng mới.

Đường nhiệt dùng nhiệt độ cao nhất trong các cảm biến CPU M4. Phần trăm là vị trí trong dải RPM: 0% = tối thiểu phần cứng, 100% = tối đa. Nội suy tuyến tính giữa các mốc. Tăng tốc ngay khi nhu cầu làm mát tăng; giảm tối đa 150 RPM mỗi chu kỳ 2 giây để hạn chế dao động tiếng quạt.

Chỉ các thiết lập đã bấm Áp dụng được lưu. Tùy chọn **Tự bật đường nhiệt khi mở** áp dụng đường nhiệt đã lưu ở lần mở tiếp theo. **Mở khi đăng nhập** dùng cơ chế Login Items của macOS. Đóng cửa sổ vẫn chạy trên thanh menu; chọn Thoát để dừng ứng dụng. Sau khi máy ngủ, cần bấm Áp dụng lại nếu muốn tiếp tục điều khiển.

CPU hoặc GPU từ 90°C yêu cầu tốc độ quạt tối đa ở cả chế độ đường nhiệt và chỉnh tay. Mất bất kỳ cảm biến đã phát hiện, lỗi đọc/ghi SMC, mất kết nối, không nhận heartbeat quá 12 giây, máy ngủ hoặc thoát sẽ yêu cầu trả quyền về macOS. Watchdog chạy trong helper; nhật ký phục hồi được ghi trước khi chiếm điều khiển để launchd có thể phục hồi khi helper khởi động lại. Nếu firmware từ chối phục hồi, helper giữ nhật ký và thử lại, giao diện hiển thị lỗi.

Tránh chạy đồng thời với phần mềm khác đang chỉnh quạt. MacFan từ chối bắt đầu khi đọc thấy quạt đã ở chế độ thủ công của phần mềm khác. Ứng dụng hiện nhắm đúng M4; không dùng danh sách cảm biến này làm giả định cho Mac đời khác.

## Bộ trợ giúp

Helper root chỉ cung cấp ba thao tác XPC có giới hạn: đọc trạng thái, áp dụng cấu hình đã kiểm tra, nhả quyền. Không có lệnh shell hay ghi khóa SMC tùy ý qua XPC. Hai phía xác minh CDHash của đúng bản thực thi; cấu hình xác minh và helper được cài root:wheel. Sau khi thay bản build, dùng **Cập nhật bộ trợ giúp** để đồng bộ chữ ký.

- `/Library/PrivilegedHelperTools/vn.huytran.MacFan.Helper`
- `/Library/LaunchDaemons/vn.huytran.MacFan.Helper.plist`
- `/Library/Application Support/MacFan/`

Để gỡ, chọn **Gỡ bộ trợ giúp…**, tắt Mở khi đăng nhập, rồi xóa app. Nếu chưa xác nhận phục hồi, trình gỡ giữ helper để tiếp tục thử trả quyền. Không cần tắt SIP hoặc cài kernel extension. Bản này ký ad hoc để chạy cục bộ, chưa được Apple notarize.

## Build và kiểm thử

Yêu cầu Xcode Command Line Tools, không có thư viện ngoài.

```sh
bash build.sh
bash test.sh
```

`build.sh` tạo `../MacFan.app`. `test.sh` chạy 23 bài kiểm thử hành vi dùng phần cứng giả lập và kiểm tra plist/script; các bài này không đổi quạt thật. Build cũng xác minh cú pháp và đối chiếu chữ ký CDHash của cả app lẫn helper.

Đọc phần cứng thật, không ghi:

```sh
../MacFan.app/Contents/Resources/MacFanHelper --probe
```

Sau khi cài helper và đóng phiên UI đang điều khiển, có thể kiểm thử tích hợp thật. Lệnh sau tạm chỉnh quạt lên 2.000 RPM, kiểm tra chế độ đường nhiệt, timeout/mất kết nối, rồi trả về macOS:

```sh
../MacFan.app/Contents/MacOS/MacFan --integration-test
```

Không dùng thời gian sleep/kill của test để suy ra bảo đảm với lỗi kernel, mất điện hoặc firmware. Cơ chế bảo vệ nhiệt phần cứng và macOS là các lớp độc lập; ứng dụng không thay đổi chúng.

## Nguồn tham khảo

Giao thức SMC không có API điều khiển quạt công khai của Apple. Bố cục gói 80 byte, kiểu dữ liệu, khóa cảm biến M4 và thao tác nhả quyền được đối chiếu với [Stats SMC](https://github.com/exelban/stats/blob/master/SMC/smc.swift) và [Stats Sensors](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift). Các phần dựa trên Stats tuân theo giấy phép MIT kèm tại `Resources/Stats-LICENSE.txt`. Logic điều khiển, XPC, helper, UI và kiểm thử được viết riêng cho ứng dụng này.
